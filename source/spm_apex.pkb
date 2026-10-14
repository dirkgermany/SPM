create or replace package body spm_apex as

    function esc(p_text varchar2) return varchar2 is
    begin
        return dbms_xmlgen.convert(p_text);
    end esc;

    function age_text(p_ts timestamp with time zone) return varchar2 is
        l_min number;
    begin
        if p_ts is null then
            return 'nie';
        end if;
        l_min := round((cast(systimestamp as date) - cast(p_ts as date)) * 1440);
        return case
                   when l_min < 1    then 'gerade eben'
                   when l_min < 120  then 'vor ' || l_min || ' min'
                   when l_min < 2880 then 'vor ' || round(l_min / 60) || ' h'
                   else 'vor ' || round(l_min / 1440) || ' Tagen'
               end;
    end age_text;

    -- Kachel: Titel, großer Wert, Zusatz, Farbe des Rands
    function tile(p_title varchar2, p_value varchar2, p_sub varchar2, p_color varchar2) return varchar2 is
    begin
        return '<div style="flex:1 1 180px;min-width:180px;background:#fff;border:1px solid #e5e7eb;'
            || 'border-left:6px solid ' || p_color || ';border-radius:6px;padding:12px 14px;">'
            || '<div style="font-size:12px;color:#6b7280;text-transform:uppercase;letter-spacing:.5px;">' || esc(p_title) || '</div>'
            || '<div style="font-size:24px;font-weight:bold;color:#111827;margin-top:4px;">' || esc(p_value) || '</div>'
            || '<div style="font-size:12px;color:#6b7280;margin-top:2px;">' || esc(p_sub) || '</div></div>';
    end tile;

    function job_text(p_exists varchar2, p_enabled varchar2, p_state varchar2) return varchar2 is
    begin
        return case when p_exists = 'N' then 'nicht angelegt'
                    when p_enabled = 'TRUE' then 'an (' || lower(p_state) || ')'
                    else 'aus' end;
    end job_text;

    function job_color(p_exists varchar2, p_enabled varchar2, p_last varchar2) return varchar2 is
    begin
        return case when p_exists = 'N' or p_enabled <> 'TRUE' then '#9ca3af'
                    when p_last = 'FAILED' then '#e74c3c'
                    else '#27ae60' end;
    end job_color;

    function dashboard_html return clob is
        v        spm_job_status_v%rowtype;
        l_active number;
        l_open   number;
        l_day    number;
        l_html   clob;
        l_fresh  number;
    begin
        select * into v from spm_job_status_v;
        select count(*) into l_active from spm_instrument where is_active = 'Y' and symbol not like 'TST%';
        select count(case when created_at > systimestamp - interval '1' day then 1 end),
               count(case when status = 'PENDING' then 1 end)
        into   l_day, l_open
        from   spm_alert_v;
        l_fresh := round((cast(systimestamp as date) - cast(v.last_success_at as date)) * 1440);

        l_html := '<div style="display:flex;flex-wrap:wrap;gap:12px;">'
            || tile('Letzter erfolgreicher Abruf', age_text(v.last_success_at),
                    nvl(to_char(v.last_success_at, 'DD.MM.YYYY HH24:MI:SS'), 'noch kein Abruf'),
                    case when v.last_success_at is null then '#9ca3af'
                         when l_fresh <= 2 * nvl(to_number(v.configured_interval_minutes), 15) then '#27ae60'
                         else '#f39c12' end)
            || tile('Letzter Lauf', nvl(v.last_run_status, '-'),
                    case when v.last_run_id is not null
                         then v.last_run_trigger || ', ' || v.last_run_stored || ' gespeichert, '
                           || v.last_run_failed || ' fehlerhaft' end,
                    case v.last_run_status when 'SUCCESS' then '#27ae60' when 'PARTIAL' then '#f39c12'
                                           when 'FAILED' then '#e74c3c' else '#9ca3af' end)
            || tile('Beobachtete Symbole', to_char(l_active), 'aktiv in der Watchlist', '#3498db')
            || tile('Alerts (24 h)', to_char(l_day), l_open || ' noch nicht zugestellt',
                    case when l_day > 0 then '#e74c3c' else '#27ae60' end)
            || tile('Abruf-Job', job_text(v.job_exists, v.enabled, v.state),
                    case when v.next_run_date is not null then 'nächster Lauf ' || to_char(v.next_run_date, 'HH24:MI') end,
                    job_color(v.job_exists, v.enabled, v.last_job_status))
            || tile('Watchdog', job_text(v.wd_job_exists, v.wd_enabled, v.wd_state), null,
                    job_color(v.wd_job_exists, v.wd_enabled, v.wd_last_job_status))
            || tile('Zustellung', job_text(v.nt_job_exists, v.nt_enabled, v.nt_state), null,
                    job_color(v.nt_job_exists, v.nt_enabled, v.nt_last_job_status))
            || '</div>';
        return l_html;
    end dashboard_html;

    function num(p_value number) return varchar2 is
    begin
        return to_char(round(p_value, 1), 'FM999999990.0', 'NLS_NUMERIC_CHARACTERS=''.,''');
    end num;

    -- Liniendiagramm der letzten 200 Kurse; Grenzen als gestrichelte Linien
    function chart_svg(p_instrument_id number, p_min number, p_max number, p_currency varchar2) return varchar2 is
        type t_num_tab is table of number;
        type t_ts_tab  is table of timestamp;
        l_price  t_num_tab;
        l_ts     t_ts_tab;
        l_w      constant number := 760;
        l_h      constant number := 260;
        l_pad    constant number := 40;
        l_lo     number;
        l_hi     number;
        l_points varchar2(32767);
        l_svg    varchar2(32767);

        function y(p_value number) return number is
        begin
            return l_h - l_pad - (p_value - l_lo) / nullif(l_hi - l_lo, 0) * (l_h - 2 * l_pad);
        end y;
    begin
        select price, quote_ts_local bulk collect into l_price, l_ts
        from (select price, quote_ts_local from spm_price_v
              where instrument_id = p_instrument_id order by quote_ts_utc desc fetch first 200 rows only)
        order by quote_ts_local;

        if l_price.count < 2 then
            return '<p style="color:#6b7280;">Für ein Diagramm sind mindestens zwei Kurse nötig.</p>';
        end if;

        l_lo := l_price(1);
        l_hi := l_price(1);
        for i in 2 .. l_price.count loop
            l_lo := least(l_lo, l_price(i));
            l_hi := greatest(l_hi, l_price(i));
        end loop;
        l_lo := least(l_lo, nvl(p_min, l_lo));
        l_hi := greatest(l_hi, nvl(p_max, l_hi));
        if l_hi = l_lo then
            l_hi := l_hi + 1;
            l_lo := l_lo - 1;
        end if;

        for i in 1 .. l_price.count loop
            l_points := l_points || num(l_pad + (i - 1) / (l_price.count - 1) * (l_w - 2 * l_pad)) || ','
                     || num(y(l_price(i))) || ' ';
        end loop;

        l_svg := '<svg viewBox="0 0 ' || l_w || ' ' || l_h || '" style="width:100%;max-width:' || l_w
              || 'px;height:auto;background:#fff;border:1px solid #e5e7eb;border-radius:6px;" '
              || 'xmlns="http://www.w3.org/2000/svg" font-family="Arial" font-size="11">';
        -- Achsenbeschriftung
        l_svg := l_svg
              || '<text x="4" y="' || num(y(l_hi) + 4) || '" fill="#6b7280">' || esc(to_char(l_hi, 'FM999999990D00')) || '</text>'
              || '<text x="4" y="' || num(y(l_lo) + 4) || '" fill="#6b7280">' || esc(to_char(l_lo, 'FM999999990D00')) || '</text>'
              || '<text x="' || l_pad || '" y="' || (l_h - 10) || '" fill="#6b7280">'
              || esc(to_char(l_ts(1), 'DD.MM. HH24:MI')) || '</text>'
              || '<text x="' || (l_w - l_pad) || '" y="' || (l_h - 10) || '" fill="#6b7280" text-anchor="end">'
              || esc(to_char(l_ts(l_ts.count), 'DD.MM. HH24:MI')) || '</text>';
        -- Grenzen
        if p_max is not null then
            l_svg := l_svg || '<line x1="' || l_pad || '" x2="' || (l_w - l_pad) || '" y1="' || num(y(p_max))
                  || '" y2="' || num(y(p_max)) || '" stroke="#e74c3c" stroke-dasharray="6 4"/>'
                  || '<text x="' || (l_w - l_pad) || '" y="' || num(y(p_max) - 4) || '" fill="#e74c3c" text-anchor="end">Obergrenze '
                  || esc(to_char(p_max, 'FM999999990D00') || ' ' || p_currency) || '</text>';
        end if;
        if p_min is not null then
            l_svg := l_svg || '<line x1="' || l_pad || '" x2="' || (l_w - l_pad) || '" y1="' || num(y(p_min))
                  || '" y2="' || num(y(p_min)) || '" stroke="#3498db" stroke-dasharray="6 4"/>'
                  || '<text x="' || (l_w - l_pad) || '" y="' || num(y(p_min) + 14) || '" fill="#3498db" text-anchor="end">Untergrenze '
                  || esc(to_char(p_min, 'FM999999990D00') || ' ' || p_currency) || '</text>';
        end if;
        l_svg := l_svg || '<polyline fill="none" stroke="#1f2937" stroke-width="2" points="' || rtrim(l_points) || '"/>'
              || '<circle cx="' || num(l_w - l_pad) || '" cy="' || num(y(l_price(l_price.count)))
              || '" r="4" fill="#1f2937"/></svg>';
        return l_svg;
    end chart_svg;

    function instrument_html(p_symbol varchar2) return clob is
        w spm_watchlist_v%rowtype;
        r spm_rule_v%rowtype;
    begin
        begin
            select * into w from spm_watchlist_v where symbol = p_symbol;
        exception
            when no_data_found then
                return '<p>Symbol nicht gefunden.</p>';
        end;
        begin
            select * into r from spm_rule_v where symbol = p_symbol;
        exception
            when no_data_found then null;
        end;

        return '<div style="display:flex;flex-wrap:wrap;gap:12px;margin-bottom:12px;">'
            || tile(w.symbol, case when w.last_price is not null
                                   then to_char(w.last_price, 'FM999G999G990D00') || ' ' || w.currency else '-' end,
                    nvl(w.instrument_name, w.provider_symbol) || case when w.exchange is not null then ', ' || w.exchange end,
                    case when w.is_active = 'Y' then '#3498db' else '#9ca3af' end)
            || tile('Letzter Quote', nvl(to_char(cast(from_tz(w.last_quote_utc, 'UTC') at time zone 'Europe/Berlin' as timestamp),
                                                 'DD.MM.YYYY HH24:MI'), '-'),
                    'Zeit laut Provider (MEZ/MESZ)', '#3498db')
            || tile('Letzter Abruf', nvl(w.last_fetch_status, '-'), age_text(w.last_fetch_at),
                    case when w.last_fetch_status in ('OK', 'DUPLICATE') then '#27ae60'
                         when w.last_fetch_status is null then '#9ca3af' else '#e74c3c' end)
            || tile('Kurse gespeichert', to_char(w.price_count), 'Provider ' || w.provider_code, '#3498db')
            || '</div>'
            || case when w.last_fetch_message is not null
                    then '<p style="color:#b45309;">' || esc(w.last_fetch_message) || '</p>' end
            || chart_svg(w.instrument_id, r.val_min, r.val_max, w.currency);
    end instrument_html;

    function fmt_num(p_value number) return varchar2 is
        l_dec varchar2(1) := substr(to_char(0.5, 'FM0D0'), 2, 1);  -- Dezimalzeichen der Sitzung
    begin
        if p_value is null then
            return null;
        end if;
        -- FM entfernt Nullen hinter dem Komma; bei ganzen Zahlen bleibt nur das Komma übrig
        return rtrim(to_char(p_value, 'FM999999999999990D9999999999'), l_dec);
    end fmt_num;

    function is_admin(p_user varchar2) return boolean is
        l_list varchar2(4000) := upper(replace(spm_cfg.get_text('APEX_ADMIN_USERS'), ' '));
    begin
        return l_list is null or instr(',' || l_list || ',', ',' || upper(p_user) || ',') > 0;
    end is_admin;

    function job_status_html return clob is
        v      spm_job_status_v%rowtype;
        l_html clob;

        function row(p_name varchar2, p_job varchar2, p_exists varchar2, p_enabled varchar2, p_state varchar2,
                     p_next timestamp with time zone, p_last varchar2, p_error number, p_fail number) return varchar2 is
        begin
            return '<tr><td style="padding:6px 10px;font-weight:bold;">' || esc(p_name) || '</td>'
                || '<td style="padding:6px 10px;">' || esc(p_job) || '</td>'
                || '<td style="padding:6px 10px;color:' || job_color(p_exists, p_enabled, p_last) || ';font-weight:bold;">'
                || esc(job_text(p_exists, p_enabled, p_state)) || '</td>'
                || '<td style="padding:6px 10px;">' || esc(to_char(p_next, 'DD.MM. HH24:MI')) || '</td>'
                || '<td style="padding:6px 10px;">' || esc(p_last || case when p_error > 0 then ' (ORA-' || p_error || ')' end) || '</td>'
                || '<td style="padding:6px 10px;text-align:right;">' || esc(to_char(p_fail)) || '</td></tr>';
        end row;
    begin
        select * into v from spm_job_status_v;
        l_html := '<table style="width:100%;border-collapse:collapse;font-size:14px;">'
            || '<tr style="background:#f3f4f6;"><th style="text-align:left;padding:6px 10px;">Aufgabe</th>'
            || '<th style="text-align:left;padding:6px 10px;">Job</th><th style="text-align:left;padding:6px 10px;">Zustand</th>'
            || '<th style="text-align:left;padding:6px 10px;">Nächster Lauf</th><th style="text-align:left;padding:6px 10px;">Letzter Lauf</th>'
            || '<th style="text-align:right;padding:6px 10px;">Fehler</th></tr>'
            || row('Kursabruf', v.job_name, v.job_exists, v.enabled, v.state, v.next_run_date,
                   v.last_job_status, v.last_job_error, v.failure_count)
            || row('Watchdog', v.wd_job_name, v.wd_job_exists, v.wd_enabled, v.wd_state, v.wd_next_run_date,
                   v.wd_last_job_status, v.wd_last_job_error, v.wd_failure_count)
            || row('Zustellung', v.nt_job_name, v.nt_job_exists, v.nt_enabled, v.nt_state, v.nt_next_run_date,
                   v.nt_last_job_status, v.nt_last_job_error, v.nt_failure_count)
            || '</table>'
            || '<p style="margin-top:8px;font-size:12px;color:#6b7280;">Abrufintervall '
            || esc(v.configured_interval_minutes) || ' min. Den Watchdog nur zusammen mit dem Kursabruf einschalten.</p>';
        return l_html;
    end job_status_html;

    function alert_mail_html(p_alert_id number) return clob is
        l_subject varchar2(400);
        l_body    clob;
        l_html    clob;
    begin
        if p_alert_id is null then
            return null;
        end if;
        spm_notify.build_message(p_alert_id, l_subject, l_body, l_html);
        return '<p style="font-size:13px;color:#6b7280;">Betreff: <b>' || esc(l_subject) || '</b></p>' || l_html;
    end alert_mail_html;

    function run_poll_now return varchar2 is
        l_run spm_run%rowtype;
        l_id  number;
    begin
        l_id := spm_poll.run('APEX');
        select * into l_run from spm_run where run_id = l_id;
        return 'Abruflauf ' || l_id || ': ' || l_run.status
            || case when l_run.status <> 'SKIPPED'
                    then ' (' || l_run.cnt_stored || ' gespeichert, ' || l_run.cnt_failed || ' fehlerhaft)'
                    else ' - ein anderer Lauf ist aktiv' end;
    end run_poll_now;

    procedure set_job(p_kind varchar2, p_enabled boolean) is
        l_name varchar2(128);
        l_count pls_integer;
    begin
        l_name := case upper(p_kind)
                      when 'POLL'     then spm_job.job_name
                      when 'WATCHDOG' then spm_job.watchdog_job_name
                      when 'NOTIFY'   then spm_job.notify_job_name
                  end;
        if l_name is null then
            raise_application_error(spm_job.C_ERR_JOB, 'Unbekannter Job: ' || p_kind);
        end if;

        if p_enabled then
            select count(*) into l_count from user_scheduler_jobs where job_name = l_name;
            if l_count = 0 then
                case upper(p_kind)
                    when 'POLL'     then spm_job.create_job;
                    when 'WATCHDOG' then spm_job.create_watchdog_job;
                    when 'NOTIFY'   then spm_job.create_notify_job;
                end case;
            end if;
            spm_job.enable_job(l_name);
        else
            spm_job.disable_job(l_name);
        end if;
    end set_job;

    function publish_rules return varchar2 is
        l_before number;
        l_after  number;
    begin
        select max(version) into l_before from lilam_rules
        where  upper(group_name) = upper(spm_cfg.get_text('LILAM_GROUP')) and is_active = 1;
        l_after := spm_rules.publish(sys_context('APEX$SESSION', 'APP_USER'));
        return case when l_after = l_before then 'Rule Set unverändert (Version ' || l_after || ')'
                    else 'Rule Set Version ' || l_after || ' aktiviert' end;
    end publish_rules;

end spm_apex;
/
