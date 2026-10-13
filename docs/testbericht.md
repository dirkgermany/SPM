# Testbericht

## 2026-10-14: Installation und Mock-Tests

Umgebung: Oracle Database 23.26 (26ai Free), PDB `FREEPDB1`, Schema `SPM`; LILAM v2.3 vom Branch `messwerte`; SQLcl 26.3 auf der Kommandozeile (`sql -name spm`).

| Schritt | Ergebnis |
| --- | --- |
| `install/00_admin_create_schema.sql` (Dirk, als SYS) | erfolgreich nach zwei Korrekturen am Containerwechsel (ORA-65096 im CDB-Root) |
| `install/install.sql` | erster Lauf: `SPM_PROV_MOCK` ungültig (PLS-00684, `json_object … returning clob` in PL/SQL); behoben mit `json_object_t`; zweiter Lauf fehlerfrei, alle Pakete gültig |
| `test/run_tests.sql`, Lauf 1 | 161 bestanden, 0 fehlgeschlagen; Befund: `&s` in einer Mock-URL wurde als SQLcl-Substitutionsvariable ersetzt; behoben mit `set define off` im Fixture-Skript |
| `test/run_tests.sql`, Lauf 2 (Wiederholung, Baseline bereits vorhanden) | 161 bestanden, 0 fehlgeschlagen |
| Manueller Lauf mit Demo-Watchlist (`spm_poll.run('MANUAL')`) | Lauf 47: SUCCESS, 3 angefragt, 3 gespeichert; LILAM-Prozess 47 mit Status 1 |
| `LILAM_LOG_INTERNAL` | nicht vorhanden, d. h. LILAM hat keinen internen Fehler protokolliert |
| Maskierung | `apikey=SECRET123` erscheint als `apikey=***` in `SPM_INSTRUMENT.LAST_FETCH_MESSAGE`, nicht im LILAM-Log |

Nachtrag: LILAM mit dauerhafter Alert-Drosselung (`1bfd6ec`, Checkout-Stand `7f1f81b`) per `install/install.sql` neu installiert; Body enthält `LILAM_ALERT_LOCKS`, Tabelle angelegt. Tests danach erneut: 161 bestanden, 0 fehlgeschlagen. Die Drosselung selbst testet SPM noch nicht (noch kein Rule Set, folgt mit Schritt 5).

Abgedeckte Fälle: Erfolg (Zahl und Text), Idempotenz, HTTP-Fehler, Timeout, ungültiges JSON, fehlender/nicht numerischer Kurs, falsches Symbol, falsche Währung, zu alter und künftiger Zeitstempel, negativer Kurs, Geheimnis in Fehlerantwort, gemischter Lauf (ein Symbol scheitert), getrennte Reihen je Symbol, Quotenlimit, systemischer Fehler mit erneuter Ausnahme und geschlossenem Prozess, freie Sperre nach Abbruch, leere Auswahl, Überlappung, Wert-EWMA über drei Läufe.

Nicht getestet: Datenbankfehler beim Speichern (kein Einspeisungspunkt ohne Testhaken), Läufe aus zwei parallelen Sessions (Überlappung wird mit einer Sperre in derselben Session simuliert), Regeln und Alerts (noch kein Rule Set), Scheduler, APEX, echter Provider.

Hinweis zum Werkzeug: `whenever sqlerror exit` in den Skripten beendet den SQLcl-Prozess. Im SQLcl-MCP-Server der Claude-App führte das nach dem ersten (fehlgeschlagenen) Lauf dazu, dass der Server keine Ausgaben mehr lieferte. Skripte deshalb auf der Kommandozeile ausführen.
