# SPM – Arbeitsstand

Stand: 14.10.2026, spätabends. Übergabe für einen neuen Chat.

## Projekt

SPM (Stock Price Monitoring), Anwendung „SPM Stock Watch“: Referenzanwendung für Oracle 26ai Free, APEX und ORDS, die LILAM als Framework nutzt. Spezifikation: `C:\Users\dirk\Documents\LILAM\02_stock_price_monitoring_reference_application.md`.

- Repo: https://github.com/dirkgermany/SPM, lokal `C:\Users\dirk\Documents\SPM`, Arbeitsbranch `claude`, Basis `main`
- LILAM ist ein **getrenntes Projekt**; SPM installiert LILAM nur aus dem Checkout `C:\Users\dirk\Documents\LILAM\lilam` (Branch `main`, mindestens `87bf975` mit `RESET_BASELINE`) ins Schema SPM. LILAM wird aus SPM heraus nie geändert.
- Lizenz GPLv3. Sprache in Code-Kommentaren, Doku und Chat: Deutsch.

## Git / PRs

| PR | Inhalt | Stand |
| --- | --- | --- |
| #1–#16 | Schema, Mock, Abruflauf, Regeln, Scheduler, Watchdog, Zustellung, HTML-Mail, APEX, Dringlichkeit, Spam-Schutz, Twelve Data, Mail-Überarbeitung, Doku zu Twelve-Data-Symbolen (#8, #9), Historie löschen (#10, #11), Zeitzone als Auswahlliste (#12), Symbole an Links (#13), Schalter Aktiv (#14), Arbeitsstand (#15), Regeln veröffentlichen in der Administration (#16) | gemergt |

Nach einem Merge: `main` und `claude` per Fast-Forward auf `origin/main` nachziehen, `claude` pushen. `gh` liegt unter `C:\Program Files\GitHub CLI\gh.exe` (angemeldet als dirkgermany).

## Umgebung

- Datenbank in einer **Oracle-VM**; nach einem Windows-Neustart ist sie weg (ORA-12541), Dirk startet sie neu.
- PDB `FREEPDB1`, Schema `SPM` (angelegt mit `install/00_admin_create_schema.sql` als SYS), SMTP-ACL für `localhost:25` (`install/01_admin_network_acl.sql`).
- SQLcl: `C:\sqlcl\bin\sql.exe`, braucht `JAVA_HOME=C:\Program Files\Oracle\sqldeveloper\jdk\jre`; gespeicherte Verbindungen `spm`, `lilam_test`.
- APEX 24.2 / ORDS: `http://localhost:8080/ords/apex` (Workspace `SPM`, Benutzer `DIRK`), Admin `…/ords/apex_admin`. Anwendung 100: `http://localhost:8080/ords/r/spm/spm-stock-watch`.

## Arbeitsweise (wichtig)

- **Skripte mit `WHENEVER`/`EXIT` immer über die SQLcl-Kommandozeile**, nie über den SQLcl-MCP (der ist ein gemeinsamer Prozess aller Chats; ein `EXIT` legt ihn lahm, `connect` dort schaltet auch andere Chats um). Muster (Git Bash):
  `export JAVA_HOME='C:\Program Files\Oracle\sqldeveloper\jdk\jre'; echo exit | /c/sqlcl/bin/sql.exe -S -name spm @install/install.sql C:/Users/dirk/Documents/LILAM/lilam`
- **Vor Installation und Tests den Zustell-Job anhalten** (er belegt `spm_notify` bis zu 60 min; die Tests brechen ab, wenn SPM-Jobs eingeschaltet sind):
  `dbms_scheduler.disable('SPM_NOTIFY_JOB', force => true); dbms_scheduler.stop_job('SPM_NOTIFY_JOB');` – danach `spm_job.enable_job(spm_job.notify_job_name)`.
- Installation: `@install/install.sql <LILAM-Checkout>` (wiederholbar). Tests: `@test/run_tests.sql` (zuletzt **329 bestanden**). Live-Test Twelve Data (kostet Credits): `@test/live_twelvedata.sql "AAPL,SAP"`.
- APEX-Anwendung ändern: `apex/build/spm_app_build.sql` (im Ordner `apex/build` ausführen), danach Export `apex export -applicationid 100 -skipExportDate -expOriginalIds -overwrite-files` im Ordner `apex` → `apex/f100.sql`. **Nach jedem Neuaufbau muss Dirk sich neu anmelden** – einfach ansagen, keine Umgehung (`set_keep_sessions` führte zu ORA-28817).
- Browser-Fenster der App: Dirk vorher sagen, wenn ich darin klicke; er soll dann nicht parallel klicken. Strg+Umschalt+B schaltet das Fenster ein/aus.
- Echte Mails nur nach Absprache; Spam-Schutz ist aktiv (12/h, 10 s Abstand).
- Kein Dauertest ohne Anforderung.

## Aufbau (Kurzfassung)

| Teil | Dateien |
| --- | --- |
| Tabellen, Sichten, Grunddaten | `install/20_tables.sql`, `25_views.sql` (`SPM_JOB_STATUS_V`), `26_apex_views.sql`, `40_seed.sql` (`SPM_CONFIG`) |
| Abruf | `spm_prov` (Schnittstelle, `http_get`, `SPM_SECRET`), `spm_prov_mock`, `spm_prov_twelvedata`, `spm_poll` (Lauf = LILAM-In-Session-Prozess, Kurs als `MARK_EVENT(SHARE_PRICE, Symbol, Kurs)`) |
| Regeln | `spm_rules` (`SPM_RULE` → LILAM Rule Set, Gruppe `STOCK_MONITORING`, `publish`) |
| Jobs | `spm_job` (Abruf, Watchdog, Zustellung), `spm_watchdog` (`LILAM.CHECK_SILENCE`, `POLL_JOB_HEALTH`) |
| Zustellung | `spm_notify` (DBMS_ALERT-Consumer, HTML-Mail per UTL_SMTP, `SPM_NOTIFICATION`) |
| APEX | `spm_apex`, `apex/` (10 Seiten) |
| Tests | `test/spm_test.pkb`, `test/fixtures/mock_responses.sql` (eigene LILAM-Gruppen `SPMTEST_*`, Prozessnamen `SPMTEST_*`) |
| Doku | `README.md`, `docs/installation.md`, `docs/integrationsmatrix.md`, `docs/testbericht.md`, `rules/README.md`, `apex/README.md`, `docs/handbuch/handbuch.md` |

