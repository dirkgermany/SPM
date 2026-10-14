-- =============================================================================
-- SPM: Pakete kompilieren (Reihenfolge nach Abhängigkeit)
-- =============================================================================

-- Quelltexte enthalten & (HTML-Entities in spm_notify): keine Substitutionsvariablen
set define off

@@../source/spm_cfg.pks
@@../source/spm_prov.pks
@@../source/spm_prov_mock.pks
@@../source/spm_watchlist.pks
@@../source/spm_poll.pks
@@../source/spm_watchdog.pks
@@../source/spm_notify.pks
@@../source/spm_apex.pks
@@../source/spm_rules.pks
@@../source/spm_job.pks

@@../source/spm_cfg.pkb
@@../source/spm_prov.pkb
@@../source/spm_prov_mock.pkb
@@../source/spm_watchlist.pkb
@@../source/spm_poll.pkb
@@../source/spm_rules.pkb
@@../source/spm_job.pkb
@@../source/spm_watchdog.pkb
@@../source/spm_notify.pkb
@@../source/spm_apex.pkb

set define on

-- Abbruch, wenn ein SPM-Paket ungültig ist
declare
    l_invalid varchar2(4000);
begin
    select listagg(object_name || ' ' || object_type, ', ') within group (order by object_name)
    into   l_invalid
    from   user_objects
    where  object_name like 'SPM\_%' escape '\'
    and    object_type in ('PACKAGE', 'PACKAGE BODY')
    and    object_name <> 'SPM_TEST'   -- kompiliert test/run_tests.sql
    and    status <> 'VALID';

    if l_invalid is not null then
        raise_application_error(-20000, 'Ungültige SPM-Objekte: ' || l_invalid
                                     || ' (siehe user_errors).');
    end if;
end;
/
