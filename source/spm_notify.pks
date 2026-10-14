create or replace package spm_notify as
    -- Zustellung von LILAM-Alerts per E-Mail (Consumer), getrennt vom Kursabruf.
    --
    -- Verarbeitet Alerts mit Status PENDING der SPM-Gruppe (LILAM_GROUP) und des SPM-Kanals
    -- (RULE_HANDLER): Mailtext mit Symbol, Kurs, EWMA und Regel aufbereiten, versenden,
    -- in SPM_NOTIFICATION protokollieren und den Alert auf PROCESSED bzw. ERROR setzen.
    -- Ohne MAIL_FROM/MAIL_TO bleibt ein Alert PENDING (Warnung im LILAM-Log).
    --
    -- Transport (MAIL_TRANSPORT): SMTP = UTL_SMTP an MAIL_SMTP_HOST:MAIL_SMTP_PORT
    -- (Netzwerk-ACL: install/01_admin_network_acl.sql), MOCK = nur protokollieren.

    -- Wartet bis zu p_minutes (Standard NOTIFY_RUN_MINUTES) per DBMS_ALERT auf Alerts und
    -- verarbeitet sie; ein Lauf ist ein LILAM-Prozess (NOTIFY_PROCESS_NAME). Für den Job.
    procedure run_consumer(p_minutes number default null);

    -- Einmal alle offenen Alerts verarbeiten; liefert die Anzahl versandter Mails.
    -- p_pid: LILAM-Prozess für Traces und Logs (NULL = ohne).
    function process_pending(p_pid number default null) return number;

    -- Betreff, Text- und HTML-Fassung eines Alerts (auch für die APEX-Vorschau)
    procedure build_message(p_alert_id number, o_subject out varchar2, o_body out clob, o_html out clob);

end spm_notify;
/
