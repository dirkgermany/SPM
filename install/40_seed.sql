-- =============================================================================
-- SPM: Grunddaten (wiederholbar; vorhandene Werte werden nicht überschrieben)
-- =============================================================================

merge into spm_config c
using (
    select 'POLL_PROCESS_NAME'      n, 'SPM_POLL'         v, 'LILAM-Prozessname eines Abruflaufs' d from dual union all
    select 'LILAM_GROUP',              'STOCK_MONITORING',    'LILAM-Gruppe: aktives Rule Set für Abrufläufe' from dual union all
    select 'LILAM_BASELINE_SCOPE',     'SPM',                 'LILAM Baseline Scope: EWMA läuft über alle Abrufläufe weiter' from dual union all
    select 'LILAM_TABNAME_MASTER',     'LILAM',               'LILAM-Tabellenpräfix (_PROC, _LOG, _MON)' from dual union all
    select 'LILAM_LOG_LEVEL',          '4',                   'LILAM-Log-Level (4 = INFO; mindestens 3, sonst keine MARK_EVENT-Regeln)' from dual union all
    select 'LILAM_DAYS_TO_KEEP',       '30',                  'LILAM bereinigt Abrufläufe, die älter sind (Tage)' from dual union all
    select 'MAX_QUOTE_AGE_MINUTES',    '4320',                'Ältere Quotes werden als STALE verworfen (Wochenende: 3 Tage)' from dual union all
    select 'MAX_FUTURE_SKEW_SECONDS',  '300',                 'Zulässige Abweichung eines Quote-Zeitstempels in die Zukunft' from dual union all
    select 'MOCK_VOLATILITY',          '0.01',                'Mock ohne vorbereitete Antwort: Standardabweichung je Abruf (Zufallsbewegung)' from dual union all
    -- Scheduler-Job (SPM_JOB)
    select 'POLL_JOB_NAME',            'SPM_POLL_JOB',        'Name des DBMS_SCHEDULER-Jobs für den Kursabruf' from dual union all
    select 'POLL_INTERVAL_MINUTES',    '15',                  'Abrufintervall des Jobs in Minuten (1 bis 1440); Provider-Limits beachten' from dual union all
    -- Rule Set (SPM_RULES.PUBLISH)
    select 'RULE_SET_NAME',            'SPM_RULES',           'Name des LILAM Rule Sets (LILAM_RULES.SET_NAME, max. 30 Zeichen)' from dual union all
    select 'RULE_HANDLER',             'SPM_ALERT',           'DBMS_ALERT-Kanal der Alerts (max. 30 Zeichen)' from dual union all
    select 'RULE_TECH_THROTTLE_SECONDS', '3600',              'Drosselung der technischen Regeln (s)' from dual union all
    select 'RULE_RUN_MAX_MS',          '300000',              'Technische Regel: Abruflauf dauert länger (ms); leer = keine Regel' from dual union all
    select 'RULE_PROVIDER_CALL_MAX_MS', '10000',              'Technische Regel: Provider-Aufruf dauert länger (ms); leer = keine Regel' from dual union all
    select 'RULE_POLL_FAILED_MAX',     '0',                   'Technische Regel: mehr fehlerhafte Symbole je Lauf; leer = keine Regel' from dual union all
    select 'RULE_QUOTE_AGE_MAX_SEC',   null,                  'Technische Regel: Quote älter (s); leer = keine Regel (Wochenende/Feiertage beachten)' from dual
) s
on (c.param_name = s.n)
when not matched then insert (param_name, param_value, description) values (s.n, s.v, s.d);

merge into spm_provider p
using (
    select 'MOCK' code, 'Mock-Provider (lokal, ohne Netzwerk)' name,
           'Antworten aus SPM_MOCK_RESPONSE, sonst Zufallsbewegung. Keine echten Kurse.' note
    from dual
) s
on (p.provider_code = s.code)
when not matched then insert (provider_code, provider_name, is_active, note) values (s.code, s.name, 'Y', s.note);

commit;
