create or replace package body spm_notify as

    C_ACT_MAIL_SEND     constant varchar2(30) := 'MAIL_SEND';      -- Trace je Mail (Context Regel-ID)
    C_ACT_NOTIFY_RESULT constant varchar2(30) := 'NOTIFY_RESULT';  -- Event mit Anzahl (SENT, FAILED)
    C_ERR_NOTIFY        constant pls_integer  := -20331;

    function fmt(p_value number) return varchar2 is
    begin
        return to_char(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS='',.''');
    end fmt;

    procedure line(p_body in out nocopy clob, p_label varchar2, p_value varchar2) is
    begin
        if p_value is not null then
            p_body := p_body || rpad(p_label || ':', 12) || p_value || utl_tcp.crlf;
        end if;
    end line;

    ------------------------------------------------------------------------
    -- Mailtext
    ------------------------------------------------------------------------
    procedure build_message(p_alert_id number, o_subject out varchar2, o_body out clob) is
        a           lilam_alerts%rowtype;
        l_comment   varchar2(400);
        l_operator  varchar2(100);
        l_value     varchar2(100);
        l_trigger   varchar2(30);
        l_price     number;
        l_ewma      number;
        l_millis    number;
        l_inst_name spm_instrument.instrument_name%type;
        l_currency  spm_instrument.currency%type;
        l_proc_name varchar2(100);
        l_proc_stat number;
        l_proc_info varchar2(2000);
        l_symbol    varchar2(100);
    begin
        select * into a from lilam_alerts where alert_id = p_alert_id;

        -- Regel aus dem Rule Set, mit dem der Alert ausgelöst wurde. JSON_TABLE statt mehrerer
        -- JSON_VALUE mit PASSING: diese Kombination lieferte durchweg NULL (Testbericht).
        begin
            select jt.cmt, jt.op, jt.val, jt.trg
            into   l_comment, l_operator, l_value, l_trigger
            from   lilam_rules r,
                   json_table(r.rule_set, '$.rules[*]' columns (
                       id  varchar2(50)  path '$.id',
                       cmt varchar2(400) path '$."_comment"',
                       op  varchar2(100) path '$.condition.operator',
                       val varchar2(100) path '$.condition.value',
                       trg varchar2(30)  path '$.trigger_type')) jt
            where  upper(r.group_name) = upper(a.group_name)
            and    r.set_name = a.rule_set_name and r.version = a.rule_set_version
            and    jt.id = a.rule_id;
        exception
            when no_data_found or too_many_rows then null;
        end;

        -- Messwert und EWMA der auslösenden Messung (nicht bei Schweige-Alerts ohne Prozess)
        if a.process_id is not null and a.monitor_table_name is not null and a.action_count is not null then
            begin
                execute immediate
                    'select max(used_value), max(used_value_ewma), max(used_millis) from '
                 || dbms_assert.simple_sql_name(a.monitor_table_name)
                 || ' where process_id = :1 and action = :2'
                 || ' and (context = :3 or (context is null and :4 is null)) and action_count = :5'
                    into l_price, l_ewma, l_millis
                    using a.process_id, a.action_name, a.context_name, a.context_name, a.action_count;
            exception
                when others then null; -- Tabelle nicht lesbar: Mail ohne Messwert
            end;
        end if;

        if a.process_id is not null and a.master_table_name is not null then
            begin
                execute immediate
                    'select process_name, status, info from ' || dbms_assert.simple_sql_name(a.master_table_name)
                 || ' where id = :1'
                    into l_proc_name, l_proc_stat, l_proc_info using a.process_id;
            exception
                when others then null;
            end;
        end if;

        if a.action_name = spm_poll.C_ACT_SHARE_PRICE and a.context_name is not null then
            l_symbol := a.context_name;
            begin
                select instrument_name, currency into l_inst_name, l_currency
                from   spm_instrument where symbol = a.context_name;
            exception
                when no_data_found then null;
            end;
        end if;

        o_subject := substr(spm_cfg.get_text('MAIL_SUBJECT_PREFIX', '[SPM]') || ' ' || a.alert_severity || ' '
                         || a.rule_id || ': ' || nvl(l_comment, a.action_name), 1, 400);

        o_body := 'SPM-Alert ' || a.rule_id || ' (' || a.alert_severity || ')' || utl_tcp.crlf || utl_tcp.crlf;
        line(o_body, 'Zeit',     to_char(a.created_at, 'DD.MM.YYYY HH24:MI:SS'));
        line(o_body, 'Regel',    l_comment || case when l_operator is not null
                                                   then ' [' || l_operator || ' ' || l_value || ']' end);
        line(o_body, 'Symbol',   l_symbol || case when l_inst_name is not null then ' - ' || l_inst_name end);
        line(o_body, 'Kurs',     case when l_price is not null
                                      then fmt(l_price) || ' ' || l_currency
                                        || case when l_ewma is not null then ' (EWMA ' || fmt(l_ewma) || ')' end end);
        line(o_body, 'Dauer',    case when l_price is null and l_millis is not null then fmt(l_millis) || ' ms' end);
        line(o_body, 'Aktion',   case when l_symbol is null then a.action_name
                                      || case when a.context_name is not null then ' / ' || a.context_name end end);
        line(o_body, 'Prozess',  case when a.process_id is null then 'kein Prozess'
                                        || case when l_trigger = 'PROCESS_START' then ' (' || a.process_name || ' nicht gestartet)' end
                                      else nvl(l_proc_name, a.process_name) || ' (' || a.process_id || ')'
                                        || case when l_proc_stat is not null then ', Status ' || l_proc_stat end end);
        line(o_body, 'Info',     substr(l_proc_info, 1, 400));
        line(o_body, 'Gruppe',   a.group_name || ', Rule Set ' || a.rule_set_name || ' v' || a.rule_set_version);
        line(o_body, 'Alert-ID', to_char(a.alert_id));
        o_body := o_body || utl_tcp.crlf
               || 'Technischer Monitoring-Demonstrator, keine Anlageberatung. Kursdaten können je nach Anbieter verzögert sein.'
               || utl_tcp.crlf;
    end build_message;

    ------------------------------------------------------------------------
    -- Versand über UTL_SMTP (Text, UTF-8)
    ------------------------------------------------------------------------
    -- Text als UTF-8-Bytes, unabhängig vom Zeichensatz der Datenbank
    function utf8(p_text varchar2) return raw is
    begin
        return utl_raw.convert(utl_raw.cast_to_raw(p_text), 'AMERICAN_AMERICA.AL32UTF8',
                               'AMERICAN_AMERICA.' || nls_charset_name(nls_charset_id('CHAR_CS')));
    end utf8;

    procedure write_text(p_conn in out nocopy utl_smtp.connection, p_text varchar2) is
    begin
        utl_smtp.write_raw_data(p_conn, utf8(p_text));
    end write_text;

    -- Betreff als MIME-Encoded-Words (RFC 2047, UTF-8, Base64). UTL_ENCODE.MIMEHEADER_ENCODE
    -- kennt den Namen UTF-8 nicht (ORA-30205). Teilstücke zu 20 Zeichen halten jedes Wort
    -- unter 75 Zeichen; Folgezeilen beginnen mit einem Leerzeichen.
    function encode_subject(p_subject varchar2) return varchar2 is
        l_result varchar2(4000);
        l_pos    pls_integer := 1;
        l_part   varchar2(100);
    begin
        while l_pos <= nvl(length(p_subject), 0) loop
            l_part := substr(p_subject, l_pos, 20);
            l_result := l_result
                     || case when l_pos > 1 then utl_tcp.crlf || ' ' end
                     || '=?UTF-8?B?'
                     || replace(replace(utl_raw.cast_to_varchar2(utl_encode.base64_encode(utf8(l_part))),
                            chr(13)), chr(10))
                     || '?=';
            l_pos := l_pos + 20;
        end loop;
        return l_result;
    end encode_subject;

    procedure send_smtp(p_from varchar2, p_to varchar2, p_subject varchar2, p_body clob) is
        l_conn   utl_smtp.connection;
        l_offset pls_integer := 1;
        l_len    pls_integer := dbms_lob.getlength(p_body);
    begin
        l_conn := utl_smtp.open_connection(spm_cfg.get_text('MAIL_SMTP_HOST', 'localhost'),
                                           spm_cfg.get_number('MAIL_SMTP_PORT', 25), tx_timeout => 30);
        utl_smtp.helo(l_conn, spm_cfg.get_text('MAIL_HELO_DOMAIN', 'localhost'));
        utl_smtp.mail(l_conn, p_from);
        for r in (select trim(regexp_substr(p_to, '[^,]+', 1, level)) addr from dual
                  connect by regexp_substr(p_to, '[^,]+', 1, level) is not null) loop
            if r.addr is not null then
                utl_smtp.rcpt(l_conn, r.addr);
            end if;
        end loop;

        utl_smtp.open_data(l_conn);
        write_text(l_conn, 'From: ' || p_from || utl_tcp.crlf);
        write_text(l_conn, 'To: ' || p_to || utl_tcp.crlf);
        write_text(l_conn, 'Subject: ' || encode_subject(p_subject) || utl_tcp.crlf);
        write_text(l_conn, 'Date: ' || to_char(systimestamp, 'Dy, DD Mon YYYY HH24:MI:SS TZHTZM', 'NLS_DATE_LANGUAGE=ENGLISH') || utl_tcp.crlf);
        write_text(l_conn, 'MIME-Version: 1.0' || utl_tcp.crlf);
        write_text(l_conn, 'Content-Type: text/plain; charset=UTF-8' || utl_tcp.crlf);
        write_text(l_conn, 'Content-Transfer-Encoding: 8bit' || utl_tcp.crlf || utl_tcp.crlf);
        while l_offset <= l_len loop
            write_text(l_conn, dbms_lob.substr(p_body, 1000, l_offset));
            l_offset := l_offset + 1000;
        end loop;
        utl_smtp.close_data(l_conn);
        utl_smtp.quit(l_conn);
    exception
        when others then
            begin
                utl_smtp.quit(l_conn);
            exception
                when others then null;
            end;
            raise;
    end send_smtp;

    ------------------------------------------------------------------------
    -- Offene Alerts verarbeiten
    ------------------------------------------------------------------------
    function process_pending(p_pid number default null) return number is
        type t_id_tab is table of number;
        cursor c_lock(p_alert_id number) is
            select alert_id, rule_id, alert_severity from lilam_alerts
            where  alert_id = p_alert_id and status = 'PENDING'
            for update skip locked;
        l_group     varchar2(50)   := spm_cfg.get_text('LILAM_GROUP');
        l_handler   varchar2(30)   := spm_cfg.get_text('RULE_HANDLER', 'SPM_ALERT');
        l_transport varchar2(20)   := upper(spm_cfg.get_text('MAIL_TRANSPORT', 'SMTP'));
        l_from      varchar2(400)  := spm_cfg.get_text('MAIL_FROM');
        l_to        varchar2(1000) := spm_cfg.get_text('MAIL_TO');
        l_ids       t_id_tab;
        l_rec       c_lock%rowtype;
        l_found     boolean;
        l_subject   varchar2(400);
        l_body      clob;
        l_err       varchar2(1000);
        l_sent      number := 0;
        l_failed    number := 0;
    begin
        select alert_id bulk collect into l_ids
        from   lilam_alerts
        where  upper(group_name) = upper(l_group) and handler_type = l_handler and status = 'PENDING'
        order  by alert_id;

        if l_ids.count = 0 then
            return 0;
        end if;
        if l_from is null or l_to is null then
            if p_pid is not null then
                lilam.warn(p_pid, l_ids.count || ' Alerts warten: MAIL_FROM oder MAIL_TO ist nicht gesetzt');
            end if;
            return 0;
        end if;

        for i in 1 .. l_ids.count loop
            open c_lock(l_ids(i));
            fetch c_lock into l_rec;
            l_found := c_lock%found;
            close c_lock;

            if l_found then
                begin
                    build_message(l_rec.alert_id, l_subject, l_body);
                    if p_pid is not null then
                        lilam.trace_start(p_pid, C_ACT_MAIL_SEND, l_rec.rule_id);
                    end if;
                    case l_transport
                        when 'SMTP' then send_smtp(l_from, l_to, l_subject, l_body);
                        when 'MOCK' then null;
                        else raise_application_error(C_ERR_NOTIFY, 'Unbekannter MAIL_TRANSPORT: ' || l_transport);
                    end case;
                    if p_pid is not null then
                        lilam.trace_stop(p_pid, C_ACT_MAIL_SEND, l_rec.rule_id);
                    end if;

                    insert into spm_notification (alert_id, rule_id, alert_severity, transport, recipients, subject, body, status)
                    values (l_rec.alert_id, l_rec.rule_id, l_rec.alert_severity, l_transport, l_to, l_subject, l_body, 'SENT');
                    update lilam_alerts set status = 'PROCESSED', processed_at = systimestamp where alert_id = l_rec.alert_id;
                    commit;
                    l_sent := l_sent + 1;
                exception
                    when others then
                        l_err := substr(sqlerrm, 1, 1000);
                        rollback; -- Sperre lösen
                        if p_pid is not null then
                            lilam.trace_stop(p_pid, C_ACT_MAIL_SEND, l_rec.rule_id);
                            lilam.error(p_pid, 'Alert ' || l_rec.alert_id || ' (' || l_rec.rule_id || ') nicht zugestellt: ' || l_err);
                        end if;
                        -- ERROR statt Wiederholung bei jedem Lauf (wie LILAM_MAILER)
                        insert into spm_notification (alert_id, rule_id, alert_severity, transport, recipients, subject, body, status, error_message)
                        values (l_rec.alert_id, l_rec.rule_id, l_rec.alert_severity, l_transport, l_to, l_subject, l_body, 'ERROR', l_err);
                        update lilam_alerts set status = 'ERROR', error_message = l_err, processed_at = systimestamp
                        where  alert_id = l_rec.alert_id;
                        commit;
                        l_failed := l_failed + 1;
                end;
            end if;
        end loop;

        if p_pid is not null then
            lilam.mark_event(p_pid, C_ACT_NOTIFY_RESULT, 'SENT',   l_sent);
            lilam.mark_event(p_pid, C_ACT_NOTIFY_RESULT, 'FAILED', l_failed);
        end if;
        return l_sent;
    end process_pending;

    ------------------------------------------------------------------------
    procedure run_consumer(p_minutes number default null) is
        l_handler varchar2(30) := spm_cfg.get_text('RULE_HANDLER', 'SPM_ALERT');
        l_minutes number       := nvl(p_minutes, spm_cfg.get_number('NOTIFY_RUN_MINUTES', 60));
        l_end     timestamp    := systimestamp + numtodsinterval(l_minutes, 'MINUTE');
        l_pid     number;
        l_sent    number := 0;
        l_msg     varchar2(4000);
        l_status  integer;
        l_wait    number;
        l_errm    varchar2(4000);
    begin
        l_pid := lilam.new_process(
                     p_processName   => spm_cfg.get_text('NOTIFY_PROCESS_NAME', 'SPM_NOTIFY'),
                     p_logLevel      => spm_cfg.get_number('LILAM_LOG_LEVEL', lilam.logLevelInfo),
                     p_daysToKeep    => spm_cfg.get_number('NOTIFY_DAYS_TO_KEEP'),
                     p_tabNameMaster => spm_cfg.get_text('LILAM_TABNAME_MASTER', 'LILAM'),
                     p_baselineScope => spm_cfg.get_text('LILAM_BASELINE_SCOPE'),
                     p_groupName     => spm_cfg.get_text('LILAM_GROUP'));
        dbms_alert.register(l_handler);

        -- Offene Alerts beim Start, nach jedem Signal und nach jeder Minute ohne Signal
        -- (DBMS_ALERT kann Signale zusammenfassen; Alerts aus Zeiten ohne Consumer)
        loop
            l_sent := l_sent + process_pending(l_pid);
            commit;
            l_wait := least(60, (cast(l_end as date) - sysdate) * 86400);
            exit when l_wait <= 0;
            dbms_alert.waitone(l_handler, l_msg, l_status, l_wait);
        end loop;

        dbms_alert.remove(l_handler);
        lilam.close_process(l_pid, 'Zustell-Lauf beendet, ' || l_sent || ' Mails versandt', spm_poll.C_STATUS_SUCCESS);
    exception
        when others then
            l_errm := substr(sqlerrm || ' ' || dbms_utility.format_error_backtrace, 1, 4000);
            begin
                dbms_alert.remove(l_handler);
            exception
                when others then null;
            end;
            begin
                if l_pid is not null then
                    lilam.error(l_pid, 'Zustell-Lauf abgebrochen: ' || l_errm);
                    lilam.close_process(l_pid, substr('Abgebrochen: ' || l_errm, 1, 2000), spm_poll.C_STATUS_FAILED);
                end if;
            exception
                when others then null;
            end;
            raise;
    end run_consumer;

end spm_notify;
/
