-- =============================================================================
-- SPM: Netzwerk-ACL für den Kursanbieter (einmalig, als Administrator)
--
-- Erlaubt dem Schema SPM HTTPS-Aufrufe per UTL_HTTP zum REST-Endpunkt des
-- Anbieters (SPM_PROV_TWELVEDATA). Aufruf als SYS AS SYSDBA (oder Benutzer mit
-- Recht auf DBMS_NETWORK_ACL_ADMIN):
--   @install/02_admin_provider_acl.sql
-- Der Host muss zu SPM_PROVIDER.BASE_URL passen.
-- Zertifikate: SPM nutzt den Zertifikatsspeicher des Betriebssystems
-- (SPM_CONFIG HTTPS_WALLET = system:), ein eigenes Wallet ist nicht nötig.
-- Wiederholbar: APPEND_HOST_ACE ergänzt nur, was fehlt.
-- =============================================================================

set verify off
set serveroutput on
whenever sqlerror exit failure

define SPM_USER  = SPM
define SPM_PDB   = FREEPDB1
define HTTP_HOST = api.twelvedata.com
define HTTP_PORT = 443

alter session set container = &SPM_PDB;

begin
    dbms_network_acl_admin.append_host_ace(
        host       => '&HTTP_HOST',
        lower_port => &HTTP_PORT,
        upper_port => &HTTP_PORT,
        ace        => xs$ace_type(privilege_list => xs$name_list('http'),
                                  principal_name => upper('&SPM_USER'),
                                  principal_type => xs_acl.ptype_db));
    dbms_output.put_line('HTTPS-Zugriff für &SPM_USER auf &HTTP_HOST:&HTTP_PORT erlaubt.');
end;
/
