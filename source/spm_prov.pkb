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

end spm_prov;
/
