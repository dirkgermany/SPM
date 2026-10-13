-- =============================================================================
-- SPM: Mock-Antworten für die automatisierten Tests (Provider MOCK, Symbole TST*)
-- Wiederholbar: vorhandene Test-Fixtures werden ersetzt.
-- Platzhalter: {NOW}, {NOW-<n>M}, {YESTERDAY_NOON} (UTC, ISO 8601)
-- =============================================================================

delete from spm_mock_response where provider_symbol like 'TST%';

insert into spm_mock_response (provider_symbol, seq_no, http_status, simulate_timeout, body, note)
select provider_symbol, seq_no, http_status, simulate_timeout, body, note from (
    -- Erfolg
    select 'TSTOK'  provider_symbol, 1 seq_no, 200 http_status, 'N' simulate_timeout,
           '{"symbol":"TSTOK","price":101.5,"currency":"EUR","timestamp":"{NOW}"}' body, 'gültiger Kurs' note from dual union all
    select 'TSTSTR', 1, 200, 'N', '{"symbol":"TSTSTR","price":"123.45","currency":"EUR","timestamp":"{NOW}"}', 'Kurs als Text' from dual union all
    -- Idempotenz: zweimal derselbe Quote
    select 'TSTDUP', 1, 200, 'N', '{"symbol":"TSTDUP","price":50,"currency":"EUR","timestamp":"{YESTERDAY_NOON}"}', 'Quote 1' from dual union all
    select 'TSTDUP', 2, 200, 'N', '{"symbol":"TSTDUP","price":50,"currency":"EUR","timestamp":"{YESTERDAY_NOON}"}', 'derselbe Quote erneut' from dual union all
    -- Transport- und Formatfehler
    select 'TSTH500', 1, 500, 'N', '{"error":"internal server error"}', 'HTTP 500' from dual union all
    select 'TSTTMO',  1, 200, 'Y', null, 'Zeitüberschreitung' from dual union all
    select 'TSTJSN',  1, 200, 'N', 'kein JSON {', 'ungültiges JSON' from dual union all
    select 'TSTNOP',  1, 200, 'N', '{"symbol":"TSTNOP","currency":"EUR","timestamp":"{NOW}"}', 'price fehlt' from dual union all
    select 'TSTNAN',  1, 200, 'N', '{"symbol":"TSTNAN","price":"abc","currency":"EUR","timestamp":"{NOW}"}', 'price nicht numerisch' from dual union all
    select 'TSTSYM',  1, 200, 'N', '{"symbol":"OTHER","price":1,"currency":"EUR","timestamp":"{NOW}"}', 'falsches Symbol' from dual union all
    -- fachliche Prüfung
    select 'TSTCCY',  1, 200, 'N', '{"symbol":"TSTCCY","price":10,"currency":"USD","timestamp":"{NOW}"}', 'falsche Währung' from dual union all
    select 'TSTOLD',  1, 200, 'N', '{"symbol":"TSTOLD","price":10,"currency":"EUR","timestamp":"2020-01-01T00:00:00Z"}', 'zu alt' from dual union all
    select 'TSTFUT',  1, 200, 'N', '{"symbol":"TSTFUT","price":10,"currency":"EUR","timestamp":"2099-01-01T00:00:00Z"}', 'Zukunft' from dual union all
    select 'TSTNEG',  1, 200, 'N', '{"symbol":"TSTNEG","price":-5,"currency":"EUR","timestamp":"{NOW}"}', 'negativer Kurs' from dual union all
    -- Geheimnis in der Fehlerantwort darf nicht in Logs landen
    select 'TSTKEY',  1, 401, 'N', '{"error":"invalid key","url":"https://example.invalid/q?apikey=SECRET123&s=X"}', 'Schlüssel in Antwort' from dual union all
    -- ein Symbol scheitert, die anderen laufen weiter
    select 'TSTM1',   1, 200, 'N', '{"symbol":"TSTM1","price":11,"currency":"EUR","timestamp":"{NOW}"}', 'gemischt ok' from dual union all
    select 'TSTM2',   1, 503, 'N', '{"error":"unavailable"}', 'gemischt Fehler' from dual union all
    select 'TSTM3',   1, 200, 'N', '{"symbol":"TSTM3","price":33,"currency":"EUR","timestamp":"{NOW}"}', 'gemischt ok' from dual union all
    -- Quotenlimit bricht den Lauf ab
    select 'TSTQ1',   1, 429, 'N', '{"note":"rate limit"}', 'Quote erschöpft' from dual union all
    select 'TSTQ2',   1, 200, 'N', '{"symbol":"TSTQ2","price":2,"currency":"EUR","timestamp":"{NOW}"}', 'nach Quotenlimit nicht abgefragt' from dual union all
    -- systemischer Fehler (Verbindung/ACL/TLS)
    select 'TSTSYS',  1,   0, 'N', null, 'keine Verbindung' from dual union all
    -- Baseline über mehrere Läufe
    select 'TSTB',    1, 200, 'N', '{"symbol":"TSTB","price":100,"currency":"EUR","timestamp":"{NOW-3M}"}', 'Baseline 1' from dual union all
    select 'TSTB',    2, 200, 'N', '{"symbol":"TSTB","price":101,"currency":"EUR","timestamp":"{NOW-2M}"}', 'Baseline 2' from dual union all
    select 'TSTB',    3, 200, 'N', '{"symbol":"TSTB","price":102,"currency":"EUR","timestamp":"{NOW-1M}"}', 'Baseline 3' from dual
);

commit;
