-- =============================================================================
-- SPM: Demo-Watchlist mit dem Mock-Provider und Beispielregeln (optional, wiederholbar)
-- Die Kurse sind simuliert (Zufallsbewegung um 100), keine echten Marktdaten.
-- Veröffentlicht das Rule Set für die Gruppe aus SPM_CONFIG.LILAM_GROUP.
-- =============================================================================

begin
    spm_watchlist.save_instrument(p_symbol => 'SAP',  p_provider_code => 'MOCK', p_provider_symbol => 'SAP',
                                  p_currency => 'EUR', p_name => 'SAP SE (Mock)',     p_exchange => 'XETRA');
    spm_watchlist.save_instrument(p_symbol => 'SIE',  p_provider_code => 'MOCK', p_provider_symbol => 'SIE',
                                  p_currency => 'EUR', p_name => 'Siemens AG (Mock)', p_exchange => 'XETRA');
    spm_watchlist.save_instrument(p_symbol => 'AAPL', p_provider_code => 'MOCK', p_provider_symbol => 'AAPL',
                                  p_currency => 'USD', p_name => 'Apple Inc. (Mock)', p_exchange => 'NASDAQ');

    -- Grenzen und Ausreißer; Drosselung 1 h je Regel und Symbol
    spm_rules.save_rule('SAP',  p_val_min => 80, p_val_max => 120, p_ewma_pct_up => 3, p_ewma_pct_down => 3,
                        p_ewma_warmup => 5, p_ewma_alpha => 0.2);
    spm_rules.save_rule('SIE',  p_val_min => 85, p_val_max => 115);
    spm_rules.save_rule('AAPL', p_ewma_pct_up => 2.5, p_ewma_pct_down => 2.5);
    commit;

    dbms_output.put_line('Rule Set aktiv in Version ' || spm_rules.publish('SPM_DEMO'));
end;
/
