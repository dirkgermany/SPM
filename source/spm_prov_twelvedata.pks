create or replace package spm_prov_twelvedata as
    -- Adapter für Twelve Data (https://twelvedata.com), Endpunkt /quote.
    --
    -- Provider-Symbol: <Ticker> oder <Ticker>:<MIC>, z. B. AAPL oder SAP:XETR.
    -- Basis-URL aus SPM_PROVIDER.BASE_URL, API-Schlüssel aus SPM_SECRET (Header
    -- Authorization: apikey ..., nie in der URL). Ein Symbol kostet 1 API-Credit.
    --
    -- Abbildung: close = Kurs, currency = Währung, last_quote_at (sonst timestamp,
    -- Unix-Sekunden) = Quote-Zeitstempel. Fehler: 429 = QUOTA, 401 = SYSTEMIC
    -- (Schlüssel ungültig), sonst HTTP_ERROR (z. B. 404 Symbol unbekannt oder nicht im Tarif).

    function fetch_quote(p_instrument spm_instrument%rowtype) return spm_prov.t_quote;

    -- Auswertung einer Antwort; öffentlich für Tests ohne Netzwerk
    function parse_response(
        p_http_status     pls_integer,
        p_body            clob,
        p_provider_symbol varchar2
    ) return spm_prov.t_quote;

    -- URL des Abrufs (ohne Schlüssel); öffentlich für Tests und Diagnose
    function quote_url(p_base_url varchar2, p_provider_symbol varchar2) return varchar2;

end spm_prov_twelvedata;
/
