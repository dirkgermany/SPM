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

Netzwerk-ACL und Wallet für einen echten Provider kommen mit dem ersten REST-Adapter dazu.

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

SPM installiert LILAM in das eigene Schema. Nach einer Änderung im LILAM-Checkout `install/install.sql` erneut ausführen, damit der Body im Schema SPM neu kompiliert wird. Skripte mit `WHENEVER`/`EXIT` über die SQLcl-Kommandozeile ausführen, nicht über einen SQLcl-MCP-Server: `EXIT` beendet dessen Skript-Engine.
