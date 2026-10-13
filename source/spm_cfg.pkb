create or replace package body spm_cfg as

    function get_text(p_name varchar2, p_default varchar2 default null) return varchar2 is
        l_value spm_config.param_value%type;
    begin
        select param_value into l_value from spm_config where param_name = upper(p_name);
        return coalesce(l_value, p_default);
    exception
        when no_data_found then
            return p_default;
    end get_text;

    function get_number(p_name varchar2, p_default number default null) return number is
        l_text spm_config.param_value%type := trim(get_text(p_name));
    begin
        if l_text is null or not regexp_like(l_text, '^-?[0-9]+(\.[0-9]+)?$') then
            return p_default;
        end if;
        return to_number(l_text, '999999999999999999990D999999999999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
    end get_number;

end spm_cfg;
/
