create or replace package spm_cfg as
    -- Lesen der Konfiguration aus SPM_CONFIG

    function get_text(p_name varchar2, p_default varchar2 default null) return varchar2;

    -- Zahlen mit Dezimalpunkt; ungültige Werte liefern p_default
    function get_number(p_name varchar2, p_default number default null) return number;

end spm_cfg;
/
