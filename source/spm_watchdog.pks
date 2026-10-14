create or replace package spm_watchdog as
    -- Watchdog: läuft als eigener DBMS_SCHEDULER-Job (spm_job.create_watchdog_job).
    -- Ein Lauf ist ein LILAM-Prozess (WATCHDOG_PROCESS_NAME) und
    --   1. ruft LILAM.CHECK_SILENCE für die SPM-Gruppe auf (Schweige-Regeln: kein Abruflauf,
    --      hängender Lauf, kein neuer Kurs je Symbol, kein Watchdog-Lauf),
    --   2. prüft den Abruf-Job in DBMS_SCHEDULER und meldet das Ergebnis als Messwert
    --      POLL_JOB_HEALTH (1 = in Ordnung, 0 = fehlt, ausgeschaltet, defekt oder zuletzt
    --      fehlgeschlagen); die Regel SPM-POLLJOB-BAD alarmiert bei 0.
    -- Auch jeder Abruflauf ruft CHECK_SILENCE auf: Fällt einer der beiden Jobs aus, meldet
    -- der andere das Schweigen. Fallen beide aus, meldet niemand (Grenze, siehe Doku).

    C_ACT_POLL_JOB_HEALTH constant varchar2(30) := 'POLL_JOB_HEALTH';

    procedure run;

    -- Zustand des Abruf-Jobs: 1 = in Ordnung, 0 = nicht; o_reason erklärt 0
    function poll_job_health(o_reason out varchar2) return number;

end spm_watchdog;
/
