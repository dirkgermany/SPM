-- =============================================================================
-- SPM: LILAM in das SPM-Schema installieren
--
-- LILAM wird nicht kopiert, sondern aus einem LILAM-Checkout installiert
-- (Variable LILAM_HOME aus install.sql). LILAM legt seine Tabellen beim ersten
-- Aufruf selbst im Schema an.
-- =============================================================================

@"&LILAM_HOME/source/install.sql"

whenever sqlerror exit failure rollback

-- SPM benötigt MARK_EVENT mit Messwert (p_value), Wert-EWMA und VAL_-Regeln
declare
    l_count pls_integer;
begin
    select count(*) into l_count
    from   user_arguments
    where  package_name  = 'LILAM'
    and    object_name   = 'MARK_EVENT'
    and    argument_name = 'P_VALUE';

    if l_count = 0 then
        raise_application_error(-20000,
            'Der installierte LILAM-Stand kennt MARK_EVENT(p_value) nicht. '
         || 'SPM benötigt LILAM mit Messwerten (Branch messwerte oder neuer).');
    end if;
    dbms_output.put_line('LILAM ' || lilam.lilam_version || ' mit MARK_EVENT(p_value) gefunden.');
end;
/
