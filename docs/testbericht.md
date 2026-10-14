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

## 2026-10-14: Watchdog

LILAM-Checkout `messwerte` mit `cc6431c` (Erkennung ausbleibender Signale, Zeitfenster, `LILAM_ALERT_STATE`).

| Schritt | Ergebnis |
| --- | --- |
| Neuinstallation mit neuem LILAM-Stand, vorhandene Tests | 226 bestanden; Anpassung: Testaufräumen nutzt `LILAM_ALERT_STATE` statt `LILAM_ALERT_LOCKS` |
| `install/install.sql` mit Watchdog | drei Befunde behoben: `ALTER TABLE … ADD IF NOT EXISTS` für Spalten nicht angenommen (ORA-02000, ersetzt durch PL/SQL-Block); vorhandenes JSON-Constraint meldet ORA-40664 statt ORA-02264; `SPM_TEST` wird durch geänderte Abhängigkeiten ungültig und gehört nicht in die Installationsprüfung |
| `test/run_tests.sql`, Lauf 1 | 259 bestanden, 0 fehlgeschlagen |
| `test/run_tests.sql`, Lauf 2 | 259 bestanden, 0 fehlgeschlagen |
| Nachkontrolle | Konfiguration zurückgesetzt (`RULE_POLL_SILENCE_SEC` 2700, `POLL_JOB_NAME`, `LILAM_GROUP`), keine Jobs, keine Testgruppen in `LILAM_RULES`/`LILAM_ALERT_STATE`; Alerts der Watchdog-Testgruppe genau `SPM-POLL-SILENT`, `TSTOK-SILENT`, `TSTE-SILENT`, `SPM-POLLJOB-BAD` (je 1), kein `TSTB-SILENT` |
| `install/50_demo_data.sql` | Demo-Rule-Set Version 2 mit Schweige-Regeln für SAP (Xetra-Zeiten) und AAPL (NASDAQ-Zeiten, `America/New_York`) |

Neue Fälle: Eingabeprüfung der Schweige-Regel (Schweigezeit, Zeitfenster ohne Schweigezeit oder Zeitzone, ungültige Tage über `CHECK_RULE_SET`, kein JSON), Regeln im erzeugten Rule Set, kein Alarm beim Einschalten, Alarm nach Ablauf (Prozess ohne `PROCESS_ID` mit `PROCESS_NAME`, Reihe mit Context), offenes und geschlossenes Zeitfenster, Signale beenden das Schweigen, Zustand des Abruf-Jobs (fehlt, ausgeschaltet, in Ordnung nach Lauf), Watchdog-Lauf mit `SPM-POLLJOB-BAD`, Watchdog als Scheduler-Job.

Nicht getestet: eingeschaltete Jobs über mehrere Intervalle (Dauerbetrieb nur auf Anforderung), Ausfall beider Jobs (dokumentierte Grenze), `SPM-RUN-HANG` mit echtem hängendem Lauf.

## 2026-10-14: Zustellung per E-Mail (Consumer)

| Schritt | Ergebnis |
| --- | --- |
| Erster Versuch | Datenbank nicht erreichbar (ORA-12541, Neustart des Notebooks); Stand lokal committet |
| `install/install.sql` mit `spm_notify`, `SPM_NOTIFICATION` | fehlerfrei |
| `test/run_tests.sql`, Lauf 1 | 281 bestanden, 3 fehlgeschlagen: Regelangaben im Mailtext leer. Ursache: mehrere `JSON_VALUE` mit `PASSING` auf dieselbe Spalte in einer Abfrage lieferten zusammen mit dem Pfad `."_comment"` durchweg NULL, einzeln korrekt. Behoben mit `JSON_TABLE` |
| `test/run_tests.sql`, Lauf 2 und 3 | je 284 bestanden, 0 fehlgeschlagen |
| Nachkontrolle | Konfiguration zurückgesetzt (`MAIL_*` leer bzw. Standard), keine Jobs, keine Testgruppen, keine offenen Alerts in `STOCK_MONITORING` |
| Netzwerk-ACL | `SPM` und `LILAM_TEST` haben keine Host-ACE; für echten Versand ist `install/01_admin_network_acl.sql` nötig |

