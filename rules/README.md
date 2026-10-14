# Regeln

SPM pflegt keine Rule Sets von Hand. Die Grenzwerte je Aktie stehen in `SPM_RULE`, die technischen Grenzwerte in `SPM_CONFIG` (`RULE_*`). `spm_rules.publish` erzeugt daraus das LILAM Rule Set, prüft es mit `LILAM.CHECK_RULE_SET`, trägt es als neue Version in `LILAM_RULES` ein und aktiviert es mit `LILAM.SERVER_UPDATE_RULES` für die Gruppe `SPM_CONFIG.LILAM_GROUP`. Ist das erzeugte Rule Set mit dem aktiven identisch, entsteht keine neue Version.

```sql
begin
    spm_rules.save_rule('SAP', p_val_min => 80, p_val_max => 120,
                        p_ewma_pct_up => 3, p_ewma_pct_down => 3, p_ewma_warmup => 5, p_ewma_alpha => 0.2);
    commit;
    dbms_output.put_line('aktive Version ' || spm_rules.publish);
end;
/
```

Beispiel: [spm_rules_demo.json](spm_rules_demo.json), erzeugt aus `install/50_demo_data.sql`.

## Regeln je Aktie (`SPM_RULE`)

Alle Regeln: Trigger `MARK_EVENT`, Action `SHARE_PRICE`, Context = Symbol. Nur aktive Instrumente mit aktiver Regelkonfiguration.

| Regel-ID | Operator | Wert | Spalten | Löst aus, wenn |
| --- | --- | --- | --- | --- |
| `<Symbol>-MIN` | `VAL_MIN` | Grenze | `VAL_MIN`, `SEVERITY_LIMIT` | Kurs < Grenze (die Grenze selbst nicht) |
| `<Symbol>-MAX` | `VAL_MAX` | Grenze | `VAL_MAX`, `SEVERITY_LIMIT` | Kurs > Grenze |
| `<Symbol>-UP` | `VAL_EWMA_DEVIATION_PCT_UP` | `pct[|warmup[|alpha]]` | `EWMA_PCT_UP`, `EWMA_WARMUP`, `EWMA_ALPHA`, `SEVERITY_EWMA` | Kurs > EWMA + \|EWMA\| · pct / 100 |
| `<Symbol>-DOWN` | `VAL_EWMA_DEVIATION_PCT_DOWN` | wie oben | `EWMA_PCT_DOWN`, … | Kurs < EWMA − \|EWMA\| · pct / 100 |

- Verglichen wird mit dem EWMA **vor** dem aktuellen Kurs; während des Warm-ups löst die Regel nicht aus.
- Warm-up und Alpha gelten für die Wertreihe des Symbols (LILAM sucht sie je Action und Context). Ohne Angabe: LILAM-Standard Warm-up 3, Alpha 0,1. `_UP` und `_DOWN` erhalten immer dieselben Werte.
- Der EWMA läuft über alle Abrufläufe weiter (Baseline Scope `SPM_CONFIG.LILAM_BASELINE_SCOPE`). Eine Änderung von Warm-up oder Alpha wirkt auf die laufende Reihe, ohne sie neu zu beginnen.
- `THROTTLE_SECONDS` (Standard 3600): Nach einem Alert schweigt dieselbe Regel für dasselbe Symbol so lange. Die Sperre speichert LILAM in `LILAM_ALERT_LOCKS`; sie gilt über Abrufläufe und Sessions hinweg (ab LILAM `1bfd6ec`). Das ist keine Hysterese: Nach Ablauf meldet der nächste Kurs außerhalb des Bandes erneut.

## Schweige-Regel je Aktie

| Regel-ID | Operator | Wert | Spalten | Löst aus, wenn |
| --- | --- | --- | --- | --- |
| `<Symbol>-SILENT` | `TIME_MAX_SILENCE_SECONDS` | Sekunden | `SILENCE_SECONDS`, `SILENCE_WINDOWS`, `SILENCE_TIME_ZONE`, `SEVERITY_SILENCE` | seit so vielen Sekunden kein **neu gespeicherter** Kurs (Doppelabrufe zählen nicht) |

