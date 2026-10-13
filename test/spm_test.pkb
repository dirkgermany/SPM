create or replace package body spm_test as

    g_pass pls_integer := 0;
    g_fail pls_integer := 0;
    g_case varchar2(100);

    type t_text_tab is table of varchar2(30);

    C_SYMBOLS constant t_text_tab := t_text_tab(
        'TSTOK', 'TSTSTR', 'TSTDUP', 'TSTH500', 'TSTTMO', 'TSTJSN', 'TSTNOP', 'TSTNAN', 'TSTSYM',
        'TSTCCY', 'TSTOLD', 'TSTFUT', 'TSTNEG', 'TSTKEY', 'TSTM1', 'TSTM2', 'TSTM3', 'TSTQ1', 'TSTQ2',
        'TSTSYS', 'TSTB');

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
    procedure setup is
    begin
        for i in 1 .. C_SYMBOLS.count loop
            spm_watchlist.save_instrument(p_symbol => C_SYMBOLS(i), p_provider_code => 'MOCK',
                                          p_provider_symbol => C_SYMBOLS(i), p_currency => 'EUR',
                                          p_name => 'Test ' || C_SYMBOLS(i), p_is_active => 'Y');
        end loop;

        delete from spm_price
        where  instrument_id in (select instrument_id from spm_instrument where symbol like 'TST%')
        or     run_id in (select run_id from spm_run where trigger_type = 'TEST');
        delete from spm_run where trigger_type = 'TEST';
        update spm_instrument
        set    last_fetch_at = null, last_fetch_status = null, last_fetch_message = null
        where  symbol like 'TST%';
        spm_prov_mock.reset_state;
        commit;
    end setup;

    procedure teardown is
    begin
        update spm_instrument set is_active = 'N' where symbol like 'TST%';
        commit;
    end teardown;

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

        teardown;
        dbms_output.put_line('');
        dbms_output.put_line('SPM-Tests: ' || g_pass || ' bestanden, ' || g_fail || ' fehlgeschlagen');
        if g_fail > 0 then
            raise_application_error(-20900, 'SPM-Tests: ' || g_fail || ' Prüfungen fehlgeschlagen');
        end if;
    end run_all;

end spm_test;
/
