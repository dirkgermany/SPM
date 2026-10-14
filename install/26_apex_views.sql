-- =============================================================================
-- SPM: Sichten für die APEX-Anwendung (Seiten lesen nur diese Sichten)
-- LILAM-Tabellen mit Standardpräfix LILAM (SPM_CONFIG.LILAM_TABNAME_MASTER).
-- =============================================================================

-- Watchlist mit letztem Kurs und Abrufstatus
create or replace view spm_watchlist_v as
select i.instrument_id,
       i.symbol,
       i.instrument_name,
       i.provider_code,
       i.provider_symbol,
       i.exchange,
       i.currency,
       i.is_active,
       p.price          last_price,
       p.quote_ts_utc   last_quote_utc,
       i.last_fetch_at,
       i.last_fetch_status,
       i.last_fetch_message,
       (select count(*) from spm_price x where x.instrument_id = i.instrument_id) price_count,
       case when r.instrument_id is not null and r.is_active = 'Y' then 'Y' else 'N' end has_rules
from   spm_instrument i
left   join lateral (
           select price, quote_ts_utc from spm_price x
           where  x.instrument_id = i.instrument_id
           order  by quote_ts_utc desc fetch first 1 row only) p on 1 = 1
left   join spm_rule r on r.instrument_id = i.instrument_id
where  i.symbol not like 'TST%';

-- Kurshistorie
create or replace view spm_price_v as
select p.price_id,
       i.symbol,
       i.instrument_id,
       p.price,
       p.currency,
       p.quote_ts_utc,
       cast(from_tz(p.quote_ts_utc, 'UTC') at time zone 'Europe/Berlin' as timestamp) quote_ts_local,
       p.received_at,
       p.run_id,
       p.provider_code
from   spm_price p
join   spm_instrument i on i.instrument_id = p.instrument_id;

-- Regelkonfiguration je Instrument (auch ohne Regel, damit sie angelegt werden kann)
create or replace view spm_rule_v as
select i.instrument_id,
       i.symbol,
       i.instrument_name,
       i.currency,
       i.is_active          instrument_active,
       r.val_min,
       r.val_max,
       r.ewma_pct_up,
       r.ewma_pct_down,
       r.ewma_warmup,
       r.ewma_alpha,
       r.silence_seconds,
       r.silence_windows,
       r.silence_time_zone,
       r.severity_limit,
       r.severity_ewma,
       r.severity_silence,
       r.throttle_seconds,
       nvl(r.is_active, 'N') rule_active,
       r.updated_at
from   spm_instrument i
left   join spm_rule r on r.instrument_id = i.instrument_id
where  i.symbol not like 'TST%';

-- Alerts der SPM-Gruppe mit Messwert und letzter Zustellung
create or replace view spm_alert_v as
select a.alert_id,
       a.created_at,
       a.rule_id,
       initcap(a.alert_severity)          alert_severity,
       a.action_name,
       a.context_name                      symbol,
       a.process_id,
       a.process_name,
       a.status,
       a.processed_at,
       a.error_message,
       a.rule_set_name,
       a.rule_set_version,
       m.used_value                        measured_value,
       m.used_value_ewma                   measured_ewma,
       i.currency,
       n.status                            mail_status,
       n.created_at                        mail_at,
       n.error_message                     mail_error
from   lilam_alerts a
left   join lateral (
           select max(x.used_value) used_value, max(x.used_value_ewma) used_value_ewma
           from   lilam_mon x
           where  a.process_id is not null
           and    x.process_id = a.process_id and x.action = a.action_name
           and    (x.context = a.context_name or (x.context is null and a.context_name is null))
           and    x.action_count = a.action_count) m on 1 = 1
left   join spm_instrument i on i.symbol = a.context_name and a.action_name = 'SHARE_PRICE'
left   join lateral (
           select status, created_at, error_message from spm_notification y
           where  y.alert_id = a.alert_id
           order  by y.notification_id desc fetch first 1 row only) n on 1 = 1
where  upper(a.group_name) = upper((select param_value from spm_config where param_name = 'LILAM_GROUP'));

-- Abrufläufe mit LILAM-Prozess
create or replace view spm_run_v as
select r.run_id,
       r.trigger_type,
       r.symbol_filter,
       r.started_at,
       r.ended_at,
       round((cast(r.ended_at as date) - cast(r.started_at as date)) * 86400) duration_s,
       r.status,
       r.cnt_active,
       r.cnt_requested,
       r.cnt_fetched,
       r.cnt_failed,
       r.cnt_stored,
       r.cnt_duplicate,
       r.message,
       r.lilam_process_id,
       p.status   lilam_status,
       p.info     lilam_info
from   spm_run r
left   join lilam_proc p on p.id = r.lilam_process_id
where  r.trigger_type <> 'TEST'
and    nvl(r.symbol_filter, '-') not like 'TST%';   -- Job-Tests laufen mit Symbolfilter TST*

-- LILAM-Prozesse von SPM (Abruf, Watchdog, Zustellung), ohne Testläufe
create or replace view spm_process_v as
select p.id            process_id,
       p.process_name,
       p.process_start,
       p.process_end,
       round((cast(nvl(p.process_end, systimestamp) as date) - cast(p.process_start as date)) * 86400) duration_s,
       p.status,
       p.steps_todo,
       p.steps_done,
       p.info,
       (select count(*) from lilam_log l where l.process_id = p.id and l.log_level <= 2 and l.no >= 0) problems
from   lilam_proc p
where  p.process_name in (select param_value from spm_config
                          where param_name in ('POLL_PROCESS_NAME', 'WATCHDOG_PROCESS_NAME', 'NOTIFY_PROCESS_NAME'))
and    not exists (select 1 from spm_run r where r.lilam_process_id = p.id and r.trigger_type = 'TEST');

-- Warnungen und Fehler aus den LILAM-Logs der SPM-Prozesse
create or replace view spm_problem_v as
select l.process_id,
       p.process_name,
       l.session_time,
       l.log_level_c   log_level,
       l.info
from   lilam_log l
join   lilam_proc p on p.id = l.process_id
where  l.log_level <= 2
and    l.no >= 0
and    p.process_name in (select param_value from spm_config
                          where param_name in ('POLL_PROCESS_NAME', 'WATCHDOG_PROCESS_NAME', 'NOTIFY_PROCESS_NAME'))
and    not exists (select 1 from spm_run r where r.lilam_process_id = p.id and r.trigger_type = 'TEST');
