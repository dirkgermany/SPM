create or replace package spm_apex as
    -- Schicht für die APEX-Anwendung: HTML-Bausteine und Aktionen. Die Seiten rufen nur dieses
    -- Paket und die SPM-Sichten auf; die Logik bleibt in spm_poll, spm_rules, spm_job, spm_notify.

    -- Kacheln für das Dashboard (Aktualität, letzter Lauf, Alerts, Jobs)
    function dashboard_html return clob;

    -- Kopf der Instrumentseite: Stammdaten, letzter Abruf und Kursdiagramm (SVG) mit Grenzen
    function instrument_html(p_symbol varchar2) return clob;

    -- Darf der Benutzer die Administration nutzen? APEX_ADMIN_USERS in SPM_CONFIG
    -- (Komma-Liste); leer = alle angemeldeten Benutzer.
    function is_admin(p_user varchar2) return boolean;

    -- Zahl für Formularfelder im Format der Sitzung, mit führender Null und ohne überflüssige
    -- Nachkommastellen (0,2 statt ,2; 80 statt 80,0)
    function fmt_num(p_value number) return varchar2;

    -- Zustand der Jobs für die Administration
    function job_status_html return clob;

    -- HTML-Fassung der Mail zu einem Alert (Vorschau)
    function alert_mail_html(p_alert_id number) return clob;

    -- Abruf sofort in dieser Session (In-Session, eigener LILAM-Prozess); liefert eine Meldung
    function run_poll_now return varchar2;

    -- Job ein- oder ausschalten: p_kind = POLL, WATCHDOG, NOTIFY. Legt ihn bei Bedarf an.
    procedure set_job(p_kind varchar2, p_enabled boolean);

    -- Rule Set veröffentlichen; liefert eine Meldung
    function publish_rules return varchar2;

end spm_apex;
/
