-- =============================================================================
-- SPM: Live-Test Twelve Data (optional, braucht Netzwerk, ACL und API-Schlüssel)
--
--   @test/live_twelvedata.sql "SAP:XETR,AAPL"
--
-- Ruft je Provider-Symbol einmal /quote ab (1 API-Credit je Symbol) und zeigt das
-- Ergebnis. Speichert nichts, erzeugt keinen LILAM-Prozess.
-- =============================================================================

set serveroutput on size unlimited
set feedback off
set verify off

declare
    l_inst  spm_instrument%rowtype;
    l_quote spm_prov.t_quote;
begin
    for s in (select trim(regexp_substr('&1', '[^,]+', 1, level)) sym
              from   dual
              connect by level <= regexp_count('&1', '[^,]+')) loop
        l_inst.provider_code   := 'TWELVEDATA';
        l_inst.provider_symbol := s.sym;
        l_quote := spm_prov.fetch_quote(l_inst);
        dbms_output.put_line(rpad(s.sym, 14) || rpad(l_quote.outcome, 12)
            || 'HTTP ' || rpad(nvl(to_char(l_quote.http_status), '-'), 5)
            || nvl(to_char(l_quote.price, 'FM999999990.0999'), '-') || ' ' || l_quote.currency || '  '
            || case when l_quote.quote_ts_utc is not null
                    then to_char(l_quote.quote_ts_utc, 'YYYY-MM-DD HH24:MI:SS') || ' UTC  ' end
            || l_quote.message);
    end loop;
end;
/
