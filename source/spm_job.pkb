create or replace package body spm_job as

    function job_name return varchar2 is
    begin
        return upper(spm_cfg.get_text('POLL_JOB_NAME', 'SPM_POLL_JOB'));
    end job_name;

    function watchdog_job_name return varchar2 is
    begin
        return upper(spm_cfg.get_text('WATCHDOG_JOB_NAME', 'SPM_WATCHDOG_JOB'));
    end watchdog_job_name;

    function notify_job_name return varchar2 is
    begin
        return upper(spm_cfg.get_text('NOTIFY_JOB_NAME', 'SPM_NOTIFY_JOB'));
    end notify_job_name;

    -- Eigener Job-Name nur als einfacher SQL-Name
    function resolve(p_job_name varchar2, p_default varchar2) return varchar2 is
    begin
        return dbms_assert.simple_sql_name(upper(nvl(p_job_name, p_default)));
    exception
        when others then
            raise_application_error(C_ERR_JOB, 'Ungültiger Job-Name: ' || substr(p_job_name, 1, 128));
    end resolve;

    function job_exists(p_job_name varchar2) return boolean is
        l_count pls_integer;
    begin
        select count(*) into l_count from user_scheduler_jobs where job_name = p_job_name;
        return l_count > 0;
    end job_exists;

    procedure ensure_job(
        p_name     varchar2,
        p_action   varchar2,
        p_interval number,
        p_enable   boolean,
        p_comment  varchar2
    ) is
        l_repeat varchar2(100);
    begin
        if p_interval is null or p_interval < 1 or p_interval > 1440 or p_interval <> trunc(p_interval) then
            raise_application_error(C_ERR_JOB, 'Intervall in ganzen Minuten von 1 bis 1440 angeben');
        end if;
        l_repeat := 'FREQ=MINUTELY;INTERVAL=' || p_interval;

        if job_exists(p_name) then
            dbms_scheduler.disable(p_name, force => true);
            dbms_scheduler.set_attribute(p_name, 'repeat_interval', l_repeat);
            dbms_scheduler.set_attribute(p_name, 'job_action', p_action);
        else
            dbms_scheduler.create_job(
                job_name        => p_name,
                job_type        => 'PLSQL_BLOCK',
                job_action      => p_action,
                repeat_interval => l_repeat,
                enabled         => false,
                auto_drop       => false,
                comments        => p_comment);
        end if;

        if p_enable then
            dbms_scheduler.enable(p_name);
        end if;
    end ensure_job;

    procedure create_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null,
        p_symbol_like      varchar2 default null
    ) is
    begin
        ensure_job(
            p_name     => resolve(p_job_name, job_name),
            p_action   => 'begin spm_poll.run(''SCHEDULER'''
                       || case when p_symbol_like is not null
                               then ', ''' || replace(p_symbol_like, '''', '''''') || '''' end
                       || '); end;',
            p_interval => nvl(p_interval_minutes, spm_cfg.get_number('POLL_INTERVAL_MINUTES', 15)),
            p_enable   => p_enable,
            p_comment  => 'SPM: Kursabruf (spm_poll.run), angelegt mit spm_job.create_job');
    end create_job;

    procedure create_watchdog_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null
    ) is
    begin
        ensure_job(
            p_name     => resolve(p_job_name, watchdog_job_name),
            p_action   => 'begin spm_watchdog.run; end;',
            p_interval => nvl(p_interval_minutes, spm_cfg.get_number('WATCHDOG_INTERVAL_MINUTES', 5)),
            p_enable   => p_enable,
            p_comment  => 'SPM: Watchdog (spm_watchdog.run), angelegt mit spm_job.create_watchdog_job');
    end create_watchdog_job;

    procedure create_notify_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null
    ) is
    begin
        ensure_job(
            p_name     => resolve(p_job_name, notify_job_name),
            p_action   => 'begin spm_notify.run_consumer; end;',
            p_interval => nvl(p_interval_minutes, spm_cfg.get_number('NOTIFY_RUN_MINUTES', 60)),
            p_enable   => p_enable,
            p_comment  => 'SPM: Zustellung von Alerts (spm_notify.run_consumer), angelegt mit spm_job.create_notify_job');
    end create_notify_job;

    procedure enable_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name, job_name);
    begin
        if not job_exists(l_name) then
            raise_application_error(C_ERR_JOB, 'Job ' || l_name || ' existiert nicht');
        end if;
        dbms_scheduler.enable(l_name);
    end enable_job;

    procedure disable_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name, job_name);
    begin
        if job_exists(l_name) then
            dbms_scheduler.disable(l_name, force => true);
        end if;
    end disable_job;

    procedure stop_job(p_job_name varchar2 default null) is
        l_name  varchar2(128) := resolve(p_job_name, job_name);
        l_state user_scheduler_jobs.state%type;
    begin
        select max(state) into l_state from user_scheduler_jobs where job_name = l_name;
        if l_state = 'RUNNING' then
            begin
                dbms_scheduler.stop_job(l_name);
            exception
                when others then
                    if sqlcode = -27366 then null; -- Job läuft nicht mehr
                    else dbms_scheduler.stop_job(l_name, force => true);
                    end if;
            end;
        end if;
    end stop_job;

    procedure run_now(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name, job_name);
    begin
        if not job_exists(l_name) then
            raise_application_error(C_ERR_JOB, 'Job ' || l_name || ' existiert nicht');
        end if;
        dbms_scheduler.run_job(l_name, use_current_session => false);
    end run_now;

    procedure drop_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name, job_name);
    begin
        if job_exists(l_name) then
            dbms_scheduler.drop_job(l_name, force => true);
        end if;
    end drop_job;

end spm_job;
/
