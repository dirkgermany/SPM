# Integrationsmatrix SPM ↔ LILAM

Stand: 2026-10-13. Geprüft gegen den LILAM-Branch `messwerte` (`LILAM_VERSION` v2.3, `docs/API_DE.md`, `rules/README.md`, `source/package/lilam.pks/.pkb`).

## Geprüfter LILAM-Stand

| Fähigkeit | Status im Branch `messwerte` | Nutzung in SPM |
| --- | --- | --- |
| `NEW_PROCESS`, `SERVER_NEW_PROCESS`, `CLOSE_PROCESS`, `FLUSH` | vorhanden | Abruflauf: `NEW_PROCESS` (In-Session) |
| `MARK_EVENT(p_processId, p_actionName, p_contextName, p_value, p_timestamp)` | vorhanden | Kurs, Quote-Alter, Zählwerte |
| Wert-EWMA je Action/Context, über Baseline Scope prozessübergreifend | vorhanden (`LILAM_BASELINES.AVG_VAL`, `VAL_COUNT`) | fortlaufender EWMA je Aktie |
| `VAL_MIN`, `VAL_MAX` (strikt `<` bzw. `>`, nur Trigger `MARK_EVENT`) | vorhanden | absolute Grenzen je Aktie |
| `VAL_EWMA_DEVIATION_PCT_UP` / `_DOWN` (`pct[|warmup[|alpha]]`, Vergleich mit EWMA **vor** der Messung) | vorhanden | Ausreißer nach oben/unten |
| `TIME_`-Operatoren (`TIME_MAX_DURATION_MS`, `TIME_EWMA_DEVIATION_PCT_*`, `TIME_MAX_GAP_SECONDS`, …) | vorhanden | Dauer der Provider-Aufrufe, Laufzeit |
| Regeln im In-Session-Modus über `p_groupName` | vorhanden | Scheduler-Lauf ohne Server/Dispatcher |
| `VAL_CROSS_*`, Hysterese, `DATA_STALE` | nicht vorhanden | nicht verwendet; Freshness über SPM-Watchdog |

## Identität der Messungen

| Element | Festlegung | Begründung |
| --- | --- | --- |
| Prozess | ein LILAM-Prozess je Abruflauf, Name `SPM_POLL` (`SPM_CONFIG.POLL_PROCESS_NAME`) | Prozess-ID ordnet Messungen einem Lauf zu |
| Betriebsart | In-Session (`NEW_PROCESS`) für Scheduler und manuellen Lauf | ein Lauf = eine Datenbanksession; kein Server/Dispatcher nötig |
| Gruppe | `STOCK_MONITORING` (`LILAM_GROUP`) | aktives Rule Set der Gruppe gilt auch im In-Session-Modus |
| Baseline Scope | `SPM` (`LILAM_BASELINE_SCOPE`) | EWMA läuft über alle Läufe weiter, auch für spätere APEX-Läufe mit demselben Scope |
| Kurs | `ACTION = SHARE_PRICE`, `CONTEXT = Symbol`, `p_value = Kurs` | eine Reihe je Aktie; immer mit Wert |
| Währung | eine Währung je Symbol (`SPM_INSTRUMENT.CURRENCY`); Quotes in anderer Währung werden verworfen | eine Reihe hat genau eine Einheit |
| Zeitpunkt | `p_timestamp = NULL` (jetzt) | die Zeitreihe misst den Abstand zwischen zwei neu gespeicherten Kursen; der Quote-Zeitpunkt steht in `SPM_PRICE` |
| Duplikate | nur neu gespeicherte Kurse erzeugen `SHARE_PRICE` | Doppelabrufe verändern den EWMA nicht und lösen keine doppelten fachlichen Alerts aus |

## Matrix

