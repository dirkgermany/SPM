-- =============================================================================
-- SPM: Schema anlegen (einmalig, als Administrator)
--
-- Aufruf (SQLcl / SQL*Plus), angemeldet als SYS AS SYSDBA (oder ein Benutzer mit
-- CREATE USER und GRANT-Recht auf die SYS-Pakete) in der PDB, z. B.:
--   sql sys@localhost:1521/FREEPDB1 as sysdba
--   @install/00_admin_create_schema.sql
--
-- Das Kennwort wird abgefragt und nicht gespeichert. Das Skript ist wiederholbar:
-- ein vorhandener Benutzer wird nicht neu angelegt, die Rechte werden erneut vergeben.
-- =============================================================================

set verify off
set serveroutput on
whenever sqlerror exit failure

-- Schemaname und Tablespace bei Bedarf hier anpassen
define SPM_USER       = SPM
define SPM_TABLESPACE = USERS

accept SPM_PASSWORD char prompt 'Kennwort für &SPM_USER (wird nicht angezeigt): ' hide

declare
    l_count pls_integer;
begin
    select count(*) into l_count from dba_users where username = upper('&SPM_USER');
    if l_count = 0 then
        execute immediate 'create user &SPM_USER identified by "&SPM_PASSWORD"'
                       || ' default tablespace &SPM_TABLESPACE quota unlimited on &SPM_TABLESPACE';
        dbms_output.put_line('Benutzer &SPM_USER angelegt.');
    else
        dbms_output.put_line('Benutzer &SPM_USER existiert bereits, nur Rechte werden vergeben.');
    end if;
end;
/

undefine SPM_PASSWORD

-- Systemrechte: Anwendungsobjekte und LILAM (legt seine Tabellen selbst an)
grant create session, create table, create sequence, create view, create procedure, create type to &SPM_USER;
-- DBMS_SCHEDULER-Job für den Kursabruf, später LILAM-Server per CREATE_SERVER
grant create job to &SPM_USER;

-- LILAM referenziert DBMS_PIPE und DBMS_ALERT statisch; ohne diese Rechte kompiliert
-- der Package Body nicht (auch im reinen In-Session-Betrieb). DBMS_ALERT signalisiert Alerts.
grant execute on sys.dbms_pipe  to &SPM_USER;
grant execute on sys.dbms_alert to &SPM_USER;
-- SPM: Sperre gegen überlappende Abrufläufe
grant execute on sys.dbms_lock  to &SPM_USER;

prompt
prompt Schema &SPM_USER ist bereit. Weiter mit install/install.sql als &SPM_USER.