- `SILENCE_WINDOWS` ist ein JSON-Array im LILAM-Format, z. B. Handelszeiten: `[{"days":"MON-FRI","from":"09:00","to":"17:30"}]` mit `SILENCE_TIME_ZONE` `Europe/Berlin`. Außerhalb der Fenster wird nicht gemeldet; beim Öffnen eines Fensters zählt das Schweigen neu. Feiertage kennt LILAM nicht: An Feiertagen die Regel deaktivieren oder Meldungen hinnehmen.
- `save_rule` lässt die Zeitfenster vor dem Speichern von `LILAM.CHECK_RULE_SET` prüfen.
- Geprüft wird nicht beim Signal, sondern zeitgesteuert durch `LILAM.CHECK_SILENCE` (siehe [Watchdog](#watchdog)).

## Technische Regeln (`SPM_CONFIG`)

Drosselung aller technischen Regeln: `RULE_TECH_THROTTLE_SECONDS` (Standard 3600). Ein leerer Grenzwert lässt die Regel weg.

| Regel-ID | Trigger / Action / Context | Operator | Wert | Bedeutung |
| --- | --- | --- | --- | --- |
| `SPM-RUN-FAILED` | `PROCESS_STOP` / `SPM_POLL` | `STATUS_EQUALS` | `-1` | Abruflauf fehlgeschlagen (ERROR) |
| `SPM-RUN-PARTIAL` | `PROCESS_STOP` / `SPM_POLL` | `STATUS_EQUALS` | `2` | Abruflauf teilweise erfolgreich (WARN) |
| `SPM-RUN-SLOW` | `PROCESS_STOP` / `SPM_POLL` | `TIME_MAX_RUNTIME_EXCEEDED` | `RULE_RUN_MAX_MS` | Lauf dauert zu lange |
| `SPM-PROVIDER-SLOW` | `TRACE_STOP` / `PROVIDER_CALL` | `TIME_MAX_DURATION_MS` | `RULE_PROVIDER_CALL_MAX_MS` | Provider-Aufruf dauert zu lange |
| `SPM-POLL-FAILED` | `MARK_EVENT` / `POLL_RESULT` / `FAILED` | `VAL_MAX` | `RULE_POLL_FAILED_MAX` | mehr fehlerhafte Symbole je Lauf |
| `SPM-QUOTE-AGE` | `MARK_EVENT` / `QUOTE_AGE_SEC` | `VAL_MAX` | `RULE_QUOTE_AGE_MAX_SEC` | Quote zu alt; standardmäßig aus (Wochenende) |
| `SPM-POLL-SILENT` | `PROCESS_START` / `SPM_POLL` | `TIME_MAX_SILENCE_SECONDS` | `RULE_POLL_SILENCE_SEC` (2700) | kein Abruflauf gestartet (ERROR) |
| `SPM-RUN-HANG` | `PROCESS_UPDATE` / `SPM_POLL` | `TIME_MAX_SILENCE_SECONDS` | `RULE_RUN_HANG_SEC` (600) | laufender Abruflauf sendet nichts (ERROR) |
| `SPM-WATCHDOG-SILENT` | `PROCESS_START` / `SPM_WATCHDOG` | `TIME_MAX_SILENCE_SECONDS` | `RULE_WATCHDOG_SILENCE_SEC` (1800) | kein Watchdog-Lauf gestartet (ERROR) |
| `SPM-POLLJOB-BAD` | `MARK_EVENT` / `POLL_JOB_HEALTH` | `VAL_MIN` | `1` | Abruf-Job fehlt, ist ausgeschaltet, defekt oder zuletzt fehlgeschlagen (ERROR) |

## Watchdog

LILAM erkennt das Schweigen, SPM plant die Prüfung ein und überwacht die Prüfer.

- **Watchdog-Job** (`spm_job.create_watchdog_job`, Standard alle 5 Minuten): Jeder Lauf ist ein LILAM-Prozess `SPM_WATCHDOG`. Er ruft `LILAM.CHECK_SILENCE(<LILAM_GROUP>)` auf und meldet den Zustand des Abruf-Jobs aus `SPM_JOB_STATUS_V` als `POLL_JOB_HEALTH` (1/0); bei 0 steht der Grund als WARN im LILAM-Log.
- **Zweiter Prüfer:** Auch jeder Abruflauf ruft am Ende `CHECK_SILENCE` auf. Fällt der Watchdog-Job aus, meldet der Abruf-Job `SPM-WATCHDOG-SILENT`; fällt der Abruf-Job aus, meldet der Watchdog `SPM-POLL-SILENT` und `SPM-POLLJOB-BAD`. Mehrere Prüfer erzeugen nur einen Alert.
- **Grenzen:** Fallen beide Jobs aus (oder ist das Schema gesperrt), meldet niemand etwas; das zeigt nur `SPM_JOB_STATUS_V` bzw. das Dashboard. Ein Schweigen wird bis zu einem Prüfintervall verspätet gemeldet; die Schweigezeiten müssen deutlich über den Intervallen liegen. Ein Abruflauf, der ohne `CLOSE_PROCESS` endet (Session abgebrochen), gilt für `SPM-RUN-HANG` als schweigend, bis die Regel entfernt wird. Bei Wiederkehr der Signale gibt es keine Entwarnung.
- Den Watchdog nur zusammen mit dem Abruf-Job einschalten: Ist der Abruf-Job bewusst aus, meldet der Watchdog das (gedrosselt) als Fehler.

## Alerts

Alerts schreibt LILAM in `LILAM_ALERTS` (Status `PENDING`) und signalisiert sie über `DBMS_ALERT` auf dem Kanal `SPM_CONFIG.RULE_HANDLER` (Standard `SPM_ALERT`). Einen Consumer, der sie zustellt, gibt es in SPM noch nicht. Messwert und EWMA zum Alert stehen in `LILAM_MON` (`USED_VALUE`, `USED_VALUE_EWMA`), zuzuordnen über `PROCESS_ID`, `ACTION_NAME`, `CONTEXT_NAME` und `ACTION_COUNT`.

## Nicht vorhandene Operatoren

`VAL_CROSS_BELOW` / `VAL_CROSS_ABOVE` und Hysterese gibt es in LILAM nicht; SPM verwendet sie nicht. Veraltete Daten deckt `TIME_MAX_SILENCE_SECONDS` ab (statt eines eigenen `DATA_STALE`).

Alerts der Schweige-Regeln haben in `LILAM_ALERTS` keine `PROCESS_ID` (außer `SPM-RUN-HANG`); bei `SPM-POLL-SILENT` und `SPM-WATCHDOG-SILENT` steht der Prozessname in `PROCESS_NAME`.
