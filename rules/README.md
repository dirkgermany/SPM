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

## Alerts

Alerts schreibt LILAM in `LILAM_ALERTS` (Status `PENDING`) und signalisiert sie über `DBMS_ALERT` auf dem Kanal `SPM_CONFIG.RULE_HANDLER` (Standard `SPM_ALERT`). Einen Consumer, der sie zustellt, gibt es in SPM noch nicht. Messwert und EWMA zum Alert stehen in `LILAM_MON` (`USED_VALUE`, `USED_VALUE_EWMA`), zuzuordnen über `PROCESS_ID`, `ACTION_NAME`, `CONTEXT_NAME` und `ACTION_COUNT`.

## Nicht vorhandene Operatoren

`VAL_CROSS_BELOW` / `VAL_CROSS_ABOVE`, Hysterese und `DATA_STALE` gibt es in LILAM nicht; SPM verwendet sie nicht. Ausbleibende Abrufläufe erkennt LILAM nicht (keine zeitgesteuerte Prüfung), dafür ist der SPM-Watchdog vorgesehen.