| # | Phase im Abruflauf | LILAM-Aufruf | ACTION / CONTEXT | Wert | Trigger → mögliche Regel | Erwartetes Verhalten |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Lauf beginnt | `NEW_PROCESS(SPM_POLL, …, p_procStepsToDo = aktive Symbole, p_groupName, p_baselineScope)` | Prozess | – | `PROCESS_START` → `ON_START` (optional) | Prozess in `LILAM_PROC`; `SPM_RUN.LILAM_PROCESS_ID` verweist darauf |
| 2 | Konfiguration und Symbole gelesen | `INFO` | – | – | `LOGGING` | Startmeldung mit Anzahl und Filter |
| 3 | REST-Aufruf je Symbol | `TRACE_START` / `TRACE_STOP` | `PROVIDER_CALL` / Symbol | Dauer (ms) | `TRACE_STOP` → `TIME_MAX_DURATION_MS`, `TIME_EWMA_DEVIATION_PCT_UP` | langsamer Provider wird erkannt |
| 4 | HTTP-Status, Timeout, JSON, Pflichtfelder | `WARN "<Symbol>: <OUTCOME> (HTTP n) <Diagnose>"` | – | – | `LOGGING` → `LOG_CONTAINS` z. B. `WARN|TIMEOUT` | Symbol scheitert, Lauf geht weiter |
| 5 | Währung, Wertebereich, Zeitstempel | `WARN` bei `INVALID`/`STALE`; `MARK_EVENT` mit Alter | `QUOTE_AGE_SEC` / Symbol | Alter des Quotes in s | `MARK_EVENT` → `VAL_MAX` | veraltete Daten werden sichtbar, auch wenn der Kurs verworfen wird |
| 6 | Kurs speichern (Idempotenz) | `INFO` bei Duplikat | – | – | – | `SPM_PRICE` eindeutig je Instrument und Quote-Zeitpunkt |
| 7 | Kurs melden | `MARK_EVENT` | `SHARE_PRICE` / Symbol | Kurs | `MARK_EVENT` → `VAL_MIN`, `VAL_MAX`, `VAL_EWMA_DEVIATION_PCT_UP/_DOWN` | Alert in `LILAM_ALERTS` + `DBMS_ALERT`-Signal an den Handler |
| 7a | Symbol erledigt | `PROC_STEP_DONE` | Prozess | – | `PROCESS_UPDATE` → `STEPS_LEFT_HIGH` (selten sinnvoll) | Fortschritt |
| 8 | Zählwerte des Laufs | `MARK_EVENT` je Kennzahl | `POLL_RESULT` / `REQUESTED`, `FETCHED`, `FAILED`, `STORED`, `DUPLICATE` | Anzahl | `MARK_EVENT` → `VAL_MAX` auf `FAILED`, `VAL_MIN` auf `STORED` | fehlerhafte Läufe ohne Auswertung der Logs erkennen |
| 9 | Quotenlimit | `ERROR "… vorzeitig beendet"`, `CLOSE_PROCESS(…, -1 oder 2)` | – | – | `LOGGING` → `SEVERITY ERROR`; `PROCESS_STOP` → `STATUS_EQUALS` | Lauf endet geordnet, restliche Symbole werden nicht angefragt |
| 10 | Abschluss | `CLOSE_PROCESS(info, status)`; Status 1 = Erfolg, 2 = teilweise, −1 = fehlgeschlagen | Prozess | – | `PROCESS_STOP` → `STATUS_EQUALS -1`, `TIME_MAX_RUNTIME_EXCEEDED` | Zusammenfassung in `LILAM_PROC.INFO` |
| 11 | Systemischer Fehler / unerwartete Ausnahme | `ERROR` (mit Backtrace), `CLOSE_PROCESS(…, -1)`, dann `RAISE` | Prozess | – | `LOGGING` → `SEVERITY ERROR`; `PROCESS_STOP` → `STATUS_EQUALS -1` | `DBMS_SCHEDULER` registriert den Lauf als fehlgeschlagen |
| 12 | Lauf überlappt | kein LILAM-Prozess; `SPM_RUN.STATUS = SKIPPED` | – | – | – | kein doppelter Abruf |
| 13 | Job läuft gar nicht | – (LILAM sieht kein Signal) | – | – | – | Watchdog (geplant) vergleicht `SPM_RUN` und Scheduler-Historie mit dem Intervall |