Neue Fälle: Mailtext eines Grenzwert-Alerts (Symbol, Instrument, Kurs mit Währung, Regel mit Schwelle, Prozess) und eines Schweige-Alerts ohne Prozess; ohne Absender/Empfänger bleiben Alerts offen; Transport MOCK verarbeitet alle offenen Alerts genau der konfigurierten Gruppe und protokolliert sie; SMTP-Fehler (keine ACL bzw. kein Dienst) wird als `ERROR` mit Meldung verbucht; Consumer-Lauf als LILAM-Prozess mit `NOTIFY_RESULT`; Zustell-Job anlegen.

Nicht getestet: echter Versand per SMTP (erst nach ACL, Absender/Empfänger und Freigabe durch Dirk), Zustell-Job im Dauerbetrieb.

## 2026-10-14: Echter Testversand

Freigabe durch Dirk; ACL (`install/01_admin_network_acl.sql`), `MAIL_FROM`/`MAIL_TO` und Zustell-Job von Dirk eingerichtet.

| Schritt | Ergebnis |
| --- | --- |
| Test-Instrument `MAILTEST` (Mock, Kurs 150, Obergrenze 100), Rule Set v3, manueller Abruf | Alert 120 `MAILTEST-MAX` in `STOCK_MONITORING`, vom laufenden Zustell-Job sofort aufgenommen; Mailtext vollständig |
| Versand 1 | `ERROR` ORA-30205: `UTL_ENCODE.MIMEHEADER_ENCODE` kennt den Zeichensatznamen `UTF-8` nicht. Es ging keine Mail hinaus. Behoben: Betreff als RFC-2047-Encoded-Words selbst kodiert, Text und Betreff unabhängig vom DB-Zeichensatz nach UTF-8 |
| Aktualisierung | Zustell-Job belegt `spm_notify` bis zu 60 min; neu: `spm_job.stop_job`. Job ausgeschaltet/angehalten, neu installiert, Tests 284 bestanden, Job wieder eingeschaltet |
| Versand 2 (Alert 120 erneut `PENDING`) | `SENT` um 10:25:34, Alert `PROCESSED`; Empfang durch Dirk zu bestätigen |
| Aufräumen | `MAILTEST` deaktiviert, Regel entfernt, Rule Set v4 ohne `MAILTEST` |

Neu in den Tests: Sie brechen ab, wenn SPM-Jobs eingeschaltet sind oder laufen (ein laufender Zustell-Job würde die vorübergehend geänderte Konfiguration der Tests lesen und könnte echte Mails an Testadressen schicken).

## 2026-10-14: HTML-Mail

| Schritt | Ergebnis |
| --- | --- |
| Erster Installationsversuch | `SPM_NOTIFY` ungültig: SQLcl hielt die HTML-Entities (`&#9650;`, `&middot;`) für Substitutionsvariablen („Ersetzung abgebrochen“), der Body wurde nicht kompiliert. Behoben: `set define off` in `install/30_packages.sql` |
| `test/run_tests.sql` | 293 bestanden, 0 fehlgeschlagen (neu: Farben je Severity und Abweichung, Überschreitung in Prozent, Regel in Worten, Schweige-Block) |
| Vorschau | `docs/beispiele/mail_grenzwert.html` (Alert 120, `MAILTEST-MAX`) |
| Zustell-Job | für Installation und Tests ausgeschaltet, danach wieder eingeschaltet |

## 2026-10-14: APEX-Anwendung

