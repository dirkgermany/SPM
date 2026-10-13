create or replace package spm_prov_mock as
    -- Mock-Provider ohne Netzwerk und ohne API-Quote.
    --
    -- Gibt es in SPM_MOCK_RESPONSE Antworten zum Provider-Symbol, werden sie der Reihe
    -- nach (SEQ_NO) abgespielt und danach von vorn. Sonst erzeugt der Mock eine
    -- Zufallsbewegung um den zuletzt gespeicherten Kurs (Start 100).
    --
    -- Antwortformat (JSON):
    --   {"symbol":"SAP","price":187.42,"currency":"EUR","timestamp":"2026-10-13T13:30:00Z"}

    function fetch_quote(p_instrument spm_instrument%rowtype) return spm_prov.t_quote;

    -- Abspielposition zurücksetzen; NULL = alle Symbole
    procedure reset_state(p_provider_symbol varchar2 default null);

end spm_prov_mock;
/
