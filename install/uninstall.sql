-- =============================================================================
-- SPM: Deinstallation (angemeldet als Schema SPM)
--
-- Entfernt die SPM-Pakete. Tabellen und Daten bleiben erhalten, außer
-- SPM_DROP_DATA = 'J' (nicht rückgängig zu machen).
-- LILAM bleibt installiert; entfernen mit <LILAM>/source/uninstall.sql.
-- Das Schema selbst entfernt ein Administrator (DROP USER SPM CASCADE).
-- =============================================================================

define SPM_DROP_DATA = 'N'

set serveroutput on
set verify off

declare
    procedure drop_object(p_type varchar2, p_name varchar2) is
    begin
        execute immediate 'drop ' || p_type || ' ' || p_name;
        dbms_output.put_line('Entfernt: ' || p_type || ' ' || p_name);
    exception
        when others then
            if sqlcode not in (-4043, -942) then -- existiert nicht
                raise;
            end if;
    end drop_object;
begin
    for p in (select column_value name from table(sys.odcivarchar2list(
                  'SPM_TEST', 'SPM_RULES', 'SPM_POLL', 'SPM_WATCHLIST', 'SPM_PROV_MOCK', 'SPM_PROV', 'SPM_CFG'))) loop
        drop_object('package', p.name);
    end loop;

    if '&SPM_DROP_DATA' = 'J' then
        for t in (select column_value name from table(sys.odcivarchar2list(
                      'SPM_RULE', 'SPM_PRICE', 'SPM_RUN', 'SPM_INSTRUMENT', 'SPM_PROVIDER', 'SPM_CONFIG',
                      'SPM_MOCK_RESPONSE', 'SPM_MOCK_STATE'))) loop
            drop_object('table', t.name || ' purge');
        end loop;
    else
        dbms_output.put_line('Tabellen bleiben erhalten (SPM_DROP_DATA = N).');
    end if;
end;
/
