create or replace package spm_watchlist as
    -- Watchlist-Verwaltung mit Validierung. Commit macht der Aufrufer.

    -- Symbol normalisieren: Leerzeichen entfernen, Großbuchstaben
    function normalize_symbol(p_symbol varchar2) return varchar2;

    -- Anlegen oder Ändern (Schlüssel: normalisiertes Symbol); liefert INSTRUMENT_ID.
    -- Fehler: ORA-20201 mit Begründung.
    function save_instrument(
        p_symbol           varchar2,
        p_provider_code    varchar2,
        p_provider_symbol  varchar2,
        p_currency         varchar2,
        p_name             varchar2 default null,
        p_exchange         varchar2 default null,
        p_is_active        varchar2 default 'Y'
    ) return number;

    procedure save_instrument(
        p_symbol           varchar2,
        p_provider_code    varchar2,
        p_provider_symbol  varchar2,
        p_currency         varchar2,
        p_name             varchar2 default null,
        p_exchange         varchar2 default null,
        p_is_active        varchar2 default 'Y'
    );

    procedure set_active(p_symbol varchar2, p_is_active varchar2);

    -- Kurshistorie eines Symbols löschen: Kurse (SPM_PRICE), Abrufstatus und die LILAM-Baselines
    -- des Symbols (Kurs, Quote-Alter, Provider-Aufruf) im Scope LILAM_BASELINE_SCOPE; das
    -- EWMA-Warm-up beginnt neu. Alerts und LILAM-Protokolle bleiben. Liefert die Zahl gelöschter
    -- Kurse. Die Baselines setzt LILAM sofort (eigene Transaktion), die Kurse committet der Aufrufer.
    -- Fehler ORA-20201: Symbol unbekannt oder ein Abruflauf ist aktiv.
    function delete_history(p_symbol varchar2) return number;

end spm_watchlist;
/
