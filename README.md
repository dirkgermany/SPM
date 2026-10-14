# SPM – Stock Price Monitoring

Referenzanwendung (Arbeitstitel *LILAM Stock Watch*) für Oracle Database 26ai Free, APEX und ORDS.
SPM ruft Aktienkurse über einen austauschbaren REST-Provider ab, speichert sie in einer eigenen
fachlichen Kurshistorie und nutzt [LILAM](https://github.com/dirkgermany/LILAM) als Framework für
Prozessüberwachung, Messwerte und regelbasierte Alerts – sowohl für die Kursentwicklung als auch für
die technische Ausführung der Anwendung selbst.

> **Kein Anlageprodukt.** SPM ist ein technischer Monitoring-Demonstrator, keine Anlageberatung und
> keine Handelsplattform. Kursdaten können je nach Provider, Lizenz und Tarif verzögert oder begrenzt sein.

## Verhältnis zu LILAM

SPM und LILAM sind getrennte Projekte. SPM verwendet LILAM als Framework, baut dessen Funktionalität
aber nicht nach und verändert LILAM nicht.

- Eigenes Datenbankschema für SPM, getrennt von den LILAM-Tabellen.
- Benötigter LILAM-Stand: `MARK_EVENT` mit numerischem `p_value`, Wert-EWMA und `VAL_`-Regeln
  (derzeit LILAM-Branch `messwerte`, noch nicht in `main`).

## Verzeichnisse

| Verzeichnis      | Inhalt |
|------------------|--------|
| `install/`       | Schema, Grants, Network ACL, Installation/Deinstallation |
| `source/`        | PL/SQL-Pakete: Provider-Adapter, Kursverarbeitung, Scheduler, LILAM-Instrumentierung |
| `rules/`         | LILAM-Rule-Set-Beispiele |
| `apex/`          | APEX-Anwendungsexport |
| `test/`          | Automatisierte Tests; `test/fixtures/` enthält Mock-Provider-Antworten |
| `docs/`          | Architektur, Integrationsmatrix, Installation, Sicherheit, Betrieb |

## Stand

- Anwendungsschema, Mock-Provider und manueller Abruflauf (`spm_poll.run`) mit LILAM-Instrumentierung:
  ein In-Session-Prozess je Lauf, Trace je Provider-Aufruf, Kurs als `MARK_EVENT(p_value)`.
- Automatisierte Tests mit Mock-Antworten (`test/run_tests.sql`).
- Regeln je Aktie (Grenzen, EWMA-Ausreißer) und technische Regeln: `spm_rules` erzeugt und aktiviert das LILAM Rule Set,
  siehe [rules/README.md](rules/README.md).
- Scheduler-Job `spm_job` (nicht automatisch eingeschaltet) und Statussicht `SPM_JOB_STATUS_V`.
- Watchdog `spm_watchdog` (eigener Job, Schweige-Regeln über `LILAM.CHECK_SILENCE`, Zustand des Abruf-Jobs).
- Offen: Alert-Consumer, APEX-Anwendung,
  REST-Adapter für einen echten Provider.

Dokumentation: [Installation](docs/installation.md), [Integrationsmatrix](docs/integrationsmatrix.md).
