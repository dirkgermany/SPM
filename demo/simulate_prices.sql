-- =============================================================================
-- SPM: Demo-Kursverläufe simulieren (Mock-Provider)
--
-- Aufruf (SQLcl), angemeldet als SPM:  @demo/simulate_prices.sql
--
-- Setzt die Demo-Daten zurück und erzeugt für sechs Aktien je 64 Kurse im 15-Minuten-Takt
-- (rückdatiert, rund 16 Stunden). Die Kurse laufen über den normalen Abrufweg
-- (spm_poll.run, Auslöser SIMULATION): Kurshistorie, LILAM-Prozesse, Messwerte und Alerts
-- entstehen wie im Betrieb. Ist der Zustell-Job eingeschaltet, gehen echte Mails hinaus
-- (Spam-Schutz: MAIL_MAX_PER_HOUR, MAIL_MIN_INTERVAL_SECONDS).
--
-- Muster: SAP steigt über die Obergrenze, Siemens fällt unter die Untergrenze, Apple hat
-- einen Ausreißer nach oben, Microsoft liefert einmal einen HTTP-Fehler (Lauf teilweise
-- erfolgreich), BMW und Allianz bleiben ruhig.
--
-- Achtung: löscht Kurse, Regeln und LILAM-Mittelwerte der Demo-Aktien sowie das frühere
-- Test-Instrument MAILTEST mit seinem Alert.
-- =============================================================================

set serveroutput on size unlimited
set define off
set feedback off
whenever sqlerror exit failure rollback

declare
    C_POINTS constant pls_integer := 64;

    type t_sym_tab is table of varchar2(20);
    l_symbols t_sym_tab := t_sym_tab('SAP', 'SIE', 'AAPL', 'BMW', 'ALV', 'MSFT');
    l_run     number;
    l_version number;
    l_status  varchar2(20);
    l_alerts  number;
    l_http    number;
    l_body    varchar2(400);

    function price(p_symbol varchar2, i pls_integer) return number is
        l_noise number := dbms_random.normal;
    begin
        return round(case p_symbol
            -- leichter Anstieg, ab Punkt 50 deutlich über die Obergrenze 185
            when 'SAP'  then 172 + i * 0.12 + greatest(i - 49, 0) * 0.6 + l_noise * 0.35
            -- seitwärts, Einbruch unter die Untergrenze 150 (Punkte 36 bis 44), dann Erholung
            when 'SIE'  then case when i between 36 and 44 then 168 - (i - 35) * 2.2
                                  when i between 45 and 56 then 148.2 + (i - 44) * 1.0
                                  else 168 end + l_noise * 0.4
            -- ruhig, Ausreißer nach oben bei Punkt 45
            when 'AAPL' then case when i = 45 then 241 else 228 end + l_noise * 0.5
            when 'BMW'  then 85 + sin(i / 6) * 0.8 + l_noise * 0.25
            when 'ALV'  then 279 + i * 0.05 + l_noise * 0.5
            when 'MSFT' then 415 + i * 0.12 + l_noise * 0.6
        end, 2);
    end price;
