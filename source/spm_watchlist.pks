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

end spm_watchlist;
/
