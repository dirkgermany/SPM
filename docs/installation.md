# Installation

Zielumgebung: Oracle Database 26ai Free (PDB `FREEPDB1`), SQLcl oder SQL*Plus. Die Skripte nutzen `CREATE TABLE IF NOT EXISTS` und setzen daher Oracle 23ai oder neuer voraus.

## 1. Schema anlegen (Administrator, einmalig)

```bash
sql sys@localhost:1521/FREEPDB1 as sysdba
```

```sql
@install/00_admin_create_schema.sql
```

Das Skript fragt das Kennwort für `SPM` ab und speichert es nicht. Es vergibt:

| Recht | Zweck |
| --- | --- |
| `CREATE SESSION, TABLE, SEQUENCE, VIEW, PROCEDURE, TYPE` | Anwendungsobjekte; LILAM legt seine Tabellen selbst an |
| `CREATE JOB` | Scheduler-Job für den Abruf, später LILAM-Server |
| `EXECUTE ON DBMS_PIPE`, `DBMS_ALERT` | von LILAM statisch referenziert; `DBMS_ALERT` signalisiert Alerts |
| `EXECUTE ON DBMS_LOCK` | Sperre gegen überlappende Abrufläufe |

Netzwerk-ACL und API-Schlüssel für den echten Provider: siehe [Kursanbieter Twelve Data](#kursanbieter-twelve-data).

## 2. SPM installieren (als `SPM`)

Optional eine gespeicherte SQLcl-Verbindung anlegen (das Kennwort gibst Du selbst ein):

```sql
conn -save spm -savepwd spm@localhost:1521/FREEPDB1
```

Installation mit dem Pfad zum LILAM-Checkout. SPM benötigt den LILAM-Stand mit `MARK_EVENT(p_value)` (derzeit Branch `messwerte`); das Skript bricht sonst ab.

```sql
@install/install.sql C:/Users/dirk/Documents/LILAM/lilam
```

Ablauf: LILAM-Pakete kompilieren und Life Check (`install/10_lilam.sql`), Tabellen (`20_tables.sql`), SPM-Pakete (`30_packages.sql`), Grunddaten (`40_seed.sql`). Die Installation ist wiederholbar.

Optional eine Demo-Watchlist mit simulierten Kursen und Beispielregeln (veröffentlicht das Rule Set):

```sql
@install/50_demo_data.sql
```

## 3. Testen

```sql
@test/run_tests.sql
```

Die Tests arbeiten nur mit dem Mock-Provider und den Symbolen `TST*`.

## 4. Manueller Abruflauf

```sql
set serveroutput on
declare
    l_run_id number;
begin
    l_run_id := spm_poll.run('MANUAL');
    dbms_output.put_line('Lauf ' || l_run_id);
end;
/
select * from spm_run order by run_id desc fetch first 5 rows only;
```

`spm_poll.run` committet je Symbol. Der LILAM-Prozess des Laufs steht in `SPM_RUN.LILAM_PROCESS_ID`.

## Deinstallation

```sql
@install/uninstall.sql      -- Pakete; Tabellen nur mit SPM_DROP_DATA = 'J'
```

LILAM entfernt `<LILAM>/source/uninstall.sql`, das Schema ein Administrator mit `DROP USER SPM CASCADE`.

## Regeln veröffentlichen

Nach Änderungen an `SPM_RULE` oder den `RULE_*`-Werten in `SPM_CONFIG`:

```sql
exec spm_rules.publish
```

Details: [rules/README.md](../rules/README.md).

## LILAM aktualisieren

SPM installiert LILAM in das eigene Schema. Nach einer Änderung im LILAM-Checkout `install/install.sql` erneut ausführen, damit der Body im Schema SPM neu kompiliert wird. Laufende SPM-Jobs vorher anhalten (`spm_job.disable_job` und `spm_job.stop_job`, je Job), sonst wartet das Kompilieren auf das Ende ihres Laufs; danach wieder einschalten. Die Tests (`test/run_tests.sql`) laufen nur, wenn kein SPM-Job eingeschaltet ist. Skripte mit `WHENEVER`/`EXIT` über die SQLcl-Kommandozeile ausführen, nicht über einen SQLcl-MCP-Server: `EXIT` beendet dessen Skript-Engine.

## Abruf-Job (DBMS_SCHEDULER)

Die Installation legt den Job **nicht** an: Ein eingeschalteter Job ruft dauerhaft Kurse ab.

```sql
exec spm_job.create_job                 -- Name und Intervall aus SPM_CONFIG (SPM_POLL_JOB, 15 min), ausgeschaltet
exec spm_job.enable_job                 -- einschalten: erster Lauf sofort, dann im Intervall
exec spm_job.create_job(p_interval_minutes => 5)   -- Intervall ändern (Job wird dabei ausgeschaltet)
exec spm_job.run_now                    -- einmal sofort in eigener Session
exec spm_job.disable_job                -- ausschalten; ein laufender Abruf endet regulär
exec spm_job.drop_job
```

Jeder Job-Lauf ist ein eigener LILAM-Prozess (In-Session, kein LILAM-Server nötig). Ein Lauf mit systemischem Fehler endet mit ORA-20110, der Scheduler verbucht ihn als `FAILED`. Überlappende Läufe (Job und manueller Abruf) verhindert die Sperre in `spm_poll`; der zweite Lauf wird als `SKIPPED` protokolliert.

Zustand und Aktualität in einer Zeile:

```sql
select job_exists, enabled, state, next_run_date, last_job_status, last_job_error,
       last_success_at, last_run_status
from   spm_job_status_v;
```

Das Abrufintervall muss zu den Limits des Providers passen (Anzahl Symbole × Läufe je Tag).

## Watchdog-Job

Erst einschalten, wenn der Abruf-Job läuft (sonst meldet der Watchdog den ausgeschalteten Abruf-Job als Fehler):

```sql
exec spm_job.create_watchdog_job                       -- WATCHDOG_JOB_NAME, alle 5 min, ausgeschaltet
exec spm_job.enable_job(spm_job.watchdog_job_name)
exec spm_job.disable_job(spm_job.watchdog_job_name)
```

Die Schweige-Regeln (`SPM-POLL-SILENT` usw.) stehen im Rule Set; nach Änderungen an `RULE_*_SEC` in `SPM_CONFIG` `exec spm_rules.publish`. Zustand beider Jobs: `SPM_JOB_STATUS_V` (Spalten `WD_*` für den Watchdog). Details: [rules/README.md](../rules/README.md#watchdog).

SPM benötigt LILAM mit `CHECK_SILENCE` (Branch `messwerte` ab `0026955`); `install/install.sql` prüft das.

## Zustellung von Alerts per E-Mail

1. Netzwerk-ACL (einmalig, als SYS; Host/Port oben im Skript anpassen, Standard `localhost:25`):
   ```sql
   @install/01_admin_network_acl.sql
   ```
   Eine ACL gilt je Datenbankbenutzer: Eine vorhandene ACL für z. B. `LILAM` genügt für `SPM` nicht.
2. Absender und Empfänger setzen (ohne sie wird nichts versandt, die Alerts bleiben `PENDING`):
   ```sql
   update spm_config set param_value = 'absender@example.org'  where param_name = 'MAIL_FROM';
   update spm_config set param_value = 'empfaenger@example.org' where param_name = 'MAIL_TO';   -- mehrere durch Komma
   commit;
   ```
   SMTP-Server: `MAIL_SMTP_HOST`, `MAIL_SMTP_PORT`, `MAIL_HELO_DOMAIN` (Standard: lokales Relay ohne TLS).
3. Zustell-Job:
   ```sql
   exec spm_job.create_notify_job                        -- NOTIFY_JOB_NAME, Läufe à 60 min, ausgeschaltet
   exec spm_job.enable_job(spm_job.notify_job_name)
   ```
   Einmalig ohne Job (versendet alle offenen Alerts der Gruppe): `exec dbms_output.put_line(spm_notify.process_pending)`.

Jeder Zustellversuch steht in `SPM_NOTIFICATION`; der Alert erhält in `LILAM_ALERTS` den Status `PROCESSED` bzw. `ERROR` (keine automatische Wiederholung). Nach `exec spm_rules.publish` enthält das Rule Set die Schweige-Regel `SPM-NOTIFY-SILENT` für den Zustell-Job.

## Kursanbieter Twelve Data

Adapter `spm_prov_twelvedata`, Endpunkt `/quote`. Der Gratistarif („Basic“, Stand 10/2026) erlaubt 800 Credits am Tag
und 8 pro Minute, ein Symbol kostet 1 Credit. 6 Symbole alle 15 Minuten rund um die Uhr ≈ 576 Credits/Tag.
Der Gratistarif enthält US-Börsen, aber **keine deutschen Börsen** (XETRA, Frankfurt: HTTP 404 „available starting
with the Grow plan“). Deutsche Werte gehen gratis nur als US-Notierung in USD:

| Aktie | Provider-Symbol | Hinweis |
| --- | --- | --- |
| SAP | `SAP` | NYSE |
| Siemens | `SIEGY` | US-Freiverkehr (ADR), Kurs vom Vortag |
| Allianz | `ALIZY` | US-Freiverkehr (ADR), Kurs vom Vortag |
| BMW | `BMWKY` | US-Freiverkehr (ADR, 1/3 Aktie) |

1. Netzwerk-ACL für `api.twelvedata.com:443` (einmalig, als SYS):
   ```sql
   @install/02_admin_provider_acl.sql
   ```
   Zertifikate: `UTL_HTTP` nutzt den Zertifikatsspeicher des Betriebssystems (`SPM_CONFIG` `HTTPS_WALLET` = `system:`),
   ein eigenes Wallet ist nicht nötig. Zeitlimit: `HTTP_TIMEOUT_SECONDS`.
2. Konto bei twelvedata.com anlegen, API-Schlüssel hinterlegen (interaktiv, Eingabe unsichtbar):
   ```
   sql -name spm @install/set_provider_key.sql
   ```
   Der Schlüssel liegt in `SPM_SECRET` (keine Sicht, keine APEX-Seite) und wird im Header
   `Authorization: apikey …` gesendet, nie in der URL oder in Logs.
3. Optionaler Live-Test (1 Credit je Symbol, speichert nichts):
   ```sql
   @test/live_twelvedata.sql "AAPL,SAP:XETR"
   ```
4. Watchlist: in APEX neue Einträge mit Provider „Twelve Data“, Provider-Symbol (z. B. `SAP`) und Währung `USD`
   anlegen. Vorhandene Mock-Einträge nicht umstellen, sondern neue Symbole verwenden (z. B. `SAP.US`):
   sonst mischen sich EUR- und USD-Kurse in einer Reihe und in der EWMA-Baseline.

Fehlerabbildung: 429 = `QUOTA` (Lauf endet), 401 = `SYSTEMIC` (Schlüssel ungültig, Lauf endet), sonst `HTTP_ERROR` nur
für das Symbol (z. B. 404 Symbol unbekannt oder nicht im Tarif). Liefert der Dienst außerhalb der Handelszeit
denselben Quote erneut, zählt der Abruf als „doppelt“, nicht als Fehler.

## APEX-Anwendung

Workspace `SPM` mit dem Schema `SPM` (APEX-Instanzadministration, `http://localhost:8080/ords/apex_admin`), dann die Anwendung importieren: siehe [apex/README.md](../apex/README.md). Aufruf: `http://localhost:8080/ords/r/spm/spm-stock-watch`, Anmeldung mit einem Benutzer des Workspace.
