create or replace package spm_job as
    -- DBMS_SCHEDULER-Jobs von SPM:
    --   Abruf-Job:    spm_poll.run('SCHEDULER'); jeder Lauf ist ein eigener LILAM-Prozess
    --                 (In-Session). Ein systemischer Fehler endet mit Ausnahme, der Scheduler
    --                 verbucht den Lauf als FAILED.
    --   Watchdog-Job: spm_watchdog.run (LILAM.CHECK_SILENCE und Zustand des Abruf-Jobs).
    --
    -- Namen und Intervalle aus SPM_CONFIG (POLL_JOB_NAME, POLL_INTERVAL_MINUTES,
    -- WATCHDOG_JOB_NAME, WATCHDOG_INTERVAL_MINUTES). Die Installation legt keinen Job an:
    -- create_job / create_watchdog_job, dann enable_job.

    C_ERR_JOB constant pls_integer := -20321;

    -- Abruf-Job anlegen oder Intervall/Filter ändern; der Job bleibt bzw. wird ausgeschaltet,
    -- wenn p_enable = false. p_symbol_like: nur für Tests (Teilmenge der Watchlist), sonst NULL.
    procedure create_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null,
        p_symbol_like      varchar2 default null
    );

    -- Watchdog-Job anlegen oder Intervall ändern (wie create_job)
    procedure create_watchdog_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null
    );

    -- Zustell-Job (spm_notify.run_consumer) anlegen; Intervall = Laufzeit eines Laufs
    -- (NOTIFY_RUN_MINUTES), danach startet der Scheduler den nächsten Lauf.
    procedure create_notify_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null
    );

    -- p_job_name NULL = Abruf-Job; sonst z. B. spm_job.watchdog_job_name, spm_job.notify_job_name
    procedure enable_job(p_job_name varchar2 default null);

    -- Ein laufender Lauf wird nicht abgebrochen, nur keine weiteren gestartet.
    procedure disable_job(p_job_name varchar2 default null);

    -- Laufenden Lauf beenden (z. B. vor dem Neukompilieren von Paketen, die ein langer
    -- Zustell-Lauf belegt). Der Zeitplan bleibt; eingeschaltete Jobs laufen planmäßig weiter.
    procedure stop_job(p_job_name varchar2 default null);

    -- Einmal sofort in eigener Session starten (asynchron), unabhängig vom Zeitplan.
    procedure run_now(p_job_name varchar2 default null);

    procedure drop_job(p_job_name varchar2 default null);

    function job_name return varchar2;

    function watchdog_job_name return varchar2;

    function notify_job_name return varchar2;

end spm_job;
/
