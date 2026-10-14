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
    -- REST-Provider (SPM_PROV.HTTP_GET)
    select 'HTTPS_WALLET',             'system:',             'Wallet für HTTPS (UTL_HTTP.SET_WALLET); system: = Zertifikate des Betriebssystems' from dual union all
    select 'HTTP_TIMEOUT_SECONDS',     '10',                  'Zeitlimit eines Provider-Aufrufs (s)' from dual union all
    select 'HTTP_MAX_BODY_CHARS',      '32000',               'Längere Provider-Antworten werden abgeschnitten (Zeichen)' from dual union all
    -- Scheduler-Job (SPM_JOB)
    select 'POLL_JOB_NAME',            'SPM_POLL_JOB',        'Name des DBMS_SCHEDULER-Jobs für den Kursabruf' from dual union all
    select 'POLL_INTERVAL_MINUTES',    '15',                  'Abrufintervall des Jobs in Minuten (1 bis 1440); Provider-Limits beachten' from dual union all
    -- Watchdog (SPM_WATCHDOG, eigener Job)
    select 'WATCHDOG_JOB_NAME',        'SPM_WATCHDOG_JOB',    'Name des DBMS_SCHEDULER-Jobs des Watchdogs' from dual union all
    select 'WATCHDOG_INTERVAL_MINUTES', '5',                  'Prüfintervall des Watchdogs in Minuten; deutlich unter der kleinsten Schweigezeit' from dual union all
    select 'WATCHDOG_PROCESS_NAME',    'SPM_WATCHDOG',        'LILAM-Prozessname eines Watchdog-Laufs' from dual union all
    select 'WATCHDOG_DAYS_TO_KEEP',    '7',                   'LILAM bereinigt Watchdog-Läufe, die älter sind (Tage)' from dual union all
    select 'RULE_POLL_SILENCE_SEC',    '2700',                'Schweige-Regel: kein Abruflauf gestartet seit (s); leer = keine Regel' from dual union all
    select 'RULE_RUN_HANG_SEC',        '600',                 'Schweige-Regel: laufender Abruflauf sendet nichts seit (s); leer = keine Regel' from dual union all
    select 'RULE_WATCHDOG_SILENCE_SEC', '1800',               'Schweige-Regel: kein Watchdog-Lauf seit (s); leer = keine Regel' from dual union all
    -- Zustellung von Alerts per E-Mail (SPM_NOTIFY, eigener Job)
    select 'MAIL_TRANSPORT',           'SMTP',                'SMTP = per UTL_SMTP versenden, MOCK = nur protokollieren (Tests)' from dual union all
    select 'MAIL_SMTP_HOST',           'localhost',           'SMTP-Server (Relay, z. B. lokales Postfix); Netzwerk-ACL nötig' from dual union all
    select 'MAIL_SMTP_PORT',           '25',                  'Port des SMTP-Servers' from dual union all
    select 'MAIL_HELO_DOMAIN',         'localhost',           'Domain für SMTP HELO' from dual union all
    select 'MAIL_FROM',                null,                  'Absenderadresse; leer = es wird nicht versendet' from dual union all
    select 'MAIL_TO',                  null,                  'Empfänger, mehrere durch Komma getrennt; leer = es wird nicht versendet' from dual union all
    select 'MAIL_SUBJECT_PREFIX',      '[SPM]',               'Präfix des Betreffs' from dual union all
    select 'MAIL_MAX_PER_HOUR',        '12',                  'Spam-Schutz: höchstens so viele Mails je Stunde; der Rest bleibt offen' from dual union all
    select 'MAIL_MIN_INTERVAL_SECONDS', '10',                 'Spam-Schutz: Mindestabstand zwischen zwei Mails (s)' from dual union all
    select 'NOTIFY_JOB_NAME',          'SPM_NOTIFY_JOB',      'Name des DBMS_SCHEDULER-Jobs der Zustellung' from dual union all
    select 'NOTIFY_PROCESS_NAME',      'SPM_NOTIFY',          'LILAM-Prozessname eines Zustell-Laufs' from dual union all
    select 'NOTIFY_RUN_MINUTES',       '60',                  'Ein Zustell-Lauf wartet so lange auf Alerts, dann startet der Job neu' from dual union all
    select 'NOTIFY_DAYS_TO_KEEP',      '30',                  'LILAM bereinigt Zustell-Läufe, die älter sind (Tage)' from dual union all
    select 'RULE_NOTIFY_SILENCE_SEC',  '10800',               'Schweige-Regel: kein Zustell-Lauf gestartet seit (s); leer = keine Regel' from dual union all
    -- APEX-Anwendung
    select 'APEX_ADMIN_USERS',         null,                  'APEX-Benutzer mit Zugriff auf die Administration (Komma-Liste); leer = alle angemeldeten' from dual union all
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
    select 'MOCK' code, 'Mock-Provider (lokal, ohne Netzwerk)' name, null base_url, null cred,
           'Antworten aus SPM_MOCK_RESPONSE, sonst Zufallsbewegung. Keine echten Kurse.' note
    from dual union all
    select 'TWELVEDATA', 'Twelve Data', 'https://api.twelvedata.com', 'TWELVEDATA_API_KEY',
           'REST /quote; Gratistarif 800 Credits/Tag, 8/min; Kurse je nach Börse verzögert. Provider-Symbol: Ticker oder Ticker:MIC (SAP:XETR).'
    from dual
) s
on (p.provider_code = s.code)
when not matched then insert (provider_code, provider_name, base_url, credential_name, is_active, note)
                      values (s.code, s.name, s.base_url, s.cred, 'Y', s.note);

commit;
