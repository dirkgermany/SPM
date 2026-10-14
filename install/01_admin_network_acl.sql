-- =============================================================================
-- SPM: Netzwerk-ACL für den E-Mail-Versand (einmalig, als Administrator)
--
-- Erlaubt dem Schema SPM, per UTL_SMTP den SMTP-Relay zu erreichen (SPM_NOTIFY).
-- Aufruf als SYS AS SYSDBA (oder Benutzer mit Recht auf DBMS_NETWORK_ACL_ADMIN):
--   @install/01_admin_network_acl.sql
-- Host und Port müssen zu SPM_CONFIG (MAIL_SMTP_HOST, MAIL_SMTP_PORT) passen.
-- Wiederholbar: APPEND_HOST_ACE ergänzt nur, was fehlt.
-- =============================================================================

set verify off
set serveroutput on
whenever sqlerror exit failure

define SPM_USER  = SPM
define SPM_PDB   = FREEPDB1
define SMTP_HOST = localhost
define SMTP_PORT = 25

alter session set container = &SPM_PDB;

begin
    dbms_network_acl_admin.append_host_ace(
        host       => '&SMTP_HOST',
        lower_port => &SMTP_PORT,
        upper_port => &SMTP_PORT,
        ace        => xs$ace_type(privilege_list => xs$name_list('smtp'),
                                  principal_name => upper('&SPM_USER'),
                                  principal_type => xs_acl.ptype_db));
    dbms_output.put_line('SMTP-Zugriff für &SPM_USER auf &SMTP_HOST:&SMTP_PORT erlaubt.');
end;
/