begin
    dbms_random.seed(4711);

    -- MAILTEST (Test-Instrument des ersten Mailversands) entfernen
    delete from spm_notification
    where  alert_id in (select alert_id from lilam_alerts where context_name = 'MAILTEST');
    delete from lilam_alerts where context_name = 'MAILTEST';
    delete from spm_rule  where instrument_id in (select instrument_id from spm_instrument where symbol = 'MAILTEST');
    delete from spm_price where instrument_id in (select instrument_id from spm_instrument where symbol = 'MAILTEST');
    delete from spm_mock_response where provider_symbol = 'MAILTEST';
    delete from spm_mock_state    where provider_symbol = 'MAILTEST';
    delete from spm_run where symbol_filter = 'MAILTEST';
    delete from spm_instrument where symbol = 'MAILTEST';

    -- Demo-Aktien zurücksetzen: Kurse, Mock-Antworten, LILAM-Mittelwerte der Kursreihen
    for s in 1 .. l_symbols.count loop
        delete from spm_price where instrument_id in (select instrument_id from spm_instrument where symbol = l_symbols(s));
        delete from spm_mock_response where provider_symbol = l_symbols(s);
        delete from spm_mock_state    where provider_symbol = l_symbols(s);
        delete from lilam_baselines   where action_name = 'SHARE_PRICE' and context_name = l_symbols(s);
    end loop;

    -- Watchlist
    spm_watchlist.save_instrument('SAP',  'MOCK', 'SAP',  'EUR', 'SAP SE',          'XETRA');
    spm_watchlist.save_instrument('SIE',  'MOCK', 'SIE',  'EUR', 'Siemens AG',      'XETRA');
    spm_watchlist.save_instrument('AAPL', 'MOCK', 'AAPL', 'USD', 'Apple Inc.',      'NASDAQ');
    spm_watchlist.save_instrument('BMW',  'MOCK', 'BMW',  'EUR', 'BMW AG',          'XETRA');
    spm_watchlist.save_instrument('ALV',  'MOCK', 'ALV',  'EUR', 'Allianz SE',      'XETRA');
    spm_watchlist.save_instrument('MSFT', 'MOCK', 'MSFT', 'USD', 'Microsoft Corp.', 'NASDAQ');

    -- Regeln (Dringlichkeit: Grenzwert = Alarm, Ausreißer und Schweigen = Warnung)
    spm_rules.save_rule('SAP',  p_val_min => 160, p_val_max => 185, p_ewma_pct_up => 3, p_ewma_pct_down => 3,
                        p_ewma_warmup => 5, p_ewma_alpha => 0.2, p_silence_seconds => 3600,
                        p_silence_windows => '[{"days":"MON-FRI","from":"09:00","to":"17:30"}]',
                        p_silence_time_zone => 'Europe/Berlin');
    spm_rules.save_rule('SIE',  p_val_min => 150, p_val_max => 185, p_silence_seconds => 3600,
                        p_silence_windows => '[{"days":"MON-FRI","from":"09:00","to":"17:30"}]',
                        p_silence_time_zone => 'Europe/Berlin');
    spm_rules.save_rule('AAPL', p_ewma_pct_up => 2.5, p_ewma_pct_down => 2.5, p_ewma_warmup => 5, p_ewma_alpha => 0.2,
                        p_silence_seconds => 3600,
                        p_silence_windows => '[{"days":"MON-FRI","from":"09:30","to":"16:00"}]',
                        p_silence_time_zone => 'America/New_York');
    spm_rules.save_rule('BMW',  p_val_min => 75, p_val_max => 95, p_ewma_pct_up => 3, p_ewma_pct_down => 3);
    spm_rules.save_rule('ALV',  p_val_max => 300, p_ewma_pct_up => 3, p_ewma_pct_down => 3);
    spm_rules.save_rule('MSFT', p_val_max => 450, p_ewma_pct_up => 3, p_ewma_pct_down => 3);

    -- Kursverläufe als Mock-Antworten, rückdatiert im 15-Minuten-Takt
    for s in 1 .. l_symbols.count loop
        for i in 1 .. C_POINTS loop
            if l_symbols(s) = 'MSFT' and i = 30 then
                l_http := 503;
                l_body := '{"error":"service unavailable"}';
            else
                l_http := 200;
                l_body := '{"symbol":"' || l_symbols(s) || '","price":'
                       || to_char(price(l_symbols(s), i), 'FM99999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''')
                       || ',"currency":"' || case when l_symbols(s) in ('AAPL', 'MSFT') then 'USD' else 'EUR' end
                       || '","timestamp":"{NOW-' || ((C_POINTS - i) * 15) || 'M}"}';
            end if;
            insert into spm_mock_response (provider_symbol, seq_no, http_status, body, note)
            values (l_symbols(s), i, l_http, l_body, 'Simulation');
        end loop;
    end loop;
    commit;

    l_version := spm_rules.publish('SPM_SIMULATION');
    dbms_output.put_line('Rule Set aktiv: Version ' || l_version);

    -- Abrufläufe über den normalen Weg
    for i in 1 .. C_POINTS loop
        l_run := spm_poll.run('SIMULATION');
        select status into l_status from spm_run where run_id = l_run;
        if l_status not in ('SUCCESS') then
            dbms_output.put_line('Lauf ' || i || ' (Run ' || l_run || '): ' || l_status);
        end if;
    end loop;

    -- Danach Zufallsbewegung um den letzten Kurs (keine vorbereiteten Antworten mehr)
    for s in 1 .. l_symbols.count loop
        delete from spm_mock_response where provider_symbol = l_symbols(s);
        delete from spm_mock_state    where provider_symbol = l_symbols(s);
    end loop;
    commit;

    select count(*) into l_alerts from lilam_alerts
    where  group_name = spm_cfg.get_text('LILAM_GROUP') and created_at > systimestamp - interval '10' minute;
    dbms_output.put_line(C_POINTS || ' Abrufläufe, ' || l_alerts || ' Alerts');
    for a in (select rule_id, context_name, initcap(alert_severity) sev, count(*) cnt from lilam_alerts
              where  group_name = spm_cfg.get_text('LILAM_GROUP') and created_at > systimestamp - interval '10' minute
              group  by rule_id, context_name, alert_severity order by rule_id) loop
        dbms_output.put_line('  ' || rpad(a.rule_id, 20) || ' ' || rpad(nvl(a.context_name, '-'), 10) || ' ' || a.sev || ' x' || a.cnt);
    end loop;
end;
/
