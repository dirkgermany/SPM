create or replace package body spm_prov_twelvedata as

    C_PROVIDER constant varchar2(20)  := 'TWELVEDATA';
    C_BASE_URL constant varchar2(100) := 'https://api.twelvedata.com';

    function ticker(p_provider_symbol varchar2) return varchar2 is
    begin
        return regexp_substr(p_provider_symbol, '^[^:]+');
    end ticker;

    function quote_url(p_base_url varchar2, p_provider_symbol varchar2) return varchar2 is
        l_mic varchar2(20) := regexp_substr(p_provider_symbol, ':(.+)$', 1, 1, null, 1);
    begin
        return rtrim(nvl(p_base_url, C_BASE_URL), '/') || '/quote?symbol='
            || utl_url.escape(ticker(p_provider_symbol), true, 'UTF-8')
            || case when l_mic is not null then '&mic_code=' || utl_url.escape(l_mic, true, 'UTF-8') end;
    end quote_url;

    function epoch_utc(p_seconds number) return timestamp is
    begin
        if p_seconds is null or p_seconds <= 0 then
            return null;
        end if;
        return timestamp '1970-01-01 00:00:00' + numtodsinterval(trunc(p_seconds), 'second');
    end epoch_utc;

    -- Zahl als JSON-Zahl oder -Text
    function get_num(p_obj json_object_t, p_key varchar2) return number is
        l_elem json_element_t;
    begin
        if not p_obj.has(p_key) then
            return null;
        end if;
        l_elem := p_obj.get(p_key);
        if l_elem.is_number then
            return p_obj.get_number(p_key);
        elsif l_elem.is_string then
            return spm_prov.parse_decimal(p_obj.get_string(p_key));
        end if;
        return null;
    end get_num;

    function parse_response(
        p_http_status     pls_integer,
        p_body            clob,
        p_provider_symbol varchar2
    ) return spm_prov.t_quote is
        l_quote spm_prov.t_quote;
        l_obj   json_object_t;
        l_code  pls_integer;
        l_text  varchar2(400);
    begin
        l_quote.http_status := p_http_status;
        l_quote.outcome     := spm_prov.C_PARSE_ERROR;

        begin
            l_obj := json_object_t.parse(p_body);
        exception
            when others then
                l_obj := null;
        end;

        -- Fehler: HTTP-Status oder {"code":..,"message":..,"status":"error"} (auch bei HTTP 200)
        if l_obj is not null and l_obj.has('status') and l_obj.get_string('status') = 'error' then
            l_code := nvl(get_num(l_obj, 'code'), p_http_status);
            l_text := substr(l_obj.get_string('message'), 1, 300);
        elsif nvl(p_http_status, 0) <> 200 then
            l_code := p_http_status;
            l_text := dbms_lob.substr(p_body, 200, 1);
        end if;

        if l_code is not null then
            l_quote.outcome := case l_code
                                   when 429 then spm_prov.C_QUOTA
                                   when 401 then spm_prov.C_SYSTEMIC
                                   else spm_prov.C_HTTP_ERROR
                               end;
            l_quote.message := 'HTTP ' || l_code || ': ' || l_text;
            return l_quote;
        end if;

        if l_obj is null then
            l_quote.message := 'Antwort ist kein gültiges JSON-Objekt: ' || dbms_lob.substr(p_body, 100, 1);
            return l_quote;
        end if;

        if l_obj.has('symbol') and upper(l_obj.get_string('symbol')) <> upper(ticker(p_provider_symbol)) then
            l_quote.message := 'Antwort gehört zu Symbol ' || substr(l_obj.get_string('symbol'), 1, 40);
            return l_quote;
        end if;

        l_quote.price := get_num(l_obj, 'close');
        if l_quote.price is null then
            l_quote.message := 'Pflichtfeld close fehlt oder ist keine Zahl';
            return l_quote;
        end if;

        l_quote.currency := substr(l_obj.get_string('currency'), 1, 3);
        if l_quote.currency is null then
            l_quote.message := 'Pflichtfeld currency fehlt';
            return l_quote;
        end if;

        l_quote.quote_ts_utc := epoch_utc(nvl(get_num(l_obj, 'last_quote_at'), get_num(l_obj, 'timestamp')));
        if l_quote.quote_ts_utc is null then
            l_quote.message := 'Zeitstempel (last_quote_at/timestamp) fehlt oder ist ungültig';
            return l_quote;
        end if;

        l_quote.outcome := spm_prov.C_OK;
        l_quote.message := null;
        return l_quote;
    end parse_response;

    function fetch_quote(p_instrument spm_instrument%rowtype) return spm_prov.t_quote is
        l_quote spm_prov.t_quote;
        l_key   spm_secret.secret_value%type := spm_prov.get_secret(C_PROVIDER);
        l_base  spm_provider.base_url%type;
        l_body  clob;
    begin
        if l_key is null then
            l_quote.outcome := spm_prov.C_SYSTEMIC;
            l_quote.message := 'Kein API-Schlüssel für ' || C_PROVIDER || ' hinterlegt (install/set_provider_key.sql)';
            return l_quote;
        end if;

        select base_url into l_base from spm_provider where provider_code = C_PROVIDER;

        spm_prov.http_get(quote_url(l_base, p_instrument.provider_symbol), 'apikey ' || l_key, l_quote, l_body);
        if l_quote.outcome is not null then
            return l_quote; -- Transportfehler
        end if;

        return parse_response(l_quote.http_status, l_body, p_instrument.provider_symbol);
    end fetch_quote;

end spm_prov_twelvedata;
/
