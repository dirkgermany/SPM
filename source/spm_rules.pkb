create or replace package body spm_rules as

    C_SEVERITIES constant varchar2(100) := ',INFO,WARN,ERROR,CRITICAL,';

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
            raise_application_error(C_ERR_RULE, p_name || ' muss INFO, WARN, ERROR oder CRITICAL sein');
        end if;
    end check_severity;

    procedure save_rule(
        p_symbol            varchar2,
        p_val_min           number   default null,
        p_val_max           number   default null,
        p_ewma_pct_up       number   default null,
        p_ewma_pct_down     number   default null,
        p_ewma_warmup       number   default null,
        p_ewma_alpha        number   default null,
        p_severity_limit    varchar2 default 'ERROR',
        p_severity_ewma     varchar2 default 'WARN',
        p_throttle_seconds  number   default 3600,
        p_is_active         varchar2 default 'Y'
    ) is
        l_id number := get_instrument_id(p_symbol);
    begin
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
        check_severity(p_severity_limit, 'Severity der Grenzwerte');
        check_severity(p_severity_ewma, 'Severity der EWMA-Regeln');

        merge into spm_rule r
        using (select l_id id from dual) s
        on (r.instrument_id = s.id)
        when matched then update set
            r.val_min = p_val_min, r.val_max = p_val_max,
            r.ewma_pct_up = p_ewma_pct_up, r.ewma_pct_down = p_ewma_pct_down,
            r.ewma_warmup = p_ewma_warmup, r.ewma_alpha = p_ewma_alpha,
            r.severity_limit = p_severity_limit, r.severity_ewma = p_severity_ewma,
            r.throttle_seconds = p_throttle_seconds, r.is_active = p_is_active,
            r.updated_at = systimestamp
        when not matched then insert
            (instrument_id, val_min, val_max, ewma_pct_up, ewma_pct_down, ewma_warmup, ewma_alpha,
             severity_limit, severity_ewma, throttle_seconds, is_active)
        values
            (l_id, p_val_min, p_val_max, p_ewma_pct_up, p_ewma_pct_down, p_ewma_warmup, p_ewma_alpha,
             p_severity_limit, p_severity_ewma, p_throttle_seconds, p_is_active);
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
        p_throttle  number
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
        add_rule(p_rules, 'SPM-RUN-FAILED', 'Abruflauf fehlgeschlagen (Status -1)',
                 'PROCESS_STOP', l_process, null, 'STATUS_EQUALS', num(spm_poll.C_STATUS_FAILED), 'ERROR', l_throttle);
        add_rule(p_rules, 'SPM-RUN-PARTIAL', 'Abruflauf teilweise erfolgreich (Status 2)',
                 'PROCESS_STOP', l_process, null, 'STATUS_EQUALS', num(spm_poll.C_STATUS_PARTIAL), 'WARN', l_throttle);

        l_limit := spm_cfg.get_number('RULE_RUN_MAX_MS');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-RUN-SLOW', 'Abruflauf dauert zu lange (ms)',
                     'PROCESS_STOP', l_process, null, 'TIME_MAX_RUNTIME_EXCEEDED', num(l_limit), 'WARN', l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_PROVIDER_CALL_MAX_MS');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-PROVIDER-SLOW', 'Provider-Aufruf dauert zu lange (ms)',
                     'TRACE_STOP', spm_poll.C_ACT_PROVIDER_CALL, null, 'TIME_MAX_DURATION_MS', num(l_limit), 'WARN', l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_POLL_FAILED_MAX');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-POLL-FAILED', 'Zu viele fehlerhafte Symbole in einem Lauf',
                     'MARK_EVENT', spm_poll.C_ACT_POLL_RESULT, 'FAILED', 'VAL_MAX', num(l_limit), 'WARN', l_throttle);
        end if;

        l_limit := spm_cfg.get_number('RULE_QUOTE_AGE_MAX_SEC');
        if l_limit is not null then
            add_rule(p_rules, 'SPM-QUOTE-AGE', 'Quote zu alt (s), je Symbol',
                     'MARK_EVENT', spm_poll.C_ACT_QUOTE_AGE, null, 'VAL_MAX', num(l_limit), 'WARN', l_throttle);
        end if;
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
                add_rule(p_rules, r.symbol || '-MIN', 'Kurs unter ' || num(r.val_min) || ' ' || r.currency,
                         'MARK_EVENT', l_action, r.symbol, 'VAL_MIN', num(r.val_min), r.severity_limit, r.throttle_seconds);
            end if;
            if r.val_max is not null then
                add_rule(p_rules, r.symbol || '-MAX', 'Kurs über ' || num(r.val_max) || ' ' || r.currency,
                         'MARK_EVENT', l_action, r.symbol, 'VAL_MAX', num(r.val_max), r.severity_limit, r.throttle_seconds);
            end if;
            -- _UP und _DOWN teilen Warm-up und Alpha der Reihe: beide mit denselben Werten
            if r.ewma_pct_up is not null then
                add_rule(p_rules, r.symbol || '-UP', 'Kurs mehr als ' || num(r.ewma_pct_up) || ' % über dem EWMA',
                         'MARK_EVENT', l_action, r.symbol, 'VAL_EWMA_DEVIATION_PCT_UP',
                         ewma_value(r.ewma_pct_up, r.ewma_warmup, r.ewma_alpha), r.severity_ewma, r.throttle_seconds);
            end if;
            if r.ewma_pct_down is not null then
                add_rule(p_rules, r.symbol || '-DOWN', 'Kurs mehr als ' || num(r.ewma_pct_down) || ' % unter dem EWMA',
                         'MARK_EVENT', l_action, r.symbol, 'VAL_EWMA_DEVIATION_PCT_DOWN',
                         ewma_value(r.ewma_pct_down, r.ewma_warmup, r.ewma_alpha), r.severity_ewma, r.throttle_seconds);
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
