-- =============================================================================
-- SPM: Installation
--
-- Aufruf (SQLcl / SQL*Plus), angemeldet als Schema SPM:
--   @install/install.sql <Pfad zum LILAM-Checkout>
--   z. B. @install/install.sql C:/Users/dirk/Documents/LILAM/lilam
--
-- Voraussetzung: install/00_admin_create_schema.sql wurde als Administrator ausgeführt.
-- Wiederholbar: Tabellen werden nur angelegt, wenn sie fehlen (CREATE ... IF NOT EXISTS,
-- ab Oracle 23ai), Pakete werden neu kompiliert, Grunddaten per MERGE ergänzt.
-- =============================================================================

set define on
set verify off
set serveroutput on
whenever sqlerror exit failure rollback

define LILAM_HOME = '&1'

prompt
prompt === SPM 1/4: LILAM installieren (&LILAM_HOME) ===
@@10_lilam.sql

whenever sqlerror exit failure rollback
set feedback on

prompt
prompt === SPM 2/4: Tabellen und Sichten ===
@@20_tables.sql
@@25_views.sql
@@26_apex_views.sql

prompt
prompt === SPM 3/4: Pakete ===
@@30_packages.sql

prompt
prompt === SPM 4/4: Grunddaten ===
@@40_seed.sql

prompt
prompt SPM ist installiert. Demo-Watchlist (optional): @install/50_demo_data.sql
prompt Abruf-Job (nicht automatisch): exec spm_job.create_job; exec spm_job.enable_job
