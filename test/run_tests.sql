-- =============================================================================
-- SPM: automatisierte Tests mit dem Mock-Provider (keine Netzwerkzugriffe)
--
-- Aufruf (SQLcl / SQL*Plus), angemeldet als Schema SPM:
--   @test/run_tests.sql
--
-- Legt Test-Instrumente TST* an (danach inaktiv), löscht vorher deren Kurse und die
-- Läufe mit Trigger TEST. LILAM-Prozesse der Tests bleiben zur Analyse erhalten.
-- =============================================================================

set serveroutput on size unlimited
set feedback off
whenever sqlerror exit failure rollback

prompt === Testpaket kompilieren ===
@@spm_test.pks
@@spm_test.pkb

declare
    l_count pls_integer;
begin
    select count(*) into l_count from user_objects where object_name = 'SPM_TEST' and status <> 'VALID';
    if l_count > 0 then
        raise_application_error(-20000, 'SPM_TEST ist ungültig, siehe user_errors.');
    end if;
end;
/

prompt === Mock-Antworten laden ===
@@fixtures/mock_responses.sql

prompt === Tests ===
exec spm_test.run_all
