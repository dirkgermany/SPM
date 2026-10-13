create or replace package spm_poll as
    -- Abruflauf: Kurse der aktiven Watchlist holen, prüfen, speichern und an LILAM melden.
    -- Ein Lauf ist ein eigener LILAM-Prozess im In-Session-Modus (Gruppe und Baseline
    -- Scope aus SPM_CONFIG). Derselbe Code dient Scheduler, manuellem Abruf und Tests.
    --
    -- Überlappende Läufe verhindert eine DBMS_LOCK-Sperre: ein zweiter Lauf wird als
    -- SKIPPED protokolliert und beendet sich ohne Abruf.
    --
    -- Systemische Fehler (Provider nicht erreichbar, unerwartete Ausnahme) schließen den
    -- LILAM-Prozess mit Status -1 und werden erneut ausgelöst, damit DBMS_SCHEDULER den
    -- Lauf als fehlgeschlagen registriert. Fehler einzelner Symbole brechen den Lauf nicht ab.

    -- LILAM-Prozessstatus
    C_STATUS_SUCCESS constant pls_integer := 1;
    C_STATUS_PARTIAL constant pls_integer := 2;
    C_STATUS_FAILED  constant pls_integer := -1;

    -- LILAM-Actions (Context jeweils in Klammern)
    C_ACT_PROVIDER_CALL constant varchar2(30) := 'PROVIDER_CALL'; -- Trace (Symbol)
    C_ACT_SHARE_PRICE   constant varchar2(30) := 'SHARE_PRICE';   -- Event mit Kurs (Symbol)
    C_ACT_QUOTE_AGE     constant varchar2(30) := 'QUOTE_AGE_SEC'; -- Event mit Alter des Quotes in s (Symbol)
    C_ACT_POLL_RESULT   constant varchar2(30) := 'POLL_RESULT';   -- Event mit Anzahl (REQUESTED, FETCHED, FAILED, STORED, DUPLICATE)

    -- Systemischer Fehler: Lauf abgebrochen
    C_ERR_SYSTEMIC constant pls_integer := -20110;

    -- p_trigger: SCHEDULER, MANUAL, APEX, TEST
    -- p_symbol_like: nur Symbole, die diesem LIKE-Muster entsprechen (NULL = alle aktiven)
    -- Liefert die RUN_ID aus SPM_RUN.
    function run(p_trigger varchar2 default 'MANUAL', p_symbol_like varchar2 default null) return number;

    procedure run(p_trigger varchar2 default 'MANUAL', p_symbol_like varchar2 default null);

end spm_poll;
/