## Zustand der Datenbank (Schema SPM)

- Jobs: **Zustellung an** (`SPM_NOTIFY_JOB`), **Kursabruf und Watchdog angelegt, aber aus** (Schalter auf der Seite Administration). Solange der Watchdog aus ist, meldet jeder Abruflauf höchstens stündlich `SPM-WATCHDOG-SILENT`.
- Aktives Rule Set: `STOCK_MONITORING` / `SPM_RULES` Version 6.
- Demo-Daten aus `demo/simulate_prices.sql`: SAP, SIE, AAPL, BMW, ALV, MSFT (Mock) mit je 64 Kursen; 6 Alerts, alle zugestellt.
- `MAIL_FROM`/`MAIL_TO` von Dirk gesetzt (seine Adressen).
- Im technischen Monitoring stehen noch Prozesse alter Testläufe mit Namen `SPM_POLL` usw.; Dirk will sie vorerst behalten (ggf. für Präsentationen).

## Offene Punkte

1. Kein offener PR. Neue Arbeit auf `claude`, PR nach `main` auf Dirks Anweisung.
2. **Handbuch als PDF**: Text steht (`docs/handbuch/handbuch.md`). Es fehlen breite Bildschirmfotos (das Browser-Fenster ist nur ~800 px breit; Dirk zieht es breiter oder liefert Screenshots; vorhandene schmale Bilder liegen unversioniert in `docs/handbuch/img/`), dann HTML → PDF mit Edge headless (`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe --headless --print-to-pdf=…`). Python ist nicht installiert.
3. Entkoppelter LILAM-Modus (Server, Dispatcher) für APEX – später, wenn es ein echtes APEX-Board gibt.
4. Echte Kurse: Twelve Data ist angebunden (ACL, Schlüssel gesetzt, Live-Abruf geprüft). Gratistarif ohne deutsche Börsen → US-Notierungen in USD (`SAP`, `SIEGY`, `ALIZY`, `BMWKY`, `AAPL`, `MSFT`). Watchlist-Einträge legt Dirk in APEX an. AAPL hat er vom Mock auf Twelve Data umgestellt: vor dem Einschalten des Abrufs auf der Seite Instrument „Historie löschen“ (sonst EWMA-Ausreißer durch den Sprung Mock → echt). Danach Regeln anlegen, Abruf-Job einschalten.
5. Kurzhilfe über Listen: verworfen („zu viel“), stattdessen Handbuch.
6. **Seiten nach Joblauf auffrischen** – vorerst zurückgestellt (Dirk, 15.10.2026). Push von der DB zum Browser gibt es in APEX nicht. Vorschlag: Anzeigeseiten (Dashboard, Watchlist, Instrument, Alerts, Monitoring, nicht die Formulare) fragen z. B. alle 30 s per Ajax einen Änderungsstempel ab (letzter Lauf, letzter Alert, letzte Zustellung) und frischen nur bei Änderung ihre Regionen auf; Filter bleiben. Nebeneffekt: die APEX-Sitzung läuft nie in den Leerlauf-Timeout.

## Erkenntnisse

- APEX-Seitenschutz „D“ = kein Aufruf per URL; Seiten mit Parametern brauchen „C“ (Prüfsumme, setzt APEX bei eigenen Links automatisch).
- Mehrere `JSON_VALUE … PASSING` auf dieselbe Spalte in einer Abfrage lieferten mit dem Pfad `."_comment"` durchweg NULL → `JSON_TABLE`.
- `UTL_ENCODE.MIMEHEADER_ENCODE` kennt `UTF-8` nicht (ORA-30205) → Betreff selbst nach RFC 2047 kodiert.
- HTML-Entities (`&#9650;`) im PL/SQL-Quelltext: beim Kompilieren `set define off`, sonst bricht SQLcl die Ersetzung ab.
- `ALTER TABLE … ADD IF NOT EXISTS` für Spalten nimmt die DB nicht an; vorhandenes JSON-Constraint meldet ORA-40664.
- Lokale PL/SQL-Funktionen dürfen nicht in SQL-Anweisungen stehen (PLS-00231).
- Aus APEX angelegte Scheduler-Jobs erhalten die Zeitzone der ORDS-Sitzung (PST8PDT); Anzeige daher mit `at time zone 'Europe/Berlin'`.
- SQLcl in Git Bash braucht immer eine Eingabe per Pipe (`echo exit | sql …`), sonst „Unzulässige Funktion“.
- HTTPS aus der DB: `utl_http.set_wallet('system:')` (Zertifikate des Betriebssystems der VM) reicht, kein eigenes Wallet. ACL-Privileg `http` für `api.twelvedata.com:443`.
- Twelve Data meldet „Symbol nicht im Tarif“ mit HTTP 404 (nicht 403); Fehler kommen als `{"code":..,"status":"error"}`.
- PowerShell: `sql.exe` ohne `JAVA_HOME` öffnet die Java-Webseite; Argument `@datei.sql` in Anführungszeichen setzen.
