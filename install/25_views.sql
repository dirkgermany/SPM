-- =============================================================================
-- SPM: Sichten
-- =============================================================================

-- Zustand der Jobs (Abruf, Watchdog, Zustellung) (DBMS_SCHEDULER) und Aktualität der
-- Abrufläufe in einer Zeile. Eine Zeile auch ohne Job (JOB_EXISTS = 'N'), damit Dashboard
-- und Watchdog das erkennen. Abrufläufe: nur über die ganze Watchlist (ohne Symbolfilter,
-- den nur Tests setzen).
create or replace view spm_job_status_v as
with cfg as (
    select upper(coalesce(max(case when param_name = 'POLL_JOB_NAME' then param_value end), 'SPM_POLL_JOB')) job_name,
           max(case when param_name = 'POLL_INTERVAL_MINUTES' then param_value end) interval_minutes,
           upper(coalesce(max(case when param_name = 'WATCHDOG_JOB_NAME' then param_value end), 'SPM_WATCHDOG_JOB')) wd_job_name,
           upper(coalesce(max(case when param_name = 'NOTIFY_JOB_NAME' then param_value end), 'SPM_NOTIFY_JOB')) nt_job_name
    from   spm_config
),
last_detail as (
    select d.job_name, d.status, d.error#, d.actual_start_date, d.run_duration,
           substr(d.additional_info, 1, 1000) additional_info
    from   user_scheduler_job_run_details d
    join   cfg on d.job_name = cfg.job_name
    order  by d.log_id desc
    fetch  first 1 row only
),
wd_detail as (
    select d.status, d.error#
    from   user_scheduler_job_run_details d
    join   cfg on d.job_name = cfg.wd_job_name
    order  by d.log_id desc
    fetch  first 1 row only
),
nt_detail as (
    select d.status, d.error#
    from   user_scheduler_job_run_details d
    join   cfg on d.job_name = cfg.nt_job_name
    order  by d.log_id desc
    fetch  first 1 row only
),
runs as (
    select max(case when status in ('SUCCESS', 'PARTIAL') then ended_at end) last_success_at,
           max(case when status = 'FAILED' then ended_at end)                last_failure_at,
           max(started_at)                                                   last_start_at
    from   spm_run
    where  trigger_type in ('SCHEDULER', 'MANUAL', 'APEX') and symbol_filter is null
),
last_run as (
    select run_id, trigger_type, status, started_at, ended_at, cnt_requested, cnt_stored, cnt_failed, message
    from   spm_run
    where  trigger_type in ('SCHEDULER', 'MANUAL', 'APEX') and symbol_filter is null
    order  by run_id desc
    fetch  first 1 row only
)
select cfg.job_name,
       case when j.job_name is null then 'N' else 'Y' end job_exists,
       j.enabled,
       j.state,
       j.repeat_interval,
       cfg.interval_minutes                        configured_interval_minutes,
       j.next_run_date,
       j.last_start_date,
       j.last_run_duration,
       j.run_count,
       j.failure_count,
       d.status                                    last_job_status,
       d.error#                                    last_job_error,
       d.additional_info                           last_job_info,
       runs.last_start_at,
       runs.last_success_at,
       runs.last_failure_at,
       lr.run_id                                   last_run_id,
       lr.trigger_type                             last_run_trigger,
       lr.status                                   last_run_status,
       lr.cnt_requested                            last_run_requested,
       lr.cnt_stored                               last_run_stored,
       lr.cnt_failed                               last_run_failed,
       lr.message                                  last_run_message,
       cfg.wd_job_name,
       case when w.job_name is null then 'N' else 'Y' end wd_job_exists,
       w.enabled                                   wd_enabled,
       w.state                                     wd_state,
       w.next_run_date                             wd_next_run_date,
       w.last_start_date                           wd_last_start_date,
       w.failure_count                             wd_failure_count,
       wd.status                                   wd_last_job_status,
       wd.error#                                   wd_last_job_error,
       cfg.nt_job_name,
       case when n.job_name is null then 'N' else 'Y' end nt_job_exists,
       n.enabled                                   nt_enabled,
       n.state                                     nt_state,
       n.next_run_date                             nt_next_run_date,
       n.failure_count                             nt_failure_count,
       nt.status                                   nt_last_job_status,
       nt.error#                                   nt_last_job_error,
       (select count(*) from lilam_alerts la
        where  la.status = 'PENDING'
        and    upper(la.group_name) = upper((select param_value from spm_config where param_name = 'LILAM_GROUP')))
                                                   alerts_pending
from   cfg
left   join user_scheduler_jobs j on j.job_name = cfg.job_name
left   join user_scheduler_jobs w on w.job_name = cfg.wd_job_name
left   join user_scheduler_jobs n on n.job_name = cfg.nt_job_name
left   join last_detail d         on 1 = 1
left   join wd_detail wd          on 1 = 1
left   join nt_detail nt          on 1 = 1
cross  join runs
left   join last_run lr           on 1 = 1;
