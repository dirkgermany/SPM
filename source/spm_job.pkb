create or replace package body spm_job as

    function job_name return varchar2 is
    begin
        return upper(spm_cfg.get_text('POLL_JOB_NAME', 'SPM_POLL_JOB'));
    end job_name;

    -- Eigener Job-Name nur als einfacher SQL-Name
    function resolve(p_job_name varchar2) return varchar2 is
    begin
        return dbms_assert.simple_sql_name(upper(nvl(p_job_name, job_name)));
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

    procedure create_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null,
        p_symbol_like      varchar2 default null
    ) is
        l_name     varchar2(128) := resolve(p_job_name);
        l_interval number        := nvl(p_interval_minutes, spm_cfg.get_number('POLL_INTERVAL_MINUTES', 15));
        l_repeat   varchar2(100);
        l_action   varchar2(400);
    begin
        if l_interval is null or l_interval < 1 or l_interval > 1440 or l_interval <> trunc(l_interval) then
            raise_application_error(C_ERR_JOB, 'Intervall in ganzen Minuten von 1 bis 1440 angeben');
        end if;
        l_repeat := 'FREQ=MINUTELY;INTERVAL=' || l_interval;
        l_action := 'begin spm_poll.run(''SCHEDULER'''
                 || case when p_symbol_like is not null
                         then ', ''' || replace(p_symbol_like, '''', '''''') || '''' end
                 || '); end;';

        if job_exists(l_name) then
            dbms_scheduler.disable(l_name, force => true);
            dbms_scheduler.set_attribute(l_name, 'repeat_interval', l_repeat);
            dbms_scheduler.set_attribute(l_name, 'job_action', l_action);
        else
            dbms_scheduler.create_job(
                job_name        => l_name,
                job_type        => 'PLSQL_BLOCK',
                job_action      => l_action,
                repeat_interval => l_repeat,
                enabled         => false,
                auto_drop       => false,
                comments        => 'SPM: Kursabruf (spm_poll.run), angelegt mit spm_job.create_job');
        end if;

        if p_enable then
            dbms_scheduler.enable(l_name);
        end if;
    end create_job;

    procedure enable_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name);
    begin
        if not job_exists(l_name) then
            raise_application_error(C_ERR_JOB, 'Job ' || l_name || ' existiert nicht (spm_job.create_job)');
        end if;
        dbms_scheduler.enable(l_name);
    end enable_job;

    procedure disable_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name);
    begin
        if job_exists(l_name) then
            dbms_scheduler.disable(l_name, force => true);
        end if;
    end disable_job;

    procedure run_now(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name);
    begin
        if not job_exists(l_name) then
            raise_application_error(C_ERR_JOB, 'Job ' || l_name || ' existiert nicht (spm_job.create_job)');
        end if;
        dbms_scheduler.run_job(l_name, use_current_session => false);
    end run_now;

    procedure drop_job(p_job_name varchar2 default null) is
        l_name varchar2(128) := resolve(p_job_name);
    begin
        if job_exists(l_name) then
            dbms_scheduler.drop_job(l_name, force => true);
        end if;
    end drop_job;

end spm_job;
/
