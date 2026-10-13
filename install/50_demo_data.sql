-- =============================================================================
-- SPM: Demo-Watchlist mit dem Mock-Provider (optional, wiederholbar)
-- Die Kurse sind simuliert (Zufallsbewegung), keine echten Marktdaten.
-- =============================================================================

begin
    spm_watchlist.save_instrument(p_symbol => 'SAP',  p_provider_code => 'MOCK', p_provider_symbol => 'SAP',
                                  p_currency => 'EUR', p_name => 'SAP SE (Mock)',     p_exchange => 'XETRA');
    spm_watchlist.save_instrument(p_symbol => 'SIE',  p_provider_code => 'MOCK', p_provider_symbol => 'SIE',
                                  p_currency => 'EUR', p_name => 'Siemens AG (Mock)', p_exchange => 'XETRA');
    spm_watchlist.save_instrument(p_symbol => 'AAPL', p_provider_code => 'MOCK', p_provider_symbol => 'AAPL',
                                  p_currency => 'USD', p_name => 'Apple Inc. (Mock)', p_exchange => 'NASDAQ');
    commit;
end;
/
