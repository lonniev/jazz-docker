#!/bin/bash
#
# Oracle 19c schema initialization for IBM Jazz CLM 7.0.2
# This script runs inside the Oracle container after the database is ready.
# It creates per-application schemas (as Oracle users) within the pluggable database.
#

set -e

ORACLE_PDB="${ORACLE_PDB:-JAZZPDB}"
JAZZ_DBA="${ORACLE_USER:-jazz_dba}"
JAZZ_DBA_PWD="${ORACLE_PASSWORD:-Ora19Jazz!}"
SYS_PWD="${ORACLE_PWD:-SysOracle19!}"

echo "=== Jazz CLM: Creating Oracle schemas in PDB ${ORACLE_PDB} ==="

# Datafiles must use absolute paths within the persistent oradata volume,
# otherwise Oracle places them in dbs/ which is lost on container restart.
DATAFILE_DIR="/opt/oracle/oradata/ORCLCDB/${ORACLE_PDB}"
mkdir -p "${DATAFILE_DIR}"

# Define Jazz databases and their default tablespace sizes (in MB)
declare -A schemas
schemas[JTS]=512
schemas[CCM]=512
schemas[QM]=512
schemas[RM]=512
schemas[LQE]=1024
schemas[LDX]=1024
schemas[DCC]=512
schemas[GC]=512
schemas[RELM]=512
schemas[DM]=512
schemas[DW]=512

# Connect to the PDB as SYS and create everything (idempotent — skips if already exists)
sqlplus -s "sys/${SYS_PWD}@localhost:1521/${ORACLE_PDB} as sysdba" <<EOSQL
SET FEEDBACK OFF
WHENEVER SQLERROR CONTINUE

-- Create a shared DBA user if it doesn't exist
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = UPPER('${JAZZ_DBA}');
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER ${JAZZ_DBA} IDENTIFIED BY "${JAZZ_DBA_PWD}" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP QUOTA UNLIMITED ON USERS';
    DBMS_OUTPUT.PUT_LINE('Created user ${JAZZ_DBA}');
  ELSE
    DBMS_OUTPUT.PUT_LINE('User ${JAZZ_DBA} already exists — skipping');
  END IF;
END;
/

GRANT CONNECT, RESOURCE, DBA TO ${JAZZ_DBA};
GRANT CREATE SESSION TO ${JAZZ_DBA};
GRANT UNLIMITED TABLESPACE TO ${JAZZ_DBA};

EOSQL

# Create a schema (Oracle user) and tablespace for each Jazz application
for schema in "${!schemas[@]}"; do

    size="${schemas[$schema]}"
    ts_name="TS_${schema}"

    sqlplus -s "sys/${SYS_PWD}@localhost:1521/${ORACLE_PDB} as sysdba" <<EOSQL
    SET FEEDBACK OFF
    SET SERVEROUTPUT ON
    WHENEVER SQLERROR CONTINUE

    DECLARE
      v_ts_count NUMBER;
      v_user_count NUMBER;
    BEGIN
      -- Check/create tablespace
      SELECT COUNT(*) INTO v_ts_count FROM dba_tablespaces WHERE tablespace_name = '${ts_name}';
      IF v_ts_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLESPACE ${ts_name} DATAFILE ''${DATAFILE_DIR}/${schema,,}_data.dbf'' SIZE ${size}M AUTOEXTEND ON NEXT 64M MAXSIZE UNLIMITED EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO';
        DBMS_OUTPUT.PUT_LINE('Created tablespace ${ts_name}');
      ELSE
        DBMS_OUTPUT.PUT_LINE('Tablespace ${ts_name} already exists — skipping');
      END IF;

      -- Check/create schema user
      SELECT COUNT(*) INTO v_user_count FROM dba_users WHERE username = '${schema}';
      IF v_user_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER ${schema} IDENTIFIED BY "${JAZZ_DBA_PWD}" DEFAULT TABLESPACE ${ts_name} TEMPORARY TABLESPACE TEMP QUOTA UNLIMITED ON ${ts_name}';
        DBMS_OUTPUT.PUT_LINE('Created schema user ${schema}');
      ELSE
        DBMS_OUTPUT.PUT_LINE('Schema user ${schema} already exists — skipping');
      END IF;
    END;
    /

    GRANT CONNECT, RESOURCE TO ${schema};
    GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE TO ${schema};
    GRANT ALL PRIVILEGES TO ${JAZZ_DBA};

EOSQL

done

# Create the OAuth2 database schema for Jazz Auth Server
echo "Creating OAuth2 schema for Jazz Authentication Server..."

sqlplus -s "sys/${SYS_PWD}@localhost:1521/${ORACLE_PDB} as sysdba" <<EOSQL
SET FEEDBACK OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

DECLARE
  v_ts_count NUMBER;
  v_user_count NUMBER;
  v_tab_count NUMBER;
