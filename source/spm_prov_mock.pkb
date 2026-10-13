create or replace package body spm_prov_mock as

    C_TS_FORMAT constant varchar2(30) := 'YYYY-MM-DD"T"HH24:MI:SS"Z"';

    -- Nächste vorbereitete Antwort; FALSE, wenn es zum Symbol keine gibt
    function next_response(p_provider_symbol varchar2, o_resp out spm_mock_response%rowtype) return boolean is
        l_last spm_mock_state.last_seq_no%type;
    begin
        select max(last_seq_no) into l_last from spm_mock_state where provider_symbol = p_provider_symbol;

        begin
            select * into o_resp
            from   spm_mock_response
            where  provider_symbol = p_provider_symbol
            and    seq_no > nvl(l_last, -1)
            order  by seq_no
            fetch  first 1 row only;
        exception
            when no_data_found then
                -- am Ende: von vorn
                begin
                    select * into o_resp
                    from   spm_mock_response
                    where  provider_symbol = p_provider_symbol
                    order  by seq_no
                    fetch  first 1 row only;
                exception
                    when no_data_found then
                        return false;
                end;
        end;

        merge into spm_mock_state s
        using (select p_provider_symbol sym, o_resp.seq_no seq from dual) n
        on (s.provider_symbol = n.sym)
        when matched then update set s.last_seq_no = n.seq
        when not matched then insert (provider_symbol, last_seq_no) values (n.sym, n.seq);

        return true;
    end next_response;

    function fill_placeholders(p_body clob) return clob is
        l_now     date := cast(spm_prov.utc_now as date);
        l_body    clob := p_body;
        l_token   varchar2(30);
        l_minutes number;
    begin
        -- {NOW-<n>M}: n Minuten vor jetzt
        loop
            l_token := regexp_substr(l_body, '\{NOW-[0-9]{1,6}M\}');
            exit when l_token is null;
            l_minutes := to_number(regexp_substr(l_token, '[0-9]+'));
            l_body := replace(l_body, l_token, to_char(l_now - l_minutes / 1440, C_TS_FORMAT));
        end loop;

        return replace(replace(l_body,
                   '{NOW}',            to_char(l_now, C_TS_FORMAT)),
                   '{YESTERDAY_NOON}', to_char(trunc(l_now) - 0.5, C_TS_FORMAT));
    end fill_placeholders;

    -- Zufallsbewegung um den letzten gespeicherten Kurs
    function random_walk(p_instrument spm_instrument%rowtype) return clob is
        l_last  number;
        l_price number;
    begin
        select max(price) keep (dense_rank last order by quote_ts_utc)
        into   l_last
        from   spm_price
        where  instrument_id = p_instrument.instrument_id;

        l_price := round(nvl(l_last, 100)
                         * (1 + dbms_random.normal * spm_cfg.get_number('MOCK_VOLATILITY', 0.01)), 4);
        l_price := greatest(l_price, 0.01);

        return json_object(
                   'symbol'    value p_instrument.provider_symbol,
                   'price'     value l_price,
                   'currency'  value p_instrument.currency,
                   'timestamp' value to_char(cast(spm_prov.utc_now as date), C_TS_FORMAT)
                   returning clob);
    end random_walk;

    procedure parse_body(p_body clob, p_provider_symbol varchar2, p_quote in out nocopy spm_prov.t_quote) is
        l_obj  json_object_t;
        l_elem json_element_t;
    begin
        p_quote.outcome := spm_prov.C_PARSE_ERROR;

        begin
            l_obj := json_object_t.parse(p_body);
        exception
            when others then
                p_quote.message := 'Antwort ist kein gültiges JSON-Objekt: ' || dbms_lob.substr(p_body, 100, 1);
                return;
        end;

        if l_obj.has('symbol') and l_obj.get_string('symbol') <> p_provider_symbol then
            p_quote.message := 'Antwort gehört zu Symbol ' || substr(l_obj.get_string('symbol'), 1, 40);
            return;
        end if;

        if not l_obj.has('price') or l_obj.get('price').is_null then
            p_quote.message := 'Pflichtfeld price fehlt';
            return;
        end if;
        l_elem := l_obj.get('price');
        if l_elem.is_number then
            p_quote.price := l_obj.get_number('price');
        elsif l_elem.is_string then
            p_quote.price := spm_prov.parse_decimal(l_obj.get_string('price'));
        end if;
        if p_quote.price is null then
            p_quote.message := 'price ist keine Zahl: ' || substr(l_elem.to_string, 1, 50);
            return;
        end if;

        p_quote.currency := substr(l_obj.get_string('currency'), 1, 3);
        if p_quote.currency is null then
            p_quote.message := 'Pflichtfeld currency fehlt';
            return;
        end if;

        p_quote.quote_ts_utc := spm_prov.parse_iso_utc(l_obj.get_string('timestamp'));
        if p_quote.quote_ts_utc is null then
            p_quote.message := 'timestamp fehlt oder ist ungültig: ' || substr(l_obj.get_string('timestamp'), 1, 50);
            return;
        end if;

        p_quote.outcome := spm_prov.C_OK;
        p_quote.message := null;
    end parse_body;

    function fetch_quote(p_instrument spm_instrument%rowtype) return spm_prov.t_quote is
        l_resp  spm_mock_response%rowtype;
        l_quote spm_prov.t_quote;
    begin
        if not next_response(p_instrument.provider_symbol, l_resp) then
            l_resp.http_status      := 200;
            l_resp.simulate_timeout := 'N';
            l_resp.body             := random_walk(p_instrument);
        end if;

        l_quote.http_status := l_resp.http_status;

        if l_resp.simulate_timeout = 'Y' then
            l_quote.outcome     := spm_prov.C_TIMEOUT;
            l_quote.http_status := null;
            l_quote.message     := 'Mock: Zeitüberschreitung (simuliert)';
        elsif l_resp.http_status = 0 then
            l_quote.outcome     := spm_prov.C_SYSTEMIC;
            l_quote.http_status := null;
            l_quote.message     := 'Mock: keine Verbindung (simuliert, z. B. ACL oder TLS)';
        elsif l_resp.http_status = 429 then
            l_quote.outcome := spm_prov.C_QUOTA;
            l_quote.message := 'HTTP 429: Quotenlimit erreicht';
        elsif l_resp.http_status <> 200 then
            l_quote.outcome := spm_prov.C_HTTP_ERROR;
            l_quote.message := 'HTTP ' || l_resp.http_status || ': ' || dbms_lob.substr(l_resp.body, 200, 1);
        else
            parse_body(fill_placeholders(l_resp.body), p_instrument.provider_symbol, l_quote);
        end if;

        return l_quote;
    end fetch_quote;

    procedure reset_state(p_provider_symbol varchar2 default null) is
    begin
        delete from spm_mock_state where p_provider_symbol is null or provider_symbol = p_provider_symbol;
    end reset_state;

end spm_prov_mock;
/
