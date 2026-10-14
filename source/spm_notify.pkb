create or replace package body spm_notify as

    C_ACT_MAIL_SEND     constant varchar2(30) := 'MAIL_SEND';      -- Trace je Mail (Context Regel-ID)
    C_ACT_NOTIFY_RESULT constant varchar2(30) := 'NOTIFY_RESULT';  -- Event mit Anzahl (SENT, FAILED)
    C_ERR_NOTIFY        constant pls_integer  := -20331;

    -- Farben der Mail
    C_RED    constant varchar2(7) := '#e74c3c';
    C_DARK   constant varchar2(7) := '#c0392b';
    C_ORANGE constant varchar2(7) := '#f39c12';
    C_BLUE   constant varchar2(7) := '#3498db';
    C_GREEN  constant varchar2(7) := '#27ae60';
    C_VIOLET constant varchar2(7) := '#8e44ad';
    C_GREY   constant varchar2(7) := '#7f8c8d';

    -- Alles, was eine Nachricht zu einem Alert braucht
    type t_msg is record (
        a          lilam_alerts%rowtype,
        rule_comment  varchar2(400),
        rule_operator varchar2(100),
        rule_value    varchar2(100),
        rule_trigger  varchar2(30),
        price      number,
        ewma       number,
        millis     number,
        inst_name  spm_instrument.instrument_name%type,
        currency   spm_instrument.currency%type,
        proc_name  varchar2(100),
        proc_stat  number,
        proc_info  varchar2(2000),
        symbol     varchar2(100)
    );

    function fmt(p_value number) return varchar2 is
    begin
        return to_char(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS='',.''');
    end fmt;

    function fmt2(p_value number) return varchar2 is
    begin
        return trim(to_char(p_value, '999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.'''));
    end fmt2;

    -- Sekunden lesbar: 45 s, 15 min, 2 h 30 min
    function fmt_seconds(p_seconds number) return varchar2 is
    begin
        return case
                   when p_seconds < 120  then fmt(p_seconds) || ' s'
                   when p_seconds < 7200 then fmt(round(p_seconds / 60)) || ' min'
                   else fmt(trunc(p_seconds / 3600)) || ' h'
                     || case when mod(round(p_seconds / 60), 60) > 0 then ' ' || mod(round(p_seconds / 60), 60) || ' min' end
               end;
    end fmt_seconds;

    function esc(p_text varchar2) return varchar2 is
    begin
        return dbms_xmlgen.convert(p_text);
    end esc;

    function severity_color(p_severity varchar2) return varchar2 is
    begin
        return case upper(p_severity)
                   when 'CRITICAL' then C_DARK
                   when 'ERROR'    then C_RED
                   when 'WARN'     then C_ORANGE
                   when 'INFO'     then C_BLUE
                   else C_GREY
               end;
    end severity_color;

    -- Regel in Worten, z. B. "Obergrenze 120 EUR"
    function rule_text(m t_msg) return varchar2 is
        l_pct number := spm_prov.parse_decimal(regexp_substr(m.rule_value, '[^|]+'));
    begin
        return case m.rule_operator
                   when 'VAL_MAX' then 'Obergrenze ' || fmt(spm_prov.parse_decimal(m.rule_value)) || ' ' || m.currency
                   when 'VAL_MIN' then 'Untergrenze ' || fmt(spm_prov.parse_decimal(m.rule_value)) || ' ' || m.currency
                   when 'VAL_EWMA_DEVIATION_PCT_UP'   then 'mehr als ' || fmt(l_pct) || ' % über dem gleitenden Mittel (EWMA)'
                   when 'VAL_EWMA_DEVIATION_PCT_DOWN' then 'mehr als ' || fmt(l_pct) || ' % unter dem gleitenden Mittel (EWMA)'
                   when 'TIME_MAX_SILENCE_SECONDS'    then 'kein Signal seit mehr als ' || fmt_seconds(spm_prov.parse_decimal(m.rule_value))
                   when 'STATUS_EQUALS'               then 'Prozessstatus = ' || m.rule_value
                   when 'TIME_MAX_DURATION_MS'        then 'Dauer über ' || m.rule_value || ' ms'
                   when 'TIME_MAX_RUNTIME_EXCEEDED'   then 'Laufzeit über ' || fmt_seconds(spm_prov.parse_decimal(m.rule_value) / 1000)
                   else m.rule_operator || case when m.rule_value is not null then ' ' || m.rule_value end
               end;
    end rule_text;

    function process_text(m t_msg) return varchar2 is
    begin
        return case when m.a.process_id is null then 'kein Prozess'
                        || case when m.rule_trigger = 'PROCESS_START' then ' (' || m.a.process_name || ' nicht gestartet)' end
                    else nvl(m.proc_name, m.a.process_name) || ' (' || m.a.process_id || ')'
                        || case when m.proc_stat is not null then ', Status ' || m.proc_stat end
               end;
    end process_text;

    -- Abweichung des Kurses vom EWMA in Prozent
    function deviation_pct(m t_msg) return number is
    begin
        return case when m.price is not null and m.ewma is not null and m.ewma <> 0
                    then round((m.price - m.ewma) / abs(m.ewma) * 100, 2) end;
    end deviation_pct;

    ------------------------------------------------------------------------
    -- Daten zum Alert
    ------------------------------------------------------------------------
    function load_msg(p_alert_id number) return t_msg is
        m t_msg;
    begin
        select * into m.a from lilam_alerts where alert_id = p_alert_id;

        -- Regel aus dem Rule Set, mit dem der Alert ausgelöst wurde. JSON_TABLE statt mehrerer
        -- JSON_VALUE mit PASSING: diese Kombination lieferte durchweg NULL (Testbericht).
        begin
            select jt.cmt, jt.op, jt.val, jt.trg
            into   m.rule_comment, m.rule_operator, m.rule_value, m.rule_trigger
            from   lilam_rules r,
                   json_table(r.rule_set, '$.rules[*]' columns (
                       id  varchar2(50)  path '$.id',
                       cmt varchar2(400) path '$."_comment"',
                       op  varchar2(100) path '$.condition.operator',
                       val varchar2(100) path '$.condition.value',
                       trg varchar2(30)  path '$.trigger_type')) jt
            where  upper(r.group_name) = upper(m.a.group_name)
            and    r.set_name = m.a.rule_set_name and r.version = m.a.rule_set_version
            and    jt.id = m.a.rule_id;
        exception
            when no_data_found or too_many_rows then null;
        end;

        -- Messwert und EWMA der auslösenden Messung (nicht bei Schweige-Alerts ohne Prozess)
        if m.a.process_id is not null and m.a.monitor_table_name is not null and m.a.action_count is not null then
            begin
                execute immediate
                    'select max(used_value), max(used_value_ewma), max(used_millis) from '
                 || dbms_assert.simple_sql_name(m.a.monitor_table_name)
                 || ' where process_id = :1 and action = :2'
                 || ' and (context = :3 or (context is null and :4 is null)) and action_count = :5'
                    into m.price, m.ewma, m.millis
                    using m.a.process_id, m.a.action_name, m.a.context_name, m.a.context_name, m.a.action_count;
            exception
                when others then null; -- Tabelle nicht lesbar: Mail ohne Messwert
            end;
        end if;

        if m.a.process_id is not null and m.a.master_table_name is not null then
            begin
                execute immediate
                    'select process_name, status, info from ' || dbms_assert.simple_sql_name(m.a.master_table_name)
                 || ' where id = :1'
                    into m.proc_name, m.proc_stat, m.proc_info using m.a.process_id;
            exception
                when others then null;
            end;
        end if;

        if m.a.action_name = spm_poll.C_ACT_SHARE_PRICE and m.a.context_name is not null then
            m.symbol := m.a.context_name;
            begin
                select instrument_name, currency into m.inst_name, m.currency
                from   spm_instrument where symbol = m.a.context_name;
            exception
                when no_data_found then null;
            end;
        end if;
        return m;
    end load_msg;

    ------------------------------------------------------------------------
    -- Text
    ------------------------------------------------------------------------
    procedure line(p_body in out nocopy clob, p_label varchar2, p_value varchar2) is
    begin
        if p_value is not null then
            p_body := p_body || rpad(p_label || ':', 12) || p_value || utl_tcp.crlf;
        end if;
    end line;

    function build_text(m t_msg) return clob is
        l_body clob;
    begin
        l_body := 'SPM-Alert ' || m.a.rule_id || ' (' || m.a.alert_severity || ')' || utl_tcp.crlf || utl_tcp.crlf;
        line(l_body, 'Zeit',     to_char(m.a.created_at, 'DD.MM.YYYY HH24:MI:SS'));
        line(l_body, 'Regel',    m.rule_comment || case when m.rule_operator is not null
                                                   then ' [' || m.rule_operator || ' ' || m.rule_value || ']' end);
        line(l_body, 'Symbol',   m.symbol || case when m.inst_name is not null then ' - ' || m.inst_name end);
        line(l_body, 'Kurs',     case when m.price is not null
                                      then fmt(m.price) || ' ' || m.currency
                                        || case when m.ewma is not null then ' (EWMA ' || fmt(m.ewma) || ')' end end);
        line(l_body, 'Dauer',    case when m.price is null and m.millis is not null then fmt(m.millis) || ' ms' end);
        line(l_body, 'Aktion',   case when m.symbol is null then m.a.action_name
                                      || case when m.a.context_name is not null then ' / ' || m.a.context_name end end);
        line(l_body, 'Prozess',  process_text(m));
        line(l_body, 'Info',     substr(m.proc_info, 1, 400));
        line(l_body, 'Gruppe',   m.a.group_name || ', Rule Set ' || m.a.rule_set_name || ' v' || m.a.rule_set_version);
        line(l_body, 'Alert-ID', to_char(m.a.alert_id));
        return l_body || utl_tcp.crlf
            || 'Technischer Monitoring-Demonstrator, keine Anlageberatung. Kursdaten können je nach Anbieter verzögert sein.'
            || utl_tcp.crlf;
    end build_text;

    ------------------------------------------------------------------------
    -- HTML (Inline-Styles; Mailprogramme ignorieren Stylesheets oft)
    ------------------------------------------------------------------------
    function row(p_label varchar2, p_value varchar2) return varchar2 is
    begin
        if p_value is null then
            return null;
        end if;
        return '<tr><td style="width:150px;padding:8px 12px;border-bottom:1px solid #e5e7eb;color:#6b7280;">'
            || esc(p_label) || '</td><td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;">'
            || esc(p_value) || '</td></tr>' || utl_tcp.crlf;
    end row;

    -- Hervorgehobener Block: Kurs mit Grenze bzw. Abweichung, oder Schweigen
    function highlight(m t_msg) return varchar2 is
        l_limit  number;
        l_dev    number := deviation_pct(m);
        l_color  varchar2(7);
        l_big    varchar2(200);
        l_small  varchar2(400);
    begin
        if m.rule_operator = 'TIME_MAX_SILENCE_SECONDS' then
            l_color := C_VIOLET;
            l_big   := '&#9208; Kein Signal';
            l_small := 'seit mehr als ' || fmt_seconds(spm_prov.parse_decimal(m.rule_value))
                    || case when m.symbol is not null then ' kein neuer Kurs für ' || m.symbol
                            when m.rule_trigger = 'PROCESS_START' then ' kein Start von ' || m.a.process_name
                            else ' keine Meldung von ' || m.a.action_name end;
            return '<div style="margin:16px 0;padding:16px;border-left:6px solid ' || l_color || ';background:#f5eef8;">'
                || '<div style="font-size:22px;font-weight:bold;color:' || l_color || ';">' || l_big || '</div>'
                || '<div style="margin-top:4px;color:#374151;">' || esc(l_small) || '</div></div>' || utl_tcp.crlf;
        end if;

        if m.price is null then
            return null;
        end if;

        if m.rule_operator in ('VAL_MAX', 'VAL_MIN') then
            l_limit := spm_prov.parse_decimal(m.rule_value);
            l_color := severity_color(m.a.alert_severity);
            l_small := case m.rule_operator when 'VAL_MAX' then '&#9650; über der Obergrenze ' else '&#9660; unter der Untergrenze ' end
                    || esc(fmt2(l_limit) || ' ' || m.currency)
                    || case when l_limit <> 0 then ' (' || esc(fmt2(abs(m.price - l_limit) / abs(l_limit) * 100)) || ' %)' end;
        else
            -- Abweichung vom EWMA: bis 1 % grün, bis 3 % orange, darüber rot
            l_color := case when l_dev is null then severity_color(m.a.alert_severity)
                            when abs(l_dev) < 1 then C_GREEN
                            when abs(l_dev) < 3 then C_ORANGE
                            else C_RED end;
            l_small := case when l_dev is not null
                            then case when l_dev >= 0 then '&#9650; ' else '&#9660; ' end
                              || esc(fmt2(abs(l_dev)) || ' % ' || case when l_dev >= 0 then 'über' else 'unter' end
                              || ' dem gleitenden Mittel ' || fmt2(m.ewma) || ' ' || m.currency) end;
        end if;

        return '<div style="margin:16px 0;padding:16px;border-left:6px solid ' || l_color || ';background:#f9fafb;">'
            || '<div style="font-size:13px;color:#6b7280;">' || esc(m.symbol || case when m.inst_name is not null then ' · ' || m.inst_name end) || '</div>'
            || '<div style="font-size:28px;font-weight:bold;color:' || l_color || ';">'
            || esc(fmt2(m.price) || ' ' || m.currency) || '</div>'
            || '<div style="margin-top:4px;color:' || l_color || ';font-weight:bold;">' || l_small || '</div></div>' || utl_tcp.crlf;
    end highlight;

    function build_html(m t_msg) return clob is
        l_color varchar2(7) := severity_color(m.a.alert_severity);
        l_html  clob;
    begin
        l_html := '<!DOCTYPE html><html><head><meta charset="UTF-8"></head>' || utl_tcp.crlf
               || '<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">' || utl_tcp.crlf
               || '<div style="max-width:640px;margin:0 auto;background:#ffffff;">' || utl_tcp.crlf
               || '<div style="background:' || l_color || ';color:#ffffff;padding:16px 20px;">'
               || '<div style="font-size:12px;letter-spacing:1px;opacity:0.9;">SPM &middot; STOCK PRICE MONITORING</div>'
               || '<div style="font-size:20px;font-weight:bold;margin-top:4px;">' || esc(m.a.alert_severity) || ': '
               || esc(nvl(m.rule_comment, m.a.rule_id)) || '</div>'
               || '<div style="font-size:13px;margin-top:4px;">Regel ' || esc(m.a.rule_id) || ' &middot; '
               || esc(to_char(m.a.created_at, 'DD.MM.YYYY HH24:MI:SS')) || '</div></div>' || utl_tcp.crlf
               || '<div style="padding:4px 20px 20px 20px;">' || utl_tcp.crlf
               || highlight(m)
               || '<table style="width:100%;border-collapse:collapse;font-size:14px;">' || utl_tcp.crlf
               || row('Regel', rule_text(m))
               || row('Symbol', m.symbol || case when m.inst_name is not null then ' - ' || m.inst_name end)
               || row('Kurs', case when m.price is not null then fmt2(m.price) || ' ' || m.currency end)
               || row('Gleitendes Mittel', case when m.ewma is not null then fmt2(m.ewma) || ' ' || m.currency end)
               || row('Dauer', case when m.price is null and m.millis is not null then fmt(m.millis) || ' ms' end)
               || row('Aktion', case when m.symbol is null then m.a.action_name
                                     || case when m.a.context_name is not null then ' / ' || m.a.context_name end end)
               || row('Prozess', process_text(m))
               || row('Info', substr(m.proc_info, 1, 400))
               || row('Gruppe', m.a.group_name || ', Rule Set ' || m.a.rule_set_name || ' v' || m.a.rule_set_version)
               || row('Alert-ID', to_char(m.a.alert_id))
               || '</table>' || utl_tcp.crlf
               || '<p style="margin-top:20px;font-size:11px;color:#9ca3af;">Technischer Monitoring-Demonstrator, '
               || 'keine Anlageberatung. Kursdaten können je nach Anbieter verzögert sein. '
               || 'Überwacht mit LILAM.</p>' || utl_tcp.crlf
               || '</div></div></body></html>' || utl_tcp.crlf;
        return l_html;
    end build_html;

    procedure build_message(p_alert_id number, o_subject out varchar2, o_body out clob, o_html out clob) is
        m t_msg := load_msg(p_alert_id);
    begin
        o_subject := substr(spm_cfg.get_text('MAIL_SUBJECT_PREFIX', '[SPM]') || ' ' || m.a.alert_severity || ' '
                         || m.a.rule_id || ': ' || nvl(m.rule_comment, m.a.action_name), 1, 400);
        o_body := build_text(m);
        o_html := build_html(m);
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

    procedure write_clob(p_conn in out nocopy utl_smtp.connection, p_text clob) is
        l_offset pls_integer := 1;
        l_len    pls_integer := nvl(dbms_lob.getlength(p_text), 0);
    begin
        while l_offset <= l_len loop
            write_text(p_conn, dbms_lob.substr(p_text, 1000, l_offset));
            l_offset := l_offset + 1000;
        end loop;
    end write_clob;

    -- multipart/alternative: Text für Mailprogramme ohne HTML, danach HTML
    procedure send_smtp(p_from varchar2, p_to varchar2, p_subject varchar2, p_body clob, p_html clob) is
        l_conn     utl_smtp.connection;
        l_boundary varchar2(60) := 'SPM-' || rawtohex(sys_guid());
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
        write_text(l_conn, 'Content-Type: multipart/alternative; boundary="' || l_boundary || '"' || utl_tcp.crlf || utl_tcp.crlf);

        write_text(l_conn, '--' || l_boundary || utl_tcp.crlf);
        write_text(l_conn, 'Content-Type: text/plain; charset=UTF-8' || utl_tcp.crlf);
        write_text(l_conn, 'Content-Transfer-Encoding: 8bit' || utl_tcp.crlf || utl_tcp.crlf);
        write_clob(l_conn, p_body);
        write_text(l_conn, utl_tcp.crlf || '--' || l_boundary || utl_tcp.crlf);
        write_text(l_conn, 'Content-Type: text/html; charset=UTF-8' || utl_tcp.crlf);
        write_text(l_conn, 'Content-Transfer-Encoding: 8bit' || utl_tcp.crlf || utl_tcp.crlf);
        write_clob(l_conn, p_html);
        write_text(l_conn, utl_tcp.crlf || '--' || l_boundary || '--' || utl_tcp.crlf);
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
        l_html      clob;
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
                    build_message(l_rec.alert_id, l_subject, l_body, l_html);
                    if p_pid is not null then
                        lilam.trace_start(p_pid, C_ACT_MAIL_SEND, l_rec.rule_id);
                    end if;
                    case l_transport
                        when 'SMTP' then send_smtp(l_from, l_to, l_subject, l_body, l_html);
                        when 'MOCK' then null;
                        else raise_application_error(C_ERR_NOTIFY, 'Unbekannter MAIL_TRANSPORT: ' || l_transport);
                    end case;
                    if p_pid is not null then
                        lilam.trace_stop(p_pid, C_ACT_MAIL_SEND, l_rec.rule_id);
                    end if;

                    insert into spm_notification (alert_id, rule_id, alert_severity, transport, recipients, subject, body, body_html, status)
                    values (l_rec.alert_id, l_rec.rule_id, l_rec.alert_severity, l_transport, l_to, l_subject, l_body, l_html, 'SENT');
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
                        insert into spm_notification (alert_id, rule_id, alert_severity, transport, recipients, subject, body, body_html, status, error_message)
                        values (l_rec.alert_id, l_rec.rule_id, l_rec.alert_severity, l_transport, l_to, l_subject, l_body, l_html, 'ERROR', l_err);
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
