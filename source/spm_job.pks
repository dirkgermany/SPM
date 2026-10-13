create or replace package spm_job as
    -- DBMS_SCHEDULER-Job für den Kursabruf. Der Job ruft spm_poll.run('SCHEDULER') auf;
    -- jeder Lauf ist ein eigener LILAM-Prozess in der Job-Session (In-Session-Modus).
    -- Ein Lauf mit systemischem Fehler endet mit Ausnahme, der Scheduler verbucht ihn als FAILED.
    --
    -- Name und Intervall aus SPM_CONFIG (POLL_JOB_NAME, POLL_INTERVAL_MINUTES).
    -- Die Installation legt den Job nicht an: create_job, dann enable_job.

    C_ERR_JOB constant pls_integer := -20321;

    -- Anlegen oder Intervall/Filter ändern; der Job bleibt bzw. wird deaktiviert, wenn p_enable = false.
    -- p_symbol_like: nur für Tests (Teilmenge der Watchlist), sonst NULL.
    procedure create_job(
        p_interval_minutes number   default null,
        p_enable           boolean  default false,
        p_job_name         varchar2 default null,
        p_symbol_like      varchar2 default null
    );

    procedure enable_job(p_job_name varchar2 default null);

    -- Ein laufender Abruf wird nicht abgebrochen, nur keine weiteren gestartet.
    procedure disable_job(p_job_name varchar2 default null);

    -- Einmal sofort in eigener Session starten (asynchron), unabhängig vom Zeitplan.
    procedure run_now(p_job_name varchar2 default null);

    procedure drop_job(p_job_name varchar2 default null);

    function job_name return varchar2;

end spm_job;
/
