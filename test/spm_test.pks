create or replace package spm_test as
    -- Automatisierte Tests mit dem Mock-Provider (Symbole TST*, Lauf-Trigger TEST).
    -- Voraussetzung: test/fixtures/mock_responses.sql wurde ausgeführt.
    -- Ergebnis über DBMS_OUTPUT; bei Fehlschlägen endet RUN_ALL mit ORA-20900.

    procedure run_all;

end spm_test;
/