BEGIN
  -- Check/create OAuth tablespace
  SELECT COUNT(*) INTO v_ts_count FROM dba_tablespaces WHERE tablespace_name = 'TS_OAUTH2';
  IF v_ts_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE TS_OAUTH2 DATAFILE ''${DATAFILE_DIR}/oauth2_data.dbf'' SIZE 256M AUTOEXTEND ON NEXT 64M MAXSIZE UNLIMITED EXTENT MANAGEMENT LOCAL AUTOALLOCATE SEGMENT SPACE MANAGEMENT AUTO';
    DBMS_OUTPUT.PUT_LINE('Created tablespace TS_OAUTH2');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Tablespace TS_OAUTH2 already exists — skipping');
  END IF;

  -- Check/create OAuth user
  SELECT COUNT(*) INTO v_user_count FROM dba_users WHERE username = 'OAUTHDBSCHEMA';
  IF v_user_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER OAUTHDBSCHEMA IDENTIFIED BY "Ora19Jazz!" DEFAULT TABLESPACE TS_OAUTH2 TEMPORARY TABLESPACE TEMP QUOTA UNLIMITED ON TS_OAUTH2';
    DBMS_OUTPUT.PUT_LINE('Created user OAUTHDBSCHEMA');
  ELSE
    DBMS_OUTPUT.PUT_LINE('User OAUTHDBSCHEMA already exists — skipping');
  END IF;
END;
/

GRANT CONNECT, RESOURCE TO OAUTHDBSCHEMA;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE TO OAUTHDBSCHEMA;

-- Create OAuth tables (IF NOT EXISTS via checking user_tables)
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM all_tables WHERE owner = 'OAUTHDBSCHEMA' AND table_name = 'OAUTH20CACHE';
  IF v_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('OAuth tables already exist — skipping creation');
    RETURN;
  END IF;
END;
/

CREATE TABLE OAUTHDBSCHEMA.OAUTH20CACHE (
  LOOKUPKEY VARCHAR2(256) NOT NULL,
  UNIQUEID VARCHAR2(128) NOT NULL,
  COMPONENTID VARCHAR2(256) NOT NULL,
  TYPE VARCHAR2(64) NOT NULL,
  SUBTYPE VARCHAR2(64),
  CREATEDAT NUMBER(19),
  LIFETIME NUMBER(10),
  EXPIRES NUMBER(19),
  TOKENSTRING VARCHAR2(2048) NOT NULL,
  CLIENTID VARCHAR2(64) NOT NULL,
  USERNAME VARCHAR2(64) NOT NULL,
  SCOPE VARCHAR2(512) NOT NULL,
  REDIRECTURI VARCHAR2(2048),
  STATEID VARCHAR2(64) NOT NULL,
  EXTENDEDFIELDS CLOB DEFAULT '{}' NOT NULL,
  CONSTRAINT PK_LOOKUPKEY PRIMARY KEY (LOOKUPKEY)
);

CREATE TABLE OAUTHDBSCHEMA.OAUTH20CLIENTCONFIG (
  COMPONENTID VARCHAR2(256) NOT NULL,
  CLIENTID VARCHAR2(256) NOT NULL,
  CLIENTSECRET VARCHAR2(256),
  DISPLAYNAME VARCHAR2(256) NOT NULL,
  REDIRECTURI VARCHAR2(2048),
  ENABLED NUMBER(10),
  CLIENTMETADATA CLOB DEFAULT '{}' NOT NULL,
  CONSTRAINT PK_COMPIDCLIENTID PRIMARY KEY (COMPONENTID, CLIENTID)
);

CREATE TABLE OAUTHDBSCHEMA.OAUTH20CONSENTCACHE (
  CLIENTID VARCHAR2(256) NOT NULL,
  USERID VARCHAR2(256),
  PROVIDERID VARCHAR2(256) NOT NULL,
  SCOPE VARCHAR2(1024) NOT NULL,
  EXPIRES NUMBER(19),
  EXTENDEDFIELDS CLOB DEFAULT '{}' NOT NULL
);

CREATE INDEX OAUTH20CACHE_EXPIRES ON OAUTHDBSCHEMA.OAUTH20CACHE (EXPIRES ASC);

-- Grant the Jazz DBA access to OAuth tables
GRANT ALL ON OAUTHDBSCHEMA.OAUTH20CACHE TO jazz_dba;
GRANT ALL ON OAUTHDBSCHEMA.OAUTH20CLIENTCONFIG TO jazz_dba;
GRANT ALL ON OAUTHDBSCHEMA.OAUTH20CONSENTCACHE TO jazz_dba;

EOSQL

echo "=== Jazz CLM: Oracle schema initialization complete ==="

# DW-specific tuning: Oracle handles concurrency differently than DB2,
# but we ensure the DW schema user has the right grants for reporting
sqlplus -s "sys/${SYS_PWD}@localhost:1521/${ORACLE_PDB} as sysdba" <<EOSQL
WHENEVER SQLERROR CONTINUE
GRANT SELECT ANY TABLE TO DW;
GRANT INSERT ANY TABLE TO DW;
GRANT UPDATE ANY TABLE TO DW;
GRANT DELETE ANY TABLE TO DW;
EOSQL

echo "=== Jazz CLM: All Oracle schemas ready ==="
