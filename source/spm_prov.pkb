create or replace package body spm_prov as

    function fetch_quote(p_instrument spm_instrument%rowtype) return t_quote is
        l_active spm_provider.is_active%type;
        l_quote  t_quote;
    begin
        begin
            select is_active into l_active from spm_provider where provider_code = p_instrument.provider_code;
        exception
            when no_data_found then
                l_active := null;
        end;

        if l_active is null or l_active <> 'Y' then
            l_quote.outcome := C_SYSTEMIC;
            l_quote.message := 'Provider ' || p_instrument.provider_code || ' unbekannt oder inaktiv';
            return l_quote;
        end if;

        case p_instrument.provider_code
            when 'MOCK' then
                l_quote := spm_prov_mock.fetch_quote(p_instrument);
            when 'TWELVEDATA' then
                l_quote := spm_prov_twelvedata.fetch_quote(p_instrument);
            else
                l_quote.outcome := C_SYSTEMIC;
                l_quote.message := 'Für Provider ' || p_instrument.provider_code || ' gibt es keinen Adapter';
        end case;

        l_quote.message := sanitize(l_quote.message);
        return l_quote;
    end fetch_quote;

    function utc_now return timestamp is
    begin
        return sys_extract_utc(systimestamp);
    end utc_now;

    function parse_decimal(p_text varchar2) return number is
        l_text varchar2(100) := trim(p_text);
    begin
        if l_text is null or length(l_text) > 60
           or not regexp_like(l_text, '^-?[0-9]{1,30}(\.[0-9]{1,20})?$') then
            return null;
        end if;
        return to_number(l_text, '999999999999999999999999999990D99999999999999999999',
                         'NLS_NUMERIC_CHARACTERS=''.,''');
    end parse_decimal;

    function parse_iso_utc(p_text varchar2) return timestamp is
        l_text varchar2(100) := trim(p_text);
    begin
        if l_text is null
           or not regexp_like(l_text, '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$') then
            return null;
        end if;
        -- Sekundenbruchteile verwerfen, Z als +00:00
        l_text := regexp_replace(l_text, '\.[0-9]+', '');
        l_text := regexp_replace(l_text, 'Z$', '+00:00');
        return sys_extract_utc(to_timestamp_tz(l_text, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'));
    exception
        when others then
            return null; -- z. B. 2026-02-30
    end parse_iso_utc;

    function sanitize(p_text varchar2, p_max_len pls_integer default 400) return varchar2 is
    begin
        return substr(regexp_replace(p_text, '(api_?key|token|secret|password)=[^&[:space:]"'']*', '\1=***', 1, 0, 'i'),
                      1, p_max_len);
    end sanitize;

    function credential_name(p_provider_code varchar2) return varchar2 is
        l_name spm_provider.credential_name%type;
    begin
        select credential_name into l_name from spm_provider where provider_code = p_provider_code;
        if l_name is null then
            raise_application_error(-20100, 'Provider ' || p_provider_code || ' hat keinen CREDENTIAL_NAME');
        end if;
        return l_name;
    exception
        when no_data_found then
            raise_application_error(-20100, 'Provider ' || p_provider_code || ' unbekannt');
    end credential_name;

    procedure set_secret(p_provider_code varchar2, p_secret varchar2) is
        l_name spm_secret.credential_name%type := credential_name(p_provider_code);
    begin
        if trim(p_secret) is null then
            delete from spm_secret where credential_name = l_name;
        else
            merge into spm_secret s
            using (select l_name n, trim(p_secret) v from dual) x
            on (s.credential_name = x.n)
            when matched then update set s.secret_value = x.v, s.updated_at = systimestamp
            when not matched then insert (credential_name, secret_value) values (x.n, x.v);
        end if;
    end set_secret;

    function get_secret(p_provider_code varchar2) return varchar2 is
        l_value spm_secret.secret_value%type;
    begin
        select max(secret_value) into l_value
        from   spm_secret
        where  credential_name = (select credential_name from spm_provider where provider_code = p_provider_code);
        return l_value;
    end get_secret;

    procedure http_get(
        p_url         varchar2,
        p_auth_header varchar2,
        p_quote       in out nocopy t_quote,
        o_body        out nocopy clob
    ) is
        l_max  pls_integer := spm_cfg.get_number('HTTP_MAX_BODY_CHARS', 32000);
        l_req  utl_http.req;
        l_resp utl_http.resp;
        l_open boolean := false;
        l_buf  varchar2(32767);
        l_code pls_integer;
    begin
        utl_http.set_wallet(spm_cfg.get_text('HTTPS_WALLET', 'system:'));
        utl_http.set_transfer_timeout(spm_cfg.get_number('HTTP_TIMEOUT_SECONDS', 10));
        utl_http.set_detailed_excp_support(true);
        utl_http.set_response_error_check(false);

        l_req := utl_http.begin_request(p_url, 'GET', 'HTTP/1.1');
        utl_http.set_header(l_req, 'User-Agent', 'SPM Stock Watch');
        utl_http.set_header(l_req, 'Accept', 'application/json');
        if p_auth_header is not null then
            utl_http.set_header(l_req, 'Authorization', p_auth_header);
        end if;

        l_resp := utl_http.get_response(l_req);
        l_open := true;
        p_quote.http_status := l_resp.status_code;
        utl_http.set_body_charset(l_resp, 'UTF-8');

        dbms_lob.createtemporary(o_body, true);
        begin
            loop
                utl_http.read_text(l_resp, l_buf, 8000);
                if dbms_lob.getlength(o_body) + length(l_buf) > l_max then
                    exit; -- Rest verwerfen; der Adapter meldet ggf. PARSE_ERROR
                end if;
                dbms_lob.writeappend(o_body, length(l_buf), l_buf);
            end loop;
        exception
            when utl_http.end_of_body then
                null;
        end;
        utl_http.end_response(l_resp);
    exception
        when others then
            if l_open then
                begin utl_http.end_response(l_resp); exception when others then null; end;
            end if;
            o_body := null;
            l_code := utl_http.get_detailed_sqlcode;
            -- ORA-29276 Transfer-Timeout, ORA-12535/ORA-12170 Verbindungs-Timeout
            if sqlcode = -29276 or l_code in (-29276, -12535, -12170) then
                p_quote.outcome := C_TIMEOUT;
            else
                p_quote.outcome := C_SYSTEMIC;
            end if;
            p_quote.http_status := null;
            p_quote.message := sanitize(nvl(utl_http.get_detailed_sqlerrm, sqlerrm));
    end http_get;

end spm_prov;
/
