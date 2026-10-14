create or replace package body spm_rules as

    C_SEVERITIES constant varchar2(100) := ',' || C_HINWEIS || ',' || C_WARNUNG || ',' || C_ALARM || ',' || C_KRITISCH || ',';

    ------------------------------------------------------------------------
    -- Pflege
    ------------------------------------------------------------------------
    function get_instrument_id(p_symbol varchar2) return number is
        l_id spm_instrument.instrument_id%type;
    begin
        select instrument_id into l_id from spm_instrument where symbol = spm_watchlist.normalize_symbol(p_symbol);
        return l_id;
    exception
        when no_data_found then
            raise_application_error(C_ERR_RULE, 'Symbol nicht in der Watchlist: ' || spm_watchlist.normalize_symbol(p_symbol));
    end get_instrument_id;

    procedure check_severity(p_severity varchar2, p_name varchar2) is
    begin
        if p_severity is null or instr(C_SEVERITIES, ',' || p_severity || ',') = 0 then
            raise_application_error(C_ERR_RULE, p_name || ' muss HINWEIS, WARNUNG, ALARM oder KRITISCH sein');
        end if;
    end check_severity;

    -- Zeitfenster mit LILAM prüfen (Format der Tage/Zeiten, Zeitzone): Probe-Regel durch CHECK_RULE_SET
    procedure check_windows(p_windows varchar2, p_time_zone varchar2) is
        l_set   json_object_t := json_object_t();
        l_rules json_array_t  := json_array_t();
        l_rule  json_object_t := json_object_t();
        l_cond  json_object_t := json_object_t();
        l_alert json_object_t := json_object_t();
        l_win   json_array_t;
        l_error varchar2(4000);
    begin
        if p_windows is null then
            if p_time_zone is not null then
                raise_application_error(C_ERR_RULE, 'Zeitzone nur zusammen mit Zeitfenstern');
            end if;
            return;
        end if;
        if p_time_zone is null then
            raise_application_error(C_ERR_RULE, 'Zeitfenster brauchen eine Zeitzone (z. B. Europe/Berlin)');
        end if;
        begin
            l_win := json_array_t.parse(p_windows);
        exception
            when others then
                raise_application_error(C_ERR_RULE, 'Zeitfenster müssen ein JSON-Array sein, z. B. '
                    || '[{"days":"MON-FRI","from":"09:00","to":"17:30"}]');
        end;

        l_rule.put('id', 'CHECK');
        l_rule.put('trigger_type', 'MARK_EVENT');
        l_rule.put('action', 'CHECK');
        l_cond.put('operator', 'TIME_MAX_SILENCE_SECONDS');
        l_cond.put('value', '60');
        l_rule.put('condition', l_cond);
        l_rule.put('windows', l_win);
        l_rule.put('time_zone', p_time_zone);
        l_alert.put('handler', 'CHECK');
        l_rule.put('alert', l_alert);
        l_rules.append(l_rule);
        l_set.put('rules', l_rules);

        l_error := lilam.check_rule_set(l_set.to_clob);
        if l_error is not null then
            raise_application_error(C_ERR_RULE, 'Zeitfenster ungültig: ' || substr(l_error, 1, 500));
        end if;
    end check_windows;

    procedure save_rule(
        p_symbol            varchar2,
        p_val_min           number   default null,
        p_val_max           number   default null,
        p_ewma_pct_up       number   default null,
        p_ewma_pct_down     number   default null,
        p_ewma_warmup       number   default null,
        p_ewma_alpha        number   default null,
        p_severity_limit    varchar2 default 'ALARM',
        p_severity_ewma     varchar2 default 'WARNUNG',
        p_throttle_seconds  number   default 3600,
        p_is_active         varchar2 default 'Y',
        p_silence_seconds   number   default null,
        p_silence_windows   varchar2 default null,
        p_silence_time_zone varchar2 default null,
        p_severity_silence  varchar2 default 'WARNUNG'
    ) is
        l_id number := get_instrument_id(p_symbol);
    begin
        if p_silence_seconds <= 0 or p_silence_seconds <> trunc(p_silence_seconds) then
            raise_application_error(C_ERR_RULE, 'Schweigezeit in ganzen Sekunden größer 0 angeben');
        end if;
        if p_silence_seconds is null and (p_silence_windows is not null or p_silence_time_zone is not null) then
            raise_application_error(C_ERR_RULE, 'Zeitfenster nur zusammen mit einer Schweigezeit');
        end if;
        check_windows(p_silence_windows, p_silence_time_zone);
        check_severity(p_severity_silence, 'Dringlichkeit der Schweige-Regel');
        if p_val_min is not null and p_val_max is not null and p_val_min >= p_val_max then
            raise_application_error(C_ERR_RULE, 'Untergrenze muss kleiner als Obergrenze sein');
        end if;
        if p_ewma_pct_up <= 0 or p_ewma_pct_down <= 0 then
            raise_application_error(C_ERR_RULE, 'EWMA-Abweichung in Prozent muss größer 0 sein');
        end if;
        if (p_ewma_warmup is not null or p_ewma_alpha is not null)
           and p_ewma_pct_up is null and p_ewma_pct_down is null then
            raise_application_error(C_ERR_RULE, 'Warm-up und Alpha nur zusammen mit einer EWMA-Abweichung');
        end if;
        if p_ewma_warmup < 1 or p_ewma_warmup <> trunc(p_ewma_warmup) then
            raise_application_error(C_ERR_RULE, 'Warm-up muss eine ganze Zahl ab 1 sein');
        end if;
        if p_ewma_alpha <= 0 or p_ewma_alpha > 1 then
            raise_application_error(C_ERR_RULE, 'Alpha muss größer 0 und höchstens 1 sein');
        end if;
        if p_throttle_seconds is null or p_throttle_seconds < 0 then
            raise_application_error(C_ERR_RULE, 'Drosselung (Sekunden) muss 0 oder größer sein');
        end if;
        if nvl(p_is_active, '?') not in ('Y', 'N') then
            raise_application_error(C_ERR_RULE, 'Aktiv-Kennzeichen muss Y oder N sein');
        end if;
        check_severity(p_severity_limit, 'Dringlichkeit der Grenzwerte');
        check_severity(p_severity_ewma, 'Dringlichkeit der Ausreißer-Regeln');

        merge into spm_rule r
        using (select l_id id from dual) s
        on (r.instrument_id = s.id)
        when matched then update set
            r.val_min = p_val_min, r.val_max = p_val_max,
            r.ewma_pct_up = p_ewma_pct_up, r.ewma_pct_down = p_ewma_pct_down,
            r.ewma_warmup = p_ewma_warmup, r.ewma_alpha = p_ewma_alpha,
            r.severity_limit = p_severity_limit, r.severity_ewma = p_severity_ewma,
            r.throttle_seconds = p_throttle_seconds, r.is_active = p_is_active,
            r.silence_seconds = p_silence_seconds, r.silence_windows = p_silence_windows,
            r.silence_time_zone = p_silence_time_zone, r.severity_silence = p_severity_silence,
            r.updated_at = systimestamp
        when not matched then insert
            (instrument_id, val_min, val_max, ewma_pct_up, ewma_pct_down, ewma_warmup, ewma_alpha,
             severity_limit, severity_ewma, throttle_seconds, is_active,
             silence_seconds, silence_windows, silence_time_zone, severity_silence)
        values
            (l_id, p_val_min, p_val_max, p_ewma_pct_up, p_ewma_pct_down, p_ewma_warmup, p_ewma_alpha,
             p_severity_limit, p_severity_ewma, p_throttle_seconds, p_is_active,
             p_silence_seconds, p_silence_windows, p_silence_time_zone, p_severity_silence);
    end save_rule;

    procedure delete_rule(p_symbol varchar2) is
        l_id number := get_instrument_id(p_symbol);
    begin
        delete from spm_rule where instrument_id = l_id;
    end delete_rule;

    ------------------------------------------------------------------------
    -- Rule Set
    ------------------------------------------------------------------------

    -- Zahl als JSON-Text mit Dezimalpunkt
    function num(p_value number) return varchar2 is
    begin
        return rtrim(to_char(p_value, 'FM999999999999999999990.99999999999999999999',
                             'NLS_NUMERIC_CHARACTERS=''.,'''), '.');
    end num;

    -- Zahl für Regeltexte mit deutschem Komma (num liefert den Punkt für JSON-Werte)
    function txt(p_value number) return varchar2 is
    begin
        return replace(num(p_value), '.', ',');
    end txt;

    -- Sekunden lesbar für Regeltexte: 45 s, 15 min, 2 h, 1 h 30 min
    function dur(p_seconds number) return varchar2 is
        l_min number := round(p_seconds / 60);
    begin
        return case
                   when p_seconds < 120 then num(round(p_seconds)) || ' s'
                   when l_min < 120     then l_min || ' min'
                   else trunc(l_min / 60) || ' h' || case when mod(l_min, 60) > 0 then ' ' || mod(l_min, 60) || ' min' end
               end;
    end dur;

    procedure add_rule(
        p_rules     in out nocopy json_array_t,
        p_id        varchar2,
        p_comment   varchar2,
        p_trigger   varchar2,
        p_action    varchar2,
        p_context   varchar2,
        p_operator  varchar2,
        p_value     varchar2,
        p_severity  varchar2,
        p_throttle  number,
        p_windows   varchar2 default null,
        p_time_zone varchar2 default null
    ) is
        l_rule  json_object_t := json_object_t();
        l_cond  json_object_t := json_object_t();
        l_alert json_object_t := json_object_t();
    begin
        l_rule.put('id', p_id);
        l_rule.put('_comment', p_comment);
        l_rule.put('trigger_type', p_trigger);
        l_rule.put('action', p_action);
        if p_context is not null then
            l_rule.put('context', p_context);
        end if;

        l_cond.put('operator', p_operator);
        if p_value is not null then
            l_cond.put('value', p_value);
        end if;
        l_rule.put('condition', l_cond);
        if p_windows is not null then
            l_rule.put('windows', json_array_t.parse(p_windows));
            l_rule.put('time_zone', p_time_zone);
        end if;

        l_alert.put('handler', spm_cfg.get_text('RULE_HANDLER', 'SPM_ALERT'));
        l_alert.put('severity', p_severity);
        l_alert.put('throttle_seconds', p_throttle);
        l_rule.put('alert', l_alert);

        p_rules.append(l_rule);
    end add_rule;

    procedure add_technical_rules(p_rules in out nocopy json_array_t) is
        l_process  varchar2(100) := spm_cfg.get_text('POLL_PROCESS_NAME', 'SPM_POLL');
        l_throttle number        := spm_cfg.get_number('RULE_TECH_THROTTLE_SECONDS', 3600);
        l_limit    number;
    begin
        add_rule(p_rules, 'SPM-RUN-FAILED', 'Abruflauf fehlgeschlagen',
                 'PROCESS_STOP', l_process, null, 'STATUS_EQUALS', num(spm_poll.C_STATUS_FAILED), C_ALARM, l_throttle);
        add_rule(p_rules, 'SPM-RUN-PARTIAL', 'Abruflauf nur teilweise erfolgreich',
                 'PROCESS_STOP', l_process, null, 'STATUS_EQUALS', num(spm_poll.C_STATUS_PARTIAL), C_WARNUNG, l_throttle);

        l_limit := spm_cfg.get_number('RULE_RUN_MAX_MS');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-RUN-SLOW', 'Abruflauf dauert länger als ' || dur(l_limit / 1000),
                     'PROCESS_STOP', l_process, null, 'TIME_MAX_RUNTIME_EXCEEDED', num(l_limit), C_HINWEIS, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_PROVIDER_CALL_MAX_MS');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-PROVIDER-SLOW', 'Provider-Aufruf dauert länger als ' || dur(l_limit / 1000),
                     'TRACE_STOP', spm_poll.C_ACT_PROVIDER_CALL, null, 'TIME_MAX_DURATION_MS', num(l_limit), C_HINWEIS, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_POLL_FAILED_MAX');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-POLL-FAILED', case when l_limit = 0 then 'Fehlerhafte Symbole in einem Abruflauf' else 'Mehr als ' || num(l_limit) || ' fehlerhafte Symbole in einem Abruflauf' end,
                     'MARK_EVENT', spm_poll.C_ACT_POLL_RESULT, 'FAILED', 'VAL_MAX', num(l_limit), C_WARNUNG, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_QUOTE_AGE_MAX_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-QUOTE-AGE', 'Kurs vom Provider älter als ' || dur(l_limit),
                     'MARK_EVENT', spm_poll.C_ACT_QUOTE_AGE, null, 'VAL_MAX', num(l_limit), C_WARNUNG, l_throttle);
        end if;

        -- Watchdog: Schweige-Regeln, geprüft durch LILAM.CHECK_SILENCE (Watchdog- und Abruf-Job)
        l_limit := spm_cfg.get_number('RULE_POLL_SILENCE_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-POLL-SILENT', 'Kein Abruflauf seit ' || dur(l_limit),
                     'PROCESS_START', l_process, null, 'TIME_MAX_SILENCE_SECONDS', num(l_limit), C_KRITISCH, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_RUN_HANG_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-RUN-HANG', 'Abruflauf meldet sich seit ' || dur(l_limit) || ' nicht',
                     'PROCESS_UPDATE', l_process, null, 'TIME_MAX_SILENCE_SECONDS', num(l_limit), C_KRITISCH, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_WATCHDOG_SILENCE_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-WATCHDOG-SILENT', 'Kein Watchdog-Lauf seit ' || dur(l_limit),
                     'PROCESS_START', spm_cfg.get_text('WATCHDOG_PROCESS_NAME', 'SPM_WATCHDOG'), null,
                     'TIME_MAX_SILENCE_SECONDS', num(l_limit), C_ALARM, l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_NOTIFY_SILENCE_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-NOTIFY-SILENT', 'Kein Zustell-Lauf seit ' || dur(l_limit),
                     'PROCESS_START', spm_cfg.get_text('NOTIFY_PROCESS_NAME', 'SPM_NOTIFY'), null,
                     'TIME_MAX_SILENCE_SECONDS', num(l_limit), C_ALARM, l_throttle);
        end if;

        -- Watchdog meldet den Zustand des Abruf-Jobs: 1 = in Ordnung, 0 = nicht
        add_rule(p_rules, 'SPM-POLLJOB-BAD', 'Abruf-Job fehlt, ist ausgeschaltet oder zuletzt fehlgeschlagen',
                 'MARK_EVENT', spm_watchdog.C_ACT_POLL_JOB_HEALTH, null, 'VAL_MIN', '1', C_KRITISCH, l_throttle);
    end add_technical_rules;

    -- 'pct[|warmup[|alpha]]'; Alpha ohne Warm-up braucht den LILAM-Standard 3 als Platzhalter
    function ewma_value(p_pct number, p_warmup number, p_alpha number) return varchar2 is
    begin
        return num(p_pct)
            || case when p_warmup is not null or p_alpha is not null then '|' || num(nvl(p_warmup, 3)) end
            || case when p_alpha is not null then '|' || num(p_alpha) end;
    end ewma_value;

    procedure add_symbol_rules(p_rules in out nocopy json_array_t) is
        l_action varchar2(30) := spm_poll.C_ACT_SHARE_PRICE;
    begin
        for r in (select i.symbol, i.currency, s.*
                  from   spm_rule s join spm_instrument i on i.instrument_id = s.instrument_id
                  where  s.is_active = 'Y' and i.is_active = 'Y'
                  order  by i.symbol) loop
            if r.val_min is not null then
                add_rule(p_rules, r.symbol || '-MIN', 'Kurs unter ' || txt(r.val_min) || ' ' || r.currency,
                         'MARK_EVENT', l_action, r.symbol, 'VAL_MIN', num(r.val_min), r.severity_limit, r.throttle_seconds);
            end if;
            if r.val_max is not null then
                add_rule(p_rules, r.symbol || '-MAX', 'Kurs über ' || txt(r.val_max) || ' ' || r.currency,
                         'MARK_EVENT', l_action, r.symbol, 'VAL_MAX', num(r.val_max), r.severity_limit, r.throttle_seconds);
            end if;
            -- _UP und _DOWN teilen Warm-up und Alpha der Reihe: beide mit denselben Werten
            if r.ewma_pct_up is not null then
                add_rule(p_rules, r.symbol || '-UP', 'Kurs mehr als ' || txt(r.ewma_pct_up) || ' % über dem gleitenden Mittel',
                         'MARK_EVENT', l_action, r.symbol, 'VAL_EWMA_DEVIATION_PCT_UP',
                         ewma_value(r.ewma_pct_up, r.ewma_warmup, r.ewma_alpha), r.severity_ewma, r.throttle_seconds);
            end if;
            if r.ewma_pct_down is not null then
                add_rule(p_rules, r.symbol || '-DOWN', 'Kurs mehr als ' || txt(r.ewma_pct_down) || ' % unter dem gleitenden Mittel',
                         'MARK_EVENT', l_action, r.symbol, 'VAL_EWMA_DEVIATION_PCT_DOWN',
                         ewma_value(r.ewma_pct_down, r.ewma_warmup, r.ewma_alpha), r.severity_ewma, r.throttle_seconds);
            end if;
            -- Kein neuer Kurs; Doppelabrufe zählen nicht (SHARE_PRICE nur für neu gespeicherte Kurse)
            if r.silence_seconds is not null then
                add_rule(p_rules, r.symbol || '-SILENT', 'Kein neuer Kurs seit ' || dur(r.silence_seconds),
                         'MARK_EVENT', l_action, r.symbol, 'TIME_MAX_SILENCE_SECONDS', num(r.silence_seconds),
                         r.severity_silence, r.throttle_seconds, r.silence_windows, r.silence_time_zone);
            end if;
        end loop;
    end add_symbol_rules;

    function build_rule_set return clob is
        l_set    json_object_t := json_object_t();
        l_header json_object_t := json_object_t();
        l_rules  json_array_t  := json_array_t();
    begin
        l_header.put('rule_set', spm_cfg.get_text('RULE_SET_NAME', 'SPM_RULES'));
        l_header.put('description', 'Erzeugt von SPM aus SPM_RULE und SPM_CONFIG (RULE_*). Nicht von Hand ändern.');
        l_set.put('header', l_header);

        add_technical_rules(l_rules);
        add_symbol_rules(l_rules);
        l_set.put('rules', l_rules);

        return l_set.to_clob;
    end build_rule_set;

    ------------------------------------------------------------------------
    -- Veröffentlichen
    ------------------------------------------------------------------------
    function publish(p_author varchar2 default null) return number is
        l_group       varchar2(50)  := spm_cfg.get_text('LILAM_GROUP');
        l_name        varchar2(30)  := spm_cfg.get_text('RULE_SET_NAME', 'SPM_RULES');
        l_set         clob          := build_rule_set;
        l_error       varchar2(4000);
        l_active_name lilam_rules.set_name%type;
        l_active_ver  lilam_rules.version%type;
        l_active_set  clob;
        l_version     number;
    begin
        if l_group is null then
            raise_application_error(C_ERR_PUBLISH, 'SPM_CONFIG.LILAM_GROUP ist nicht gesetzt');
        end if;

        l_error := lilam.check_rule_set(l_set);
        if l_error is not null then
            raise_application_error(C_ERR_PUBLISH, 'Rule Set ungültig: ' || substr(l_error, 1, 1000));
        end if;

        begin
            select set_name, version, rule_set
            into   l_active_name, l_active_ver, l_active_set
            from   lilam_rules
            where  upper(group_name) = upper(l_group) and is_active = 1;
        exception
            when no_data_found then
                null;
        end;

        if l_active_name = l_name and dbms_lob.compare(l_active_set, l_set) = 0 then
            return l_active_ver; -- unverändert
        end if;

        select nvl(max(version), 0) + 1
        into   l_version
        from   lilam_rules
        where  upper(group_name) = upper(l_group) and set_name = l_name;

        insert into lilam_rules (group_name, set_name, version, is_active, created, author, rule_set)
        values (l_group, l_name, l_version, 0, systimestamp,
                substr(nvl(p_author, sys_context('USERENV', 'SESSION_USER')), 1, 50), l_set);
        commit;

        lilam.server_update_rules(l_group, l_name, l_version);
        commit;
        return l_version;
    end publish;

    procedure publish(p_author varchar2 default null) is
        l_version number;
    begin
        l_version := publish(p_author);
    end publish;

end spm_rules;
/
