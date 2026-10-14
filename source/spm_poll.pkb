create or replace package body spm_poll as

    C_LOCK_NAME constant varchar2(30) := 'SPM_POLL_RUN';

    type t_counts is record (
        active     pls_integer := 0,
        requested  pls_integer := 0,
        fetched    pls_integer := 0,
        failed     pls_integer := 0,
        stored     pls_integer := 0,
        duplicate  pls_integer := 0
    );

    type t_instrument_tab is table of spm_instrument%rowtype;

    g_lock_handle varchar2(128);

    ------------------------------------------------------------------------
    -- SPM_RUN in eigener Transaktion: bleibt auch bei Rollback des Laufs erhalten
    ------------------------------------------------------------------------
    function start_run(p_trigger varchar2, p_symbol_like varchar2, p_status varchar2) return number is
        pragma autonomous_transaction;
        l_run_id spm_run.run_id%type;
    begin
        insert into spm_run (trigger_type, symbol_filter, status)
        values (p_trigger, substr(p_symbol_like, 1, 40), p_status)
        returning run_id into l_run_id;
        commit;
        return l_run_id;
    end start_run;

    procedure set_run_process(p_run_id number, p_pid number) is
        pragma autonomous_transaction;
    begin
        update spm_run set lilam_process_id = p_pid where run_id = p_run_id;
        commit;
    end set_run_process;

    procedure finish_run(p_run_id number, p_status varchar2, p_counts t_counts, p_message varchar2) is
        pragma autonomous_transaction;
    begin
        update spm_run
        set    ended_at      = systimestamp,
               status        = p_status,
               cnt_active    = p_counts.active,
               cnt_requested = p_counts.requested,
               cnt_fetched   = p_counts.fetched,
               cnt_failed    = p_counts.failed,
               cnt_stored    = p_counts.stored,
               cnt_duplicate = p_counts.duplicate,
               message       = substr(p_message, 1, 1000)
        where  run_id = p_run_id;
        commit;
    end finish_run;

    ------------------------------------------------------------------------
    -- Sperre gegen überlappende Läufe (sessionübergreifend, nicht an Commit gebunden)
    ------------------------------------------------------------------------
    function acquire_lock return boolean is
        l_rc integer;
    begin
        if g_lock_handle is null then
            dbms_lock.allocate_unique_autonomous(C_LOCK_NAME, g_lock_handle);
        end if;
        l_rc := dbms_lock.request(g_lock_handle, dbms_lock.x_mode, timeout => 0, release_on_commit => false);
        return l_rc = 0; -- 1 = belegt, 4 = diese Session hält die Sperre bereits
    end acquire_lock;

    procedure release_lock is
        l_rc integer;
    begin
        if g_lock_handle is not null then
            l_rc := dbms_lock.release(g_lock_handle);
        end if;
    end release_lock;

    ------------------------------------------------------------------------
    -- Fachliche Prüfung eines geparsten Quotes
    ------------------------------------------------------------------------
    function age_seconds(p_quote_ts_utc timestamp) return number is
    begin
        return round((cast(spm_prov.utc_now as date) - cast(p_quote_ts_utc as date)) * 86400);
    end age_seconds;

    procedure validate(p_inst spm_instrument%rowtype, p_quote in out nocopy spm_prov.t_quote) is
        l_now     timestamp := spm_prov.utc_now;
        l_skew    number    := spm_cfg.get_number('MAX_FUTURE_SKEW_SECONDS', 300);
        l_max_age number    := spm_cfg.get_number('MAX_QUOTE_AGE_MINUTES', 4320);
    begin
        if p_quote.price <= 0 then
            p_quote.outcome := spm_prov.C_INVALID;
            p_quote.message := 'Kurs muss größer 0 sein: ' || p_quote.price;
        elsif p_quote.currency <> p_inst.currency then
            p_quote.outcome := spm_prov.C_INVALID;
            p_quote.message := 'Währung ' || p_quote.currency || ' statt ' || p_inst.currency;
        elsif p_quote.quote_ts_utc > l_now + numtodsinterval(l_skew, 'second') then
            p_quote.outcome := spm_prov.C_INVALID;
            p_quote.message := 'Quote-Zeitstempel liegt in der Zukunft: '
                            || to_char(p_quote.quote_ts_utc, 'YYYY-MM-DD HH24:MI:SS') || ' UTC';
        elsif p_quote.quote_ts_utc < l_now - numtodsinterval(l_max_age, 'minute') then
            p_quote.outcome := spm_prov.C_STALE;
            p_quote.message := 'Quote älter als ' || l_max_age || ' Minuten: '
                            || to_char(p_quote.quote_ts_utc, 'YYYY-MM-DD HH24:MI:SS') || ' UTC';
        end if;
    end validate;

    ------------------------------------------------------------------------
    -- Ein Symbol: abrufen (Trace), prüfen, speichern, an LILAM melden.
    -- Fachdaten werden je Symbol committet; LILAM-Meldungen erst danach.
    ------------------------------------------------------------------------
    procedure process_instrument(
        p_pid     number,
        p_run_id  number,
        p_inst    spm_instrument%rowtype,
        p_counts  in out nocopy t_counts,
        p_quote   out spm_prov.t_quote
    ) is
        l_empty  spm_prov.t_quote;
        l_age    number;
        l_stored boolean := false;
    begin
        p_counts.requested := p_counts.requested + 1;

        lilam.trace_start(p_pid, C_ACT_PROVIDER_CALL, p_inst.symbol);
        begin
            p_quote := spm_prov.fetch_quote(p_inst);
        exception
            when others then
                p_quote         := l_empty;
                p_quote.outcome := spm_prov.C_ERROR;
                p_quote.message := spm_prov.sanitize('Adapterfehler: ' || sqlerrm);
        end;
        lilam.trace_stop(p_pid, C_ACT_PROVIDER_CALL, p_inst.symbol);

        if p_quote.outcome = spm_prov.C_OK then
            validate(p_inst, p_quote);
        end if;

        if p_quote.outcome in (spm_prov.C_OK, spm_prov.C_STALE) then
            l_age := age_seconds(p_quote.quote_ts_utc);
        end if;

        if p_quote.outcome = spm_prov.C_OK then
            savepoint spm_before_price;
            begin
                insert into spm_price (instrument_id, price, currency, quote_ts_utc, run_id, provider_code)
                values (p_inst.instrument_id, p_quote.price, p_quote.currency, p_quote.quote_ts_utc,
                        p_run_id, p_inst.provider_code);
                l_stored := true;
            exception
                when dup_val_on_index then
                    rollback to spm_before_price;
                    p_quote.outcome := spm_prov.C_DUPLICATE;
                    p_quote.message := 'Quote vom ' || to_char(p_quote.quote_ts_utc, 'YYYY-MM-DD HH24:MI:SS')
                                    || ' UTC bereits gespeichert';
                when others then
                    rollback to spm_before_price;
                    p_quote.outcome := spm_prov.C_ERROR;
                    p_quote.message := spm_prov.sanitize('Speichern fehlgeschlagen: ' || sqlerrm);
            end;
        end if;

        if p_quote.outcome in (spm_prov.C_OK, spm_prov.C_DUPLICATE) then
            p_counts.fetched := p_counts.fetched + 1;
        else
            p_counts.failed := p_counts.failed + 1;
        end if;
        if l_stored then
            p_counts.stored := p_counts.stored + 1;
        end if;
        if p_quote.outcome = spm_prov.C_DUPLICATE then
            p_counts.duplicate := p_counts.duplicate + 1;
        end if;

        update spm_instrument
        set    last_fetch_at      = systimestamp,
               last_fetch_status  = p_quote.outcome,
               last_fetch_message = p_quote.message
        where  instrument_id = p_inst.instrument_id;

        commit;

        -- Nur gespeicherte Kurse speisen die Wertreihe (Doppelabrufe verfälschen den EWMA nicht)
        if l_stored then
            lilam.mark_event(p_pid, C_ACT_SHARE_PRICE, p_inst.symbol, p_quote.price);
        end if;
        if l_age is not null then
            lilam.mark_event(p_pid, C_ACT_QUOTE_AGE, p_inst.symbol, l_age);
        end if;

        if p_quote.outcome = spm_prov.C_DUPLICATE then
            lilam.info(p_pid, p_inst.symbol || ': ' || p_quote.message);
        elsif p_quote.outcome <> spm_prov.C_OK then
            lilam.warn(p_pid, p_inst.symbol || ': ' || p_quote.outcome
                           || case when p_quote.http_status is not null then ' (HTTP ' || p_quote.http_status || ')' end
                           || ' ' || p_quote.message);
        end if;

        lilam.proc_step_done(p_pid);
    end process_instrument;

    procedure mark_counts(p_pid number, p_counts t_counts) is
    begin
        lilam.mark_event(p_pid, C_ACT_POLL_RESULT, 'REQUESTED', p_counts.requested);
        lilam.mark_event(p_pid, C_ACT_POLL_RESULT, 'FETCHED',   p_counts.fetched);
        lilam.mark_event(p_pid, C_ACT_POLL_RESULT, 'FAILED',    p_counts.failed);
        lilam.mark_event(p_pid, C_ACT_POLL_RESULT, 'STORED',    p_counts.stored);
        lilam.mark_event(p_pid, C_ACT_POLL_RESULT, 'DUPLICATE', p_counts.duplicate);
    end mark_counts;

    function counts_text(p_counts t_counts) return varchar2 is
    begin
        return 'angefragt ' || p_counts.requested || ', erhalten ' || p_counts.fetched
            || ', fehlerhaft ' || p_counts.failed || ', gespeichert ' || p_counts.stored
            || ', doppelt ' || p_counts.duplicate || ' (aktiv ' || p_counts.active || ')';
    end counts_text;

    ------------------------------------------------------------------------
    function run(p_trigger varchar2 default 'MANUAL', p_symbol_like varchar2 default null) return number is
        l_trigger    spm_run.trigger_type%type := upper(substr(nvl(p_trigger, 'MANUAL'), 1, 20));
        l_run_id     number;
        l_pid        number;
        l_counts     t_counts;
        l_insts      t_instrument_tab;
        l_quote      spm_prov.t_quote;
        l_abort      varchar2(500);
        l_systemic   boolean := false;
        l_status     pls_integer;
        l_info       varchar2(1000);
        l_errm       varchar2(4000);
    begin
        if not acquire_lock then
            l_run_id := start_run(l_trigger, p_symbol_like, 'SKIPPED');
            finish_run(l_run_id, 'SKIPPED', l_counts, 'Übersprungen: ein anderer Abruflauf ist aktiv');
            return l_run_id;
        end if;

        l_run_id := start_run(l_trigger, p_symbol_like, 'RUNNING');

        select *
        bulk   collect into l_insts
        from   spm_instrument
        where  is_active = 'Y'
        and    (p_symbol_like is null or symbol like p_symbol_like)
        order  by symbol;
        l_counts.active := l_insts.count;

        l_pid := lilam.new_process(
                     p_processName   => spm_cfg.get_text('POLL_PROCESS_NAME', 'SPM_POLL'),
                     p_logLevel      => spm_cfg.get_number('LILAM_LOG_LEVEL', lilam.logLevelInfo),
                     p_procStepsToDo => l_counts.active,
                     p_daysToKeep    => spm_cfg.get_number('LILAM_DAYS_TO_KEEP'),
                     p_tabNameMaster => spm_cfg.get_text('LILAM_TABNAME_MASTER', 'LILAM'),
                     p_baselineScope => spm_cfg.get_text('LILAM_BASELINE_SCOPE'),
                     p_groupName     => spm_cfg.get_text('LILAM_GROUP'));
        set_run_process(l_run_id, l_pid);

        lilam.info(l_pid, 'Abruflauf ' || l_run_id || ' (' || l_trigger || ') gestartet, '
                       || l_counts.active || ' aktive Symbole'
                       || case when p_symbol_like is not null then ', Filter ' || p_symbol_like end);

        for i in 1 .. l_insts.count loop
            process_instrument(l_pid, l_run_id, l_insts(i), l_counts, l_quote);
            if l_quote.outcome in (spm_prov.C_QUOTA, spm_prov.C_SYSTEMIC) then
                l_abort    := l_insts(i).symbol || ': ' || l_quote.outcome || ' ' || l_quote.message;
                l_systemic := l_quote.outcome = spm_prov.C_SYSTEMIC;
                exit;
            end if;
        end loop;

        mark_counts(l_pid, l_counts);

        if l_systemic then
            raise_application_error(C_ERR_SYSTEMIC, 'Abruflauf abgebrochen, systemischer Fehler bei ' || l_abort);
        end if;

        l_status := case
                        when l_counts.failed = 0 and l_abort is null then C_STATUS_SUCCESS
                        when l_counts.fetched > 0                    then C_STATUS_PARTIAL
                        else C_STATUS_FAILED
                    end;
        l_info := counts_text(l_counts);
        if l_abort is not null then
            l_info := 'Vorzeitig beendet (' || l_abort || '); ' || l_info;
            lilam.error(l_pid, 'Abruflauf ' || l_run_id || ' vorzeitig beendet: ' || l_abort);
        end if;

        lilam.close_process(l_pid, substr(l_info, 1, 2000), l_status);
        finish_run(l_run_id,
                   case l_status when C_STATUS_SUCCESS then 'SUCCESS' when C_STATUS_PARTIAL then 'PARTIAL' else 'FAILED' end,
                   l_counts, l_info);
        release_lock;

        -- Zweiter Prüfer neben dem Watchdog-Job (meldet u. a. einen ausgefallenen Watchdog).
        -- CHECK_SILENCE wirft laut LILAM keine Ausnahme; zur Sicherheit trotzdem gekapselt.
        begin
            if spm_cfg.get_text('LILAM_GROUP') is not null then
                lilam.check_silence(spm_cfg.get_text('LILAM_GROUP'));
            end if;
        exception
            when others then null;
        end;

        return l_run_id;

    exception
        when others then
            -- Ursache sichern, bevor Aufräumarbeiten eigene Fehler erzeugen können
            l_errm := substr(sqlerrm || ' ' || dbms_utility.format_error_backtrace, 1, 4000);
            begin
                rollback;
            exception
                when others then null;
            end;
            begin
                if l_pid is not null then
                    lilam.error(l_pid, 'Abruflauf ' || l_run_id || ' abgebrochen: ' || l_errm);
                    lilam.close_process(l_pid, substr('Abgebrochen: ' || l_errm, 1, 2000), C_STATUS_FAILED);
                end if;
            exception
                when others then null;
            end;
            begin
                if l_run_id is not null then
                    finish_run(l_run_id, 'FAILED', l_counts, l_errm);
                end if;
            exception
                when others then null;
            end;
            begin
                release_lock;
            exception
                when others then null;
            end;
            raise;
    end run;

    procedure run(p_trigger varchar2 default 'MANUAL', p_symbol_like varchar2 default null) is
        l_run_id number;
    begin
        l_run_id := run(p_trigger, p_symbol_like);
    end run;

end spm_poll;
/