## Hinweise und offene Punkte aus der LILAM-Prüfung

Diese Punkte betreffen LILAM selbst. SPM ändert LILAM nicht; die Punkte sind für das LILAM-Projekt notiert.

1. **Rechte:** `docs/setup.md` nennt `DBMS_PIPE` und `DBMS_ALERT` nur für den entkoppelten Betrieb. Der Package Body referenziert beide statisch; ohne die Rechte kompiliert LILAM nicht. Im In-Session-Modus mit Gruppe signalisiert LILAM Alerts außerdem über `DBMS_ALERT`. SPM vergibt beide Rechte deshalb immer.
2. **Drosselung je Session (in LILAM gelöst):** Bis LILAM-Commit `1bfd6ec` merkte sich LILAM die Sperre für `throttle_seconds` nur in der Datenbanksession und ohne Context; jeder Scheduler-Lauf hätte erneut gemeldet, und ein Alert für ein Symbol hätte bei Regeln ohne Context andere Symbole gesperrt. Seit `1bfd6ec` liegt die Sperre dauerhaft in `LILAM_ALERT_LOCKS`, Schlüssel Gruppe, Scope bzw. Prozess, Regel, Action und Context. SPM benötigt mindestens diesen Stand; nach LILAM-Änderungen `install/install.sql` erneut ausführen, damit der Body im Schema SPM neu kompiliert wird. Der Vorgänger für `PRECEDED_BY` gilt weiterhin je Session (in SPM nicht verwendet).
3. **Alert-Details:** `LILAM_ALERTS` speichert weder Messwert noch Schwelle oder Baseline. Die Alert-Seite kann sie über `PROCESS_ID`, `ACTION_NAME`, `CONTEXT_NAME` und `ACTION_COUNT` aus `_MON` (`USED_VALUE`, `USED_VALUE_EWMA`) und aus dem Rule Set ergänzen. Zu verifizieren, sobald ein Alert ausgelöst wurde.
4. **`TIME_MAX_GAP_SECONDS` über Läufe:** Ob der Abstand zum vorherigen Event auch über Prozessgrenzen gemessen wird (Baseline Scope), ist noch zu prüfen. Unabhängig davon erkennt LILAM einen ausbleibenden Lauf nicht; dafür ist der SPM-Watchdog vorgesehen.
5. **Regeln je Symbol (umgesetzt):** Grenzwerte je Aktie sind Regeln mit `context = Symbol`. `spm_rules.publish` erzeugt das Rule Set aus `SPM_RULE` und `SPM_CONFIG`, trägt es als neue Version in `LILAM_RULES` ein und aktiviert es mit `SERVER_UPDATE_RULES`. Ein neuer Scheduler-Lauf (neue Session) lädt es sofort, eine laufende Session spätestens nach 15 Sekunden. Warm-up und Alpha wirken je Action und Context, also je Aktie. Details: [rules/README.md](../rules/README.md).

## Umsetzungsstand

| Schritt laut Spezifikation | Stand |
| --- | --- |
| 1. LILAM-Stand prüfen | erledigt (siehe oben) |
| 2. Integrationsmatrix | dieses Dokument |
| 3. Provider-Abstraktion, Mock, Schema, manueller Lauf | umgesetzt: `spm_prov`, `spm_prov_mock`, `install/20_tables.sql`, `spm_poll.run` |
| 4. Lebenszyklus, Trace, Logging, Fehlerabschluss | umgesetzt in `spm_poll` |
| 5. Regeln gegen die LILAM-Erweiterung | umgesetzt: `SPM_RULE`, `spm_rules` (Pflege, Generator, Veröffentlichen), technische Regeln, Demo-Rule-Set |
| 6. Scheduler, Freshness/Watchdog, APEX | offen |
| 7. Tests | `test/run_tests.sql` (Mock): 201 Prüfungen bestanden, siehe [Testbericht](testbericht.md) |
