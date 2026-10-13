create or replace package body spm_test as

    g_pass pls_integer := 0;
    g_fail pls_integer := 0;
    g_case varchar2(100);

    type t_text_tab is table of varchar2(30);

    C_SYMBOLS constant t_text_tab := t_text_tab(
        'TSTOK', 'TSTSTR', 'TSTDUP', 'TSTH500', 'TSTTMO', 'TSTJSN', 'TSTNOP', 'TSTNAN', 'TSTSYM',
        'TSTCCY', 'TSTOLD', 'TSTFUT', 'TSTNEG', 'TSTKEY', 'TSTM1', 'TSTM2', 'TSTM3', 'TSTQ1', 'TSTQ2',
        'TSTSYS', 'TSTB', 'TSTR', 'TSTE', 'TSTT');

    -- Tests laufen in eigenen LILAM-Gruppen: echte Regeln greifen nicht, Testregeln und
    -- Sperren (LILAM_ALERT_LOCKS) sind je Testlauf frisch. Die Regeltests brauchen eine
    -- zweite Gruppe, da die Session die Regeln einer schon benutzten Gruppe zwischenspeichert.
    g_group_orig  varchar2(400);
    g_group_base  varchar2(50);
    g_group_rules varchar2(50);

    -- Job-Test: eigener Job-Name, die Sicht SPM_JOB_STATUS_V zeigt ihn während des Tests
    C_TEST_JOB constant varchar2(30) := 'SPM_TEST_POLL_JOB';
    g_job_orig     varchar2(400);

    ------------------------------------------------------------------------
    -- Prüfungen
    ------------------------------------------------------------------------
    procedure ok(p_cond boolean, p_text varchar2) is
    begin
        if nvl(p_cond, false) then
            g_pass := g_pass + 1;
        else
            g_fail := g_fail + 1;
            dbms_output.put_line('  FEHLER [' || g_case || '] ' || p_text);
        end if;
    end ok;

    procedure eq(p_expected varchar2, p_actual varchar2, p_text varchar2) is
    begin
        ok(p_expected = p_actual or (p_expected is null and p_actual is null),
           p_text || ': erwartet <' || p_expected || '>, ist <' || p_actual || '>');
    end eq;

    procedure eq(p_expected number, p_actual number, p_text varchar2) is
    begin
        ok(p_expected = p_actual or (p_expected is null and p_actual is null),
           p_text || ': erwartet <' || p_expected || '>, ist <' || p_actual || '>');
    end eq;

    procedure start_case(p_name varchar2) is
    begin
        g_case := p_name;
        dbms_output.put_line('- ' || p_name);
    end start_case;

    ------------------------------------------------------------------------
    -- Zugriffe auf SPM und LILAM
    ------------------------------------------------------------------------
    function tab(p_suffix varchar2) return varchar2 is
    begin
        return dbms_assert.simple_sql_name(spm_cfg.get_text('LILAM_TABNAME_MASTER', 'LILAM') || p_suffix);
    end tab;

    function run_test(p_symbol_like varchar2) return spm_run%rowtype is
        l_run    spm_run%rowtype;
        l_run_id number;
    begin
        l_run_id := spm_poll.run('TEST', p_symbol_like); -- nicht in SQL: der Lauf committet
        select * into l_run from spm_run where run_id = l_run_id;
        return l_run;
    end run_test;

    function last_test_run(p_symbol_like varchar2) return spm_run%rowtype is
        l_run spm_run%rowtype;
    begin
        select * into l_run from spm_run
        where  trigger_type = 'TEST' and symbol_filter = p_symbol_like
        order  by run_id desc fetch first 1 row only;
        return l_run;
    end last_test_run;

    function fetch_status(p_symbol varchar2) return varchar2 is
        l_status spm_instrument.last_fetch_status%type;
    begin
        select last_fetch_status into l_status from spm_instrument where symbol = p_symbol;
        return l_status;
    end fetch_status;

    function fetch_message(p_symbol varchar2) return varchar2 is
        l_msg spm_instrument.last_fetch_message%type;
    begin
        select last_fetch_message into l_msg from spm_instrument where symbol = p_symbol;
        return l_msg;
    end fetch_message;

    function price_count(p_symbol varchar2) return number is
        l_count number;
    begin
        select count(*) into l_count
        from   spm_price p join spm_instrument i on i.instrument_id = p.instrument_id
        where  i.symbol = p_symbol;
        return l_count;
    end price_count;

    function last_price(p_symbol varchar2) return number is
        l_price number;
    begin
        select max(p.price) keep (dense_rank last order by p.price_id) into l_price
        from   spm_price p join spm_instrument i on i.instrument_id = p.instrument_id
        where  i.symbol = p_symbol;
        return l_price;
    end last_price;

    function proc_status(p_pid number) return number is
        l_status number;
    begin
        execute immediate 'select max(status) from ' || tab('_PROC') || ' where id = :1' into l_status using p_pid;
        return l_status;
    end proc_status;

    function proc_closed(p_pid number) return boolean is
        l_count number;
    begin
        execute immediate 'select count(*) from ' || tab('_PROC') || ' where id = :1 and process_end is not null'
            into l_count using p_pid;
        return l_count = 1;
    end proc_closed;

    function mon_value(p_pid number, p_action varchar2, p_context varchar2) return number is
        l_value number;
    begin
        execute immediate 'select max(used_value) from ' || tab('_MON')
                       || ' where process_id = :1 and action = :2 and context = :3'
            into l_value using p_pid, p_action, p_context;
        return l_value;
    end mon_value;

    function mon_count(p_pid number, p_action varchar2, p_context varchar2) return number is
        l_count number;
    begin
        execute immediate 'select count(*) from ' || tab('_MON')
                       || ' where process_id = :1 and action = :2 and context = :3'
            into l_count using p_pid, p_action, p_context;
        return l_count;
    end mon_count;

    function log_count(p_pid number, p_text varchar2) return number is
        l_count number;
    begin
        execute immediate 'select count(*) from ' || tab('_LOG')
                       || ' where process_id = :1 and instr(info, :2) > 0'
            into l_count using p_pid, p_text;
        return l_count;
    end log_count;

    procedure baseline(p_context varchar2, o_count out number, o_avg out number) is
    begin
        execute immediate
            'select nvl(max(b.val_count), 0), max(b.avg_val)
             from   lilam_baselines b join lilam_scopes s on s.scope_id = b.scope_id
             where  upper(s.scope_name) = upper(:1) and b.action_name = :2 and b.context_name = :3'
            into o_count, o_avg
            using spm_cfg.get_text('LILAM_BASELINE_SCOPE'), spm_poll.C_ACT_SHARE_PRICE, p_context;
    exception
        when others then
            -- LILAM legt die Baseline-Tabellen erst bei Bedarf an
            o_count := 0;
            o_avg   := null;
    end baseline;

    ------------------------------------------------------------------------
    -- Vorbereitung
    ------------------------------------------------------------------------
    procedure set_group(p_group varchar2) is
    begin
        update spm_config set param_value = p_group where param_name = 'LILAM_GROUP';
        commit;
    end set_group;

    procedure setup is
        l_stamp varchar2(20) := to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
    begin
        g_group_orig  := spm_cfg.get_text('LILAM_GROUP');
        g_group_base  := 'SPMTEST_' || l_stamp || '_A';
        g_group_rules := 'SPMTEST_' || l_stamp || '_R';
        set_group(g_group_base);

        for i in 1 .. C_SYMBOLS.count loop
            spm_watchlist.save_instrument(p_symbol => C_SYMBOLS(i), p_provider_code => 'MOCK',
                                          p_provider_symbol => C_SYMBOLS(i), p_currency => 'EUR',
                                          p_name => 'Test ' || C_SYMBOLS(i), p_is_active => 'Y');
        end loop;

        delete from spm_price
        where  instrument_id in (select instrument_id from spm_instrument where symbol like 'TST%')
        or     run_id in (select run_id from spm_run where trigger_type = 'TEST' or symbol_filter like 'TST%');
        delete from spm_run where trigger_type = 'TEST' or symbol_filter like 'TST%';
        update spm_instrument
        set    last_fetch_at = null, last_fetch_status = null, last_fetch_message = null
        where  symbol like 'TST%';
        delete from spm_rule where instrument_id in (select instrument_id from spm_instrument where symbol like 'TST%');
        spm_prov_mock.reset_state;
        commit;
    end setup;

    procedure teardown is
    begin
        set_group(g_group_orig);
        spm_job.drop_job(C_TEST_JOB);
        if g_job_orig is not null then
            update spm_config set param_value = g_job_orig where param_name = 'POLL_JOB_NAME';
        end if;
        delete from spm_rule where instrument_id in (select instrument_id from spm_instrument where symbol like 'TST%');
        update spm_instrument set is_active = 'N' where symbol like 'TST%';
        -- Rule Sets und Sperren der Testgruppen; Alerts und Prozesse bleiben zur Analyse
        delete from lilam_rules where upper(group_name) like 'SPMTEST\_%' escape '\';
        delete from lilam_alert_locks where lock_key like 'SPMTEST\_%' escape '\';
        commit;
    end teardown;

    function alert_count(p_pid number, p_rule_id varchar2) return number is
        l_count number;
    begin
        select count(*) into l_count from lilam_alerts where process_id = p_pid and rule_id = p_rule_id;
        return l_count;
    end alert_count;

    -- Abruflauf in eigener Session über DBMS_SCHEDULER (wie der spätere Scheduler-Job)
    function run_in_job(p_symbol_like varchar2) return spm_run%rowtype is
        l_before number;
        l_run    spm_run%rowtype;
    begin
        select nvl(max(run_id), 0) into l_before from spm_run;
        dbms_scheduler.create_job(
            job_name   => 'SPM_TEST_JOB_' || to_char(systimestamp, 'HH24MISSFF3'),
            job_type   => 'PLSQL_BLOCK',
            job_action => 'begin spm_poll.run(''TEST'', ''' || replace(p_symbol_like, '''', '''''') || '''); end;',
            enabled    => true,
            auto_drop  => true);
        for i in 1 .. 60 loop
            begin
                select * into l_run from spm_run
                where  run_id > l_before and trigger_type = 'TEST' and symbol_filter = p_symbol_like
                and    status <> 'RUNNING'
                fetch  first 1 row only;
                return l_run;
            exception
                when no_data_found then
                    dbms_session.sleep(1);
            end;
        end loop;
        raise_application_error(-20901, 'Scheduler-Testlauf nicht innerhalb von 60 s beendet');
    end run_in_job;

    function rule_value(p_set clob, p_rule_id varchar2) return varchar2 is
        l_value varchar2(100);
    begin
        select json_value(p_set, '$.rules[*]?(@.id == $id).condition.value' passing p_rule_id as "id")
        into   l_value from dual;
        return l_value;
    end rule_value;

    function has_rule(p_set clob, p_rule_id varchar2) return boolean is
        l_count number;
    begin
        select count(*) into l_count from dual
        where  json_exists(p_set, '$.rules[*]?(@.id == $id)' passing p_rule_id as "id");
        return l_count = 1;
    end has_rule;

    ------------------------------------------------------------------------
    -- Testfälle
    ------------------------------------------------------------------------
    procedure t_success is
        r spm_run%rowtype;
    begin
        start_case('Erfolg: Kurs gespeichert, LILAM-Prozess geschlossen, Messwert in _MON');
        r := run_test('TSTOK');
        eq('SUCCESS', r.status, 'Laufstatus');
        eq(1, r.cnt_requested, 'angefragt');
        eq(1, r.cnt_stored, 'gespeichert');
        eq(1, price_count('TSTOK'), 'Kurse in SPM_PRICE');
        eq(101.5, last_price('TSTOK'), 'Kurs');
        eq('OK', fetch_status('TSTOK'), 'Abrufstatus');
        ok(r.lilam_process_id > 0, 'LILAM-Prozess-ID vorhanden');
        eq(spm_poll.C_STATUS_SUCCESS, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');
        eq(101.5, mon_value(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTOK'), 'SHARE_PRICE-Wert in _MON');
        eq(1, mon_count(r.lilam_process_id, spm_poll.C_ACT_QUOTE_AGE, 'TSTOK'), 'QUOTE_AGE_SEC gemeldet');
        ok(mon_count(r.lilam_process_id, spm_poll.C_ACT_PROVIDER_CALL, 'TSTOK') > 0, 'Trace PROVIDER_CALL');
        eq(1, mon_value(r.lilam_process_id, spm_poll.C_ACT_POLL_RESULT, 'STORED'), 'POLL_RESULT STORED');
        eq(0, mon_value(r.lilam_process_id, spm_poll.C_ACT_POLL_RESULT, 'FAILED'), 'POLL_RESULT FAILED');

        start_case('Erfolg: Kurs als JSON-Text');
        r := run_test('TSTSTR');
        eq('SUCCESS', r.status, 'Laufstatus');
        eq(123.45, last_price('TSTSTR'), 'Kurs');
    end t_success;

    procedure t_duplicate is
        r1 spm_run%rowtype;
        r2 spm_run%rowtype;
    begin
        start_case('Idempotenz: derselbe Quote zweimal');
        r1 := run_test('TSTDUP');
        r2 := run_test('TSTDUP');
        eq(1, r1.cnt_stored, 'Lauf 1 gespeichert');
        eq(0, r2.cnt_stored, 'Lauf 2 gespeichert');
        eq(1, r2.cnt_duplicate, 'Lauf 2 doppelt');
        eq('SUCCESS', r2.status, 'Lauf 2 Status');
        eq(1, price_count('TSTDUP'), 'Kurse in SPM_PRICE');
        eq('DUPLICATE', fetch_status('TSTDUP'), 'Abrufstatus');
        eq(0, mon_count(r2.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTDUP'), 'kein SHARE_PRICE für Duplikat');
    end t_duplicate;

    procedure t_failures is
        type t_case is record (symbol varchar2(30), outcome varchar2(20));
        type t_case_tab is table of t_case;
        l_cases t_case_tab := t_case_tab(
            t_case('TSTH500', 'HTTP_ERROR'), t_case('TSTTMO', 'TIMEOUT'),     t_case('TSTJSN', 'PARSE_ERROR'),
            t_case('TSTNOP',  'PARSE_ERROR'), t_case('TSTNAN', 'PARSE_ERROR'), t_case('TSTSYM', 'PARSE_ERROR'),
            t_case('TSTCCY',  'INVALID'),     t_case('TSTOLD', 'STALE'),       t_case('TSTFUT', 'INVALID'),
            t_case('TSTNEG',  'INVALID'),     t_case('TSTKEY', 'HTTP_ERROR'));
        r spm_run%rowtype;
    begin
        for i in 1 .. l_cases.count loop
            start_case('Fehlerfall ' || l_cases(i).symbol || ' -> ' || l_cases(i).outcome);
            r := run_test(l_cases(i).symbol);
            eq('FAILED', r.status, 'Laufstatus');
            eq(1, r.cnt_failed, 'fehlerhaft');
            eq(0, r.cnt_stored, 'gespeichert');
            eq(0, price_count(l_cases(i).symbol), 'Kurse in SPM_PRICE');
            eq(l_cases(i).outcome, fetch_status(l_cases(i).symbol), 'Abrufstatus');
            eq(spm_poll.C_STATUS_FAILED, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
            ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');
            ok(log_count(r.lilam_process_id, l_cases(i).symbol || ': ' || l_cases(i).outcome) > 0, 'WARN im LILAM-Log');
            eq(0, mon_count(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, l_cases(i).symbol), 'kein SHARE_PRICE');
        end loop;

        start_case('Zu alter Quote: Alter wird trotzdem gemeldet');
        r := last_test_run('TSTOLD');
        eq(1, mon_count(r.lilam_process_id, spm_poll.C_ACT_QUOTE_AGE, 'TSTOLD'), 'QUOTE_AGE_SEC gemeldet');

        start_case('Geheimnis aus Fehlerantwort wird nicht protokolliert');
        r := last_test_run('TSTKEY');
        ok(instr(fetch_message('TSTKEY'), 'SECRET123') = 0, 'Schlüssel nicht in LAST_FETCH_MESSAGE');
        ok(instr(fetch_message('TSTKEY'), 'apikey=***') > 0, 'Schlüssel maskiert');
        eq(0, log_count(r.lilam_process_id, 'SECRET123'), 'Schlüssel nicht im LILAM-Log');
    end t_failures;

    procedure t_mixed is
        r       spm_run%rowtype;
        l_count number;
        l_avg   number;
    begin
        start_case('Gemischt: ein Symbol scheitert, die anderen werden verarbeitet');
        r := run_test('TSTM%');
        eq('PARTIAL', r.status, 'Laufstatus');
        eq(3, r.cnt_requested, 'angefragt');
        eq(2, r.cnt_fetched, 'erhalten');
        eq(1, r.cnt_failed, 'fehlerhaft');
        eq(2, r.cnt_stored, 'gespeichert');
        eq(spm_poll.C_STATUS_PARTIAL, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        eq(11, mon_value(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTM1'), 'Wert TSTM1');
        eq(33, mon_value(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTM3'), 'Wert TSTM3');
        eq(0, mon_count(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTM2'), 'kein Wert TSTM2');
        eq(1, mon_value(r.lilam_process_id, spm_poll.C_ACT_POLL_RESULT, 'FAILED'), 'POLL_RESULT FAILED');

        start_case('Reihen je Symbol getrennt (Baseline)');
        baseline('TSTM1', l_count, l_avg);
        eq(11, l_avg, 'Baseline TSTM1');
        baseline('TSTM3', l_count, l_avg);
        eq(33, l_avg, 'Baseline TSTM3');
    end t_mixed;

    procedure t_quota is
        r spm_run%rowtype;
    begin
        start_case('Quotenlimit: Lauf endet, restliche Symbole werden nicht angefragt');
        r := run_test('TSTQ%');
        eq('FAILED', r.status, 'Laufstatus');
        eq(1, r.cnt_requested, 'angefragt');
        eq('QUOTA', fetch_status('TSTQ1'), 'Abrufstatus TSTQ1');
        eq(null, fetch_status('TSTQ2'), 'TSTQ2 nicht angefragt');
        ok(instr(r.message, 'QUOTA') > 0, 'Grund in SPM_RUN.MESSAGE');
        eq(spm_poll.C_STATUS_FAILED, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');
    end t_quota;

    procedure t_systemic is
        r      spm_run%rowtype;
        l_code number;
    begin
        start_case('Systemischer Fehler: Prozess geschlossen, Ausnahme erneut ausgelöst');
        begin
            spm_poll.run('TEST', 'TSTSYS');
            l_code := 0;
        exception
            when others then
                l_code := sqlcode;
        end;
        eq(spm_poll.C_ERR_SYSTEMIC, l_code, 'Ausnahme an den Aufrufer');
        r := last_test_run('TSTSYS');
        eq('FAILED', r.status, 'Laufstatus');
        ok(r.ended_at is not null, 'Lauf beendet');
        eq(spm_poll.C_STATUS_FAILED, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');
        ok(log_count(r.lilam_process_id, 'abgebrochen') > 0, 'ERROR im LILAM-Log');

        start_case('Nach Abbruch ist die Sperre frei; leere Auswahl ist Erfolg');
        r := run_test('NOSUCH%');
        eq('SUCCESS', r.status, 'Laufstatus');
        eq(0, r.cnt_requested, 'angefragt');
    end t_systemic;

    procedure t_lock is
        r        spm_run%rowtype;
        l_handle varchar2(128);
        l_rc     integer;
    begin
        start_case('Überlappung: zweiter Lauf wird übersprungen');
        dbms_lock.allocate_unique_autonomous('SPM_POLL_RUN', l_handle);
        l_rc := dbms_lock.request(l_handle, dbms_lock.x_mode, timeout => 0, release_on_commit => false);
        eq(0, l_rc, 'Sperre im Test belegt');
        r := run_test('TSTOK');
        l_rc := dbms_lock.release(l_handle);
        eq('SKIPPED', r.status, 'Laufstatus');
        ok(r.lilam_process_id is null, 'kein LILAM-Prozess');
    end t_lock;

    procedure t_baseline is
        r        spm_run%rowtype;
        l_before number;
        l_after  number;
        l_avg    number;
    begin
        start_case('Baseline: Wert-EWMA läuft über mehrere Abrufläufe weiter');
        baseline('TSTB', l_before, l_avg);
        for i in 1 .. 3 loop
            r := run_test('TSTB');
            eq(1, r.cnt_stored, 'Lauf ' || i || ' gespeichert');
        end loop;
        baseline('TSTB', l_after, l_avg);
        eq(l_before + 3, l_after, 'Anzahl Werte in LILAM_BASELINES');
        if l_before = 0 then
            eq(101, l_avg, 'EWMA im Warm-up = Mittelwert');
        else
            ok(l_avg between 100 and 102, 'EWMA im Wertebereich: ' || l_avg);
        end if;
    end t_baseline;

    procedure t_rules is
        r      spm_run%rowtype;
        l_set  clob;
        l_code number;
        l_v1   number;
        l_v2   number;
        l_v3   number;
        l_act  number;
        type t_num_tab is table of number index by pls_integer;
        l_up   t_num_tab;
        l_down t_num_tab;
    begin
        start_case('Regeln: Eingaben werden geprüft');
        begin spm_rules.save_rule('TSTR', p_val_min => 10, p_val_max => 5); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'Untergrenze >= Obergrenze');
        begin spm_rules.save_rule('TSTE', p_ewma_pct_up => -1); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'negative Prozentabweichung');
        begin spm_rules.save_rule('TSTE', p_ewma_pct_up => 5, p_ewma_alpha => 2); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'Alpha > 1');
        begin spm_rules.save_rule('TSTE', p_ewma_pct_up => 5, p_ewma_warmup => 0.5); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'Warm-up keine ganze Zahl');
        begin spm_rules.save_rule('TSTE', p_ewma_warmup => 3); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'Warm-up ohne EWMA-Abweichung');
        begin spm_rules.save_rule('TSTR', p_val_max => 1, p_severity_limit => 'LAUT'); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'unbekannte Severity');
        begin spm_rules.save_rule('NOSUCH', p_val_max => 1); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_rules.C_ERR_RULE, l_code, 'Symbol nicht in der Watchlist');

        start_case('Regeln: Rule Set erzeugen');
        set_group(g_group_rules);
        spm_rules.save_rule('TSTR', p_val_min => 10, p_val_max => 100, p_throttle_seconds => 0);
        spm_rules.save_rule('TSTE', p_ewma_pct_up => 5, p_ewma_pct_down => 5, p_ewma_warmup => 3,
                            p_ewma_alpha => 0.1, p_throttle_seconds => 0);
        spm_rules.save_rule('TSTT', p_val_max => 100, p_throttle_seconds => 3600);
        -- Regel eines inaktiven Instruments darf nicht im Rule Set stehen
        spm_rules.save_rule('TSTOK', p_val_max => 1);
        spm_watchlist.set_active('TSTOK', 'N');
        commit;
        l_set := spm_rules.build_rule_set;
        ok(lilam.check_rule_set(l_set) is null, 'LILAM.CHECK_RULE_SET: ' || lilam.check_rule_set(l_set));
        eq('100', rule_value(l_set, 'TSTR-MAX'), 'TSTR-MAX');
        eq('10', rule_value(l_set, 'TSTR-MIN'), 'TSTR-MIN');
        eq('5|3|0.1', rule_value(l_set, 'TSTE-UP'), 'TSTE-UP');
        eq('5|3|0.1', rule_value(l_set, 'TSTE-DOWN'), 'TSTE-DOWN');
        ok(not has_rule(l_set, 'TSTE-MIN'), 'keine Regel ohne Wert');
        ok(not has_rule(l_set, 'TSTOK-MAX'), 'keine Regel für inaktives Instrument');
        eq('-1', rule_value(l_set, 'SPM-RUN-FAILED'), 'technische Regel SPM-RUN-FAILED');
        eq('0', rule_value(l_set, 'SPM-POLL-FAILED'), 'technische Regel SPM-POLL-FAILED');
        spm_watchlist.set_active('TSTOK', 'Y');
        spm_rules.delete_rule('TSTOK');
        commit;

        start_case('Regeln: veröffentlichen und versionieren');
        l_v1 := spm_rules.publish('SPM_TEST');
        l_v2 := spm_rules.publish('SPM_TEST');
        eq(l_v1, l_v2, 'unverändert: keine neue Version');
        spm_rules.save_rule('TSTR', p_val_min => 10, p_val_max => 101, p_throttle_seconds => 0);
        commit;
        l_v3 := spm_rules.publish('SPM_TEST');
        eq(l_v1 + 1, l_v3, 'geändert: neue Version');
        spm_rules.save_rule('TSTR', p_val_min => 10, p_val_max => 100, p_throttle_seconds => 0);
        commit;
        l_v3 := spm_rules.publish('SPM_TEST');
        eq(l_v1 + 2, l_v3, 'zurückgeändert: neue Version');
        select max(version) into l_act from lilam_rules where group_name = g_group_rules and is_active = 1;
        eq(l_v3, l_act, 'aktive Version in LILAM_RULES');

        start_case('Regeln: VAL_MAX und VAL_MIN lösen aus');
        r := run_test('TSTR');                         -- 150
        eq(1, alert_count(r.lilam_process_id, 'TSTR-MAX'), 'Lauf 1 TSTR-MAX');
        eq(0, alert_count(r.lilam_process_id, 'TSTR-MIN'), 'Lauf 1 TSTR-MIN');
        select count(*) into l_act from lilam_alerts
        where  process_id = r.lilam_process_id and rule_id = 'TSTR-MAX'
        and    context_name = 'TSTR' and group_name = g_group_rules;
        eq(1, l_act, 'Alert mit Context und Gruppe');
        r := run_test('TSTR');                         -- 5
        eq(1, alert_count(r.lilam_process_id, 'TSTR-MIN'), 'Lauf 2 TSTR-MIN');
        eq(0, alert_count(r.lilam_process_id, 'TSTR-MAX'), 'Lauf 2 TSTR-MAX');
        r := run_test('TSTR');                         -- 50
        eq(0, alert_count(r.lilam_process_id, 'TSTR-MIN') + alert_count(r.lilam_process_id, 'TSTR-MAX'),
           'Lauf 3 im Band');

        start_case('Regeln: EWMA-Ausreißer nach oben und unten');
        for i in 1 .. 5 loop                           -- 100, 100, 100, 120, 80
            r := run_test('TSTE');
            l_up(i)   := alert_count(r.lilam_process_id, 'TSTE-UP');
            l_down(i) := alert_count(r.lilam_process_id, 'TSTE-DOWN');
        end loop;
        eq(0, l_up(1) + l_up(2) + l_up(3) + l_down(1) + l_down(2) + l_down(3), 'Läufe 1-3 ohne Alert');
        eq(1, l_up(4), 'Lauf 4 TSTE-UP');
        eq(0, l_down(4), 'Lauf 4 TSTE-DOWN');
        eq(1, l_down(5), 'Lauf 5 TSTE-DOWN');
        eq(0, l_up(5), 'Lauf 5 TSTE-UP');

        start_case('Regeln: Drosselung gilt für einen Scheduler-Lauf in anderer Session');
        r := run_test('TSTT');                         -- 150
        eq(1, alert_count(r.lilam_process_id, 'TSTT-MAX'), 'Lauf 1 TSTT-MAX');
        r := run_in_job('TSTT');                       -- 160
        eq('SUCCESS', r.status, 'Scheduler-Lauf Status');
        eq(1, r.cnt_stored, 'Scheduler-Lauf gespeichert');
        eq(160, mon_value(r.lilam_process_id, spm_poll.C_ACT_SHARE_PRICE, 'TSTT'), 'Wert im Scheduler-Lauf');
        eq(0, alert_count(r.lilam_process_id, 'TSTT-MAX'), 'Scheduler-Lauf gedrosselt');

        start_case('Regeln: technische Regeln');
        r := run_test('TSTH500');
        eq(1, alert_count(r.lilam_process_id, 'SPM-RUN-FAILED'), 'SPM-RUN-FAILED');
        eq(1, alert_count(r.lilam_process_id, 'SPM-POLL-FAILED'), 'SPM-POLL-FAILED');
        r := run_test('TSTM%');
        eq(1, alert_count(r.lilam_process_id, 'SPM-RUN-PARTIAL'), 'SPM-RUN-PARTIAL');
        eq(0, alert_count(r.lilam_process_id, 'SPM-RUN-FAILED'), 'kein SPM-RUN-FAILED bei Teilerfolg');
    end t_rules;

    -- Job sofort starten und auf den Eintrag in der Job-Historie warten
    procedure run_job_and_wait(o_status out varchar2, o_error out number) is
        l_before number;
    begin
        select nvl(max(log_id), 0) into l_before from user_scheduler_job_run_details;
        spm_job.run_now(C_TEST_JOB);
        for i in 1 .. 60 loop
            begin
                select status, error# into o_status, o_error
                from   user_scheduler_job_run_details
                where  job_name = C_TEST_JOB and log_id > l_before
                order  by log_id desc fetch first 1 row only;
                return;
            exception
                when no_data_found then
                    dbms_session.sleep(1);
            end;
        end loop;
        raise_application_error(-20902, 'Job ' || C_TEST_JOB || ' nicht innerhalb von 60 s beendet');
    end run_job_and_wait;

    function last_run_of(p_trigger varchar2, p_symbol_like varchar2) return spm_run%rowtype is
        l_run spm_run%rowtype;
    begin
        select * into l_run from spm_run
        where  trigger_type = p_trigger and symbol_filter = p_symbol_like
        order  by run_id desc fetch first 1 row only;
        return l_run;
    end last_run_of;

    procedure t_job is
        l_code    number;
        l_status  varchar2(30);
        l_error   number;
        l_enabled varchar2(5);
        l_repeat  varchar2(4000);
        l_count   number;
        r         spm_run%rowtype;
        v         spm_job_status_v%rowtype;
    begin
        start_case('Job: Eingaben werden geprüft');
        begin spm_job.create_job(p_interval_minutes => 0, p_job_name => C_TEST_JOB); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_job.C_ERR_JOB, l_code, 'Intervall 0');
        begin spm_job.create_job(p_interval_minutes => 1.5, p_job_name => C_TEST_JOB); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_job.C_ERR_JOB, l_code, 'Intervall keine ganze Zahl');
        begin spm_job.create_job(p_job_name => 'X;DROP'); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_job.C_ERR_JOB, l_code, 'ungültiger Job-Name');
        begin spm_job.enable_job(C_TEST_JOB); l_code := 0;
        exception when others then l_code := sqlcode; end;
        eq(spm_job.C_ERR_JOB, l_code, 'Einschalten eines fehlenden Jobs');

        start_case('Job: anlegen und ändern, ohne einzuschalten');
        spm_job.create_job(p_interval_minutes => 1440, p_job_name => C_TEST_JOB, p_symbol_like => 'TSTOK');
        select enabled, repeat_interval into l_enabled, l_repeat from user_scheduler_jobs where job_name = C_TEST_JOB;
        eq('FALSE', l_enabled, 'nicht eingeschaltet');
        eq('FREQ=MINUTELY;INTERVAL=1440', l_repeat, 'Intervall');
        spm_job.create_job(p_interval_minutes => 720, p_job_name => C_TEST_JOB, p_symbol_like => 'TSTOK');
        select enabled, repeat_interval into l_enabled, l_repeat from user_scheduler_jobs where job_name = C_TEST_JOB;
        eq('FREQ=MINUTELY;INTERVAL=720', l_repeat, 'Intervall geändert');
        eq('FALSE', l_enabled, 'weiterhin nicht eingeschaltet');

        start_case('Job: Lauf in der Scheduler-Session');
        run_job_and_wait(l_status, l_error);
        eq('SUCCEEDED', l_status, 'Status in der Job-Historie');
        r := last_run_of('SCHEDULER', 'TSTOK');
        eq('SUCCESS', r.status, 'Abruflauf');
        eq(1, r.cnt_stored, 'gespeichert');
        eq(spm_poll.C_STATUS_SUCCESS, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');

        start_case('Job: systemischer Fehler wird vom Scheduler als FAILED verbucht');
        spm_job.create_job(p_interval_minutes => 1440, p_job_name => C_TEST_JOB, p_symbol_like => 'TSTSYS');
        run_job_and_wait(l_status, l_error);
        eq('FAILED', l_status, 'Status in der Job-Historie');
        eq(-spm_poll.C_ERR_SYSTEMIC, l_error, 'Fehlernummer in der Job-Historie');
        r := last_run_of('SCHEDULER', 'TSTSYS');
        eq('FAILED', r.status, 'Abruflauf');
        eq(spm_poll.C_STATUS_FAILED, proc_status(r.lilam_process_id), 'LILAM-Prozessstatus');
        ok(proc_closed(r.lilam_process_id), 'LILAM-Prozess geschlossen');

        start_case('Job: Statussicht');
        g_job_orig := spm_cfg.get_text('POLL_JOB_NAME');
        update spm_config set param_value = C_TEST_JOB where param_name = 'POLL_JOB_NAME';
        commit;
        select * into v from spm_job_status_v;
        eq(C_TEST_JOB, v.job_name, 'Job-Name');
        eq('Y', v.job_exists, 'Job vorhanden');
        eq('FALSE', v.enabled, 'nicht eingeschaltet');
        eq('FAILED', v.last_job_status, 'letzter Job-Status');
        eq(-spm_poll.C_ERR_SYSTEMIC, v.last_job_error, 'letzter Job-Fehler');

        start_case('Job: entfernen');
        spm_job.drop_job(C_TEST_JOB);
        select count(*) into l_count from user_scheduler_jobs where job_name = C_TEST_JOB;
        eq(0, l_count, 'Job entfernt');
        select * into v from spm_job_status_v;
        eq('N', v.job_exists, 'Sicht ohne Job');
        update spm_config set param_value = g_job_orig where param_name = 'POLL_JOB_NAME';
        commit;
    end t_job;

    ------------------------------------------------------------------------
    procedure run_all is
    begin
        g_pass := 0;
        g_fail := 0;
        setup;

        begin t_success;   exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_duplicate; exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_failures;  exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_mixed;     exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_quota;     exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_systemic;  exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_lock;      exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_baseline;  exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_rules;     exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;
        begin t_job;       exception when others then ok(false, 'Ausnahme: ' || sqlerrm || ' ' || dbms_utility.format_error_backtrace); end;

        teardown;
        dbms_output.put_line('');
        dbms_output.put_line('SPM-Tests: ' || g_pass || ' bestanden, ' || g_fail || ' fehlgeschlagen');
        if g_fail > 0 then
            raise_application_error(-20900, 'SPM-Tests: ' || g_fail || ' Prüfungen fehlgeschlagen');
        end if;
    end run_all;

end spm_test;
/
