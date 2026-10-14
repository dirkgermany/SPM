create or replace package body spm_watchdog as

    function poll_job_health(o_reason out varchar2) return number is
        v spm_job_status_v%rowtype;
    begin
        select * into v from spm_job_status_v;

        if v.job_exists = 'N' then
            o_reason := 'Abruf-Job ' || v.job_name || ' existiert nicht';
        elsif v.enabled <> 'TRUE' then
            o_reason := 'Abruf-Job ' || v.job_name || ' ist ausgeschaltet';
        elsif v.state in ('BROKEN', 'FAILED') then
            o_reason := 'Abruf-Job ' || v.job_name || ' hat den Zustand ' || v.state;
        elsif v.last_job_status = 'FAILED' then
            o_reason := 'Letzter Lauf des Abruf-Jobs ' || v.job_name || ' fehlgeschlagen (ORA-' || v.last_job_error || ')';
        end if;

        return case when o_reason is null then 1 else 0 end;
    end poll_job_health;

    procedure run is
        l_group  varchar2(50) := spm_cfg.get_text('LILAM_GROUP');
        l_pid    number;
        l_health number;
        l_reason varchar2(400);
        l_errm   varchar2(4000);
    begin
        l_pid := lilam.new_process(
                     p_processName   => spm_cfg.get_text('WATCHDOG_PROCESS_NAME', 'SPM_WATCHDOG'),
                     p_logLevel      => spm_cfg.get_number('LILAM_LOG_LEVEL', lilam.logLevelInfo),
                     p_daysToKeep    => spm_cfg.get_number('WATCHDOG_DAYS_TO_KEEP'),
                     p_tabNameMaster => spm_cfg.get_text('LILAM_TABNAME_MASTER', 'LILAM'),
                     p_baselineScope => spm_cfg.get_text('LILAM_BASELINE_SCOPE'),
                     p_groupName     => l_group);

        if l_group is not null then
            lilam.check_silence(l_group);
        end if;

        l_health := poll_job_health(l_reason);
        lilam.mark_event(l_pid, C_ACT_POLL_JOB_HEALTH, null, l_health);
        if l_health = 0 then
            lilam.warn(l_pid, l_reason);
        end if;

        lilam.close_process(l_pid, nvl(l_reason, 'Abruf-Job in Ordnung'),
                            case l_health when 1 then spm_poll.C_STATUS_SUCCESS else spm_poll.C_STATUS_PARTIAL end);
    exception
        when others then
            l_errm := substr(sqlerrm || ' ' || dbms_utility.format_error_backtrace, 1, 4000);
            begin
                if l_pid is not null then
                    lilam.error(l_pid, 'Watchdog-Lauf abgebrochen: ' || l_errm);
                    lilam.close_process(l_pid, substr('Abgebrochen: ' || l_errm, 1, 2000), spm_poll.C_STATUS_FAILED);
                end if;
            exception
                when others then null;
            end;
            raise;
    end run;

end spm_watchdog;
/
