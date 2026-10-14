-- =============================================================================
-- SPM: API-Schlüssel eines Kursanbieters hinterlegen (interaktiv, als Schema SPM)
--
--   sql -name spm @install/set_provider_key.sql
--
-- Die Eingabe ist unsichtbar und wird nicht angezeigt. Der Schlüssel landet in
-- SPM_SECRET (nie in Quelltext, SPM_CONFIG, APEX-Seiten oder Logs).
-- Leere Eingabe löscht den hinterlegten Schlüssel.
-- =============================================================================

set verify off
set feedback off
set serveroutput on
whenever sqlerror exit failure rollback

accept PROVIDER char default 'TWELVEDATA' prompt 'Provider [TWELVEDATA]: '
accept API_KEY  char prompt 'API-Schlüssel (Eingabe unsichtbar): ' hide

begin
    spm_prov.set_secret(upper(trim('&PROVIDER')), trim('&API_KEY'));
    commit;
    dbms_output.put_line('Schlüssel für ' || upper(trim('&PROVIDER')) || ' gespeichert.');
end;
/

undefine API_KEY
exit
