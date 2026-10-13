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

## 2026-10-14: Schritt 5, Regeln

Umgebung wie oben; LILAM-Checkout `messwerte` mit `1bfd6ec` (dauerhafte Drosselung). Installation und Tests über die SQLcl-Kommandozeile.

| Schritt | Ergebnis |
| --- | --- |
| `install/install.sql` mit `SPM_RULE`, `spm_rules` | fehlerfrei, alle Pakete gültig |
| `test/run_tests.sql`, Lauf 1 | 201 bestanden, 0 fehlgeschlagen |
| `test/run_tests.sql`, Lauf 2 (EWMA-Reihe und Baselines vorhanden) | 201 bestanden, 0 fehlgeschlagen |
| Nachkontrolle | `LILAM_GROUP` zurückgesetzt, keine Testgruppen in `LILAM_RULES`, keine aktiven Test-Instrumente, keine Testregeln; Alerts der Testgruppe genau: `TSTR-MAX`, `TSTR-MIN`, `TSTE-UP`, `TSTE-DOWN`, `TSTT-MAX` (einmal), `SPM-RUN-FAILED`, `SPM-POLL-FAILED`, `SPM-RUN-PARTIAL` |
| `install/50_demo_data.sql` | Demo-Rule-Set aktiv in `STOCK_MONITORING`, Version 1; Export `rules/spm_rules_demo.json` |

Neue Fälle: Eingabeprüfung der Regelpflege (Grenzen, Prozent, Alpha, Warm-up, Severity, unbekanntes Symbol), erzeugtes Rule Set (Werte, keine Regel für inaktive Instrumente, technische Regeln, `CHECK_RULE_SET`), Versionierung (unverändert keine neue Version), `VAL_MAX`/`VAL_MIN` mit Context und Gruppe im Alert, EWMA-Ausreißer nach oben und unten nach dem Warm-up, Drosselung über einen Abruflauf in eigener Session (`DBMS_SCHEDULER`-Job), technische Regeln bei Fehlschlag und Teilerfolg.

Die Tests laufen in eigenen LILAM-Gruppen (`SPMTEST_<Zeitstempel>_A` bzw. `_R`), damit echte Regeln nicht greifen und Testalerts keine echten Sperren setzen. Die Regeltests brauchen eine zweite Gruppe, weil eine Session die Regeln einer bereits benutzten Gruppe bis zu 15 Sekunden zwischenspeichert.

## 2026-10-14: Scheduler-Job

| Schritt | Ergebnis |
| --- | --- |
| `install/install.sql` mit `spm_job`, `SPM_JOB_STATUS_V` | fehlerfrei |
| `test/run_tests.sql`, Lauf 1 | 226 bestanden, 0 fehlgeschlagen |
| Befund | Die Sicht zeigte als letzten Lauf den Testlauf mit simuliertem Fehler. Behoben: Die Sicht berücksichtigt nur Läufe über die ganze Watchlist (ohne Symbolfilter) |
| `test/run_tests.sql`, Lauf 2 | 226 bestanden, 0 fehlgeschlagen |
| Nachkontrolle | kein `SPM_*`-Job übrig, `POLL_JOB_NAME` und `LILAM_GROUP` zurückgesetzt; Job-Historie des Testjobs: `SUCCEEDED/0`, `FAILED/20110` |

Neue Fälle: Eingabeprüfung (Intervall, Job-Name, fehlender Job), Anlegen und Ändern ohne Einschalten, echter Lauf über `DBMS_SCHEDULER.RUN_JOB` in eigener Session (`SUCCEEDED`, Abruflauf `SUCCESS`, LILAM-Prozess geschlossen), systemischer Fehler im Job (Historie `FAILED` mit 20110, Abruflauf `FAILED`, LILAM-Prozess mit Status −1 geschlossen), Statussicht mit und ohne Job, Entfernen.

Nicht getestet: ein eingeschalteter Job im Zeitplan über mehrere Intervalle (Dauerbetrieb nur auf Anforderung).
