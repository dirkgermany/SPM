create or replace package spm_prov as
    -- Provider-Schnittstelle: einheitliches Ergebnis eines Kursabrufs, Auswahl des
    -- Adapters je Provider und gemeinsame Hilfsfunktionen für die Adapter.
    -- Adapter liefern Format-/Transportfehler; fachliche Plausibilität prüft SPM_POLL.

    -- Ergebnis (OUTCOME)
    C_OK          constant varchar2(20) := 'OK';
    C_HTTP_ERROR  constant varchar2(20) := 'HTTP_ERROR';   -- HTTP-Status <> 200
    C_TIMEOUT     constant varchar2(20) := 'TIMEOUT';
    C_QUOTA       constant varchar2(20) := 'QUOTA';        -- Quotenlimit: Lauf abbrechen
    C_PARSE_ERROR constant varchar2(20) := 'PARSE_ERROR';  -- JSON/Pflichtfeld/Zahlformat
    C_SYSTEMIC    constant varchar2(20) := 'SYSTEMIC';     -- Verbindung/ACL/TLS: Lauf abbrechen
    -- von SPM_POLL vergeben
    C_INVALID     constant varchar2(20) := 'INVALID';      -- Währung, Wertebereich, Zukunft
    C_STALE       constant varchar2(20) := 'STALE';        -- Quote zu alt
    C_DUPLICATE   constant varchar2(20) := 'DUPLICATE';    -- Quote bereits gespeichert
    C_ERROR       constant varchar2(20) := 'ERROR';        -- unerwarteter Fehler je Symbol

    type t_quote is record (
        outcome       varchar2(20),
        http_status   pls_integer,
        price         number,
        currency      varchar2(3),
        quote_ts_utc  timestamp,
        message       varchar2(400)   -- bereinigt, ohne Geheimnisse
    );

    function fetch_quote(p_instrument spm_instrument%rowtype) return t_quote;

    -- Hilfsfunktionen für Adapter
    function utc_now return timestamp;

    -- Dezimalzahl mit Punkt (JSON-Text); NULL, wenn keine gültige Zahl
    function parse_decimal(p_text varchar2) return number;

    -- ISO 8601 mit Z oder +hh:mm, optional Sekundenbruchteile; Ergebnis in UTC; NULL, wenn ungültig
    function parse_iso_utc(p_text varchar2) return timestamp;

    -- Kürzt und entfernt Schlüssel/Token (apikey=..., token=...) aus Diagnosetexten
    function sanitize(p_text varchar2, p_max_len pls_integer default 400) return varchar2;

    -- Geheimnis (API-Schlüssel) zum Provider unter SPM_PROVIDER.CREDENTIAL_NAME;
    -- NULL/leer löscht. GET_SECRET liefert NULL, wenn keins hinterlegt ist.
    procedure set_secret(p_provider_code varchar2, p_secret varchar2);
    function get_secret(p_provider_code varchar2) return varchar2;

    -- HTTPS-GET. Setzt HTTP_STATUS in p_quote und liefert den Body (höchstens
    -- HTTP_MAX_BODY_CHARS Zeichen). Transportfehler: OUTCOME TIMEOUT bzw. SYSTEMIC
    -- (ACL, TLS, DNS, Verbindung), Body NULL. Der Auth-Header wird nie protokolliert.
    procedure http_get(
        p_url         varchar2,
        p_auth_header varchar2,
        p_quote       in out nocopy t_quote,
        o_body        out nocopy clob
    );

end spm_prov;
/