| Schritt | Ergebnis |
| --- | --- |
| Datenbank-Seite (`26_apex_views.sql`, `spm_apex`) | installiert; Sichten liefern Daten; Tests 296 bestanden |
| Aufbau mit `apex/build/spm_app_build.sql` | Import fehlerfrei (APEX 24.2) |
| Anmeldung | scheiterte zunächst: Anmeldeseite stammte aus einer abgelaufenen Sitzung („Your session has ended“), nach Neuladen erfolgreich |
| Dashboard, Watchlist | im Browser geprüft, Darstellung korrekt |
| Links zu Instrument/Formularen/Alert | „Session state protection violation“: Seitenschutz „D“ bedeutet „kein Aufruf per URL“. Behoben: Standard „C“ (Prüfsumme) |
| Neuimport | beendete zunächst die Sitzung; seitdem `apex_application_install.set_keep_sessions(true)` |
| IR-Hilfe | Actions → Hilfe ohne Rückweg; ausgeblendet |

Noch nicht im Browser geprüft: Instrument mit Diagramm, Formulare (Instrument, Regel), Regeln veröffentlichen, Alert-Vorschau, Monitoring, Administration (Aktionen mit Wirkung nur nach Absprache).

Durchsicht aller Seiten im Browser (nur lesend): alle zehn Seiten funktionieren. Befunde und Korrekturen:
- Alpha und Prozentwerte unter 1 ohne führende Null („,2“): Formatmaske in der Regelliste, `spm_apex.fmt_num` im Regel-Formular.
- Testprozesse erschienen in Monitoring und Dashboard (gleiche Prozessnamen wie echte Läufe). Tests verwenden jetzt `SPMTEST_POLL`, `SPMTEST_WATCHDOG`, `SPMTEST_NOTIFY`; die Laufliste blendet Läufe mit Symbolfilter `TST*` aus.
- Tests danach: 296 bestanden. Das Kursdiagramm ist noch ungeprüft (SAP hat erst einen Kurs).

Nachtrag APEX: `apex_application_install.set_keep_sessions(true)` wieder entfernt. Die beibehaltene Sitzung konnte ihren Zustand nach dem Neuimport nicht mehr entschlüsseln (ORA-28817 in `WWV_FLOW_CRYPTO`); Folgen: leere Watchlist, Formular mit falschem Datensatz. Nach einem Neuaufbau meldet man sich neu an. Neu: Button „Startseite“ in der Navigationsleiste.

## 2026-10-14: Dringlichkeit, Spam-Schutz, Simulation

| Schritt | Ergebnis |
| --- | --- |
| Dringlichkeit Hinweis/Warnung/Alarm/Kritisch (Matrix in `rules/README.md`), vorhandene Werte umgestellt | Tests 296 bestanden |
| Spam-Schutz `MAIL_MAX_PER_HOUR` (12), `MAIL_MIN_INTERVAL_SECONDS` (10), nur beim SMTP-Versand | Mails im Abstand von genau 10 s |
| `demo/simulate_prices.sql`: MAILTEST entfernt, 6 Aktien, 64 Abrufläufe (Auslöser SIMULATION) | Lauf 30 PARTIAL (HTTP 503 bei MSFT, gewollt); 6 Alerts: SAP-MAX, SIE-MIN (Alarm), AAPL-UP, SPM-RUN-PARTIAL, SPM-POLL-FAILED (Warnung), SPM-WATCHDOG-SILENT (Alarm, berechtigt: Watchdog-Job aus) |
| Zustellung | 6 Mails SENT (18:47:33 bis 18:48:23) |
| Befunde | technische Alerts mit Grenzwert-Operator hießen „Grenzwert“, Regeltexte mit Einheiten statt Werten („(s)“), „2.5 %“ mit Punkt, „EWMA“ unverständlich. Behoben: Art Grenzwert/Ausreißer/Schweigen nur für Aktienkurse, sonst „Technik“; Texte wie „Kein Abruflauf seit 45 min“, „Kurs mehr als 2,5 % über dem gleitenden Mittel“. Rule Set Version 6; Tests 296 bestanden |
