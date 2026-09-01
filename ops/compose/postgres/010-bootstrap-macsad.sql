\set ON_ERROR_STOP on

SELECT 'CREATE ROLE macsad_owner'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_owner')
\gexec
SELECT 'CREATE ROLE macsad_migrator'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_migrator')
\gexec
SELECT 'CREATE ROLE macsad_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_app')
\gexec
SELECT 'CREATE ROLE macsad_reader'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_reader')
\gexec
SELECT 'CREATE ROLE alejandro LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alejandro')
\gexec
SELECT 'CREATE ROLE macsad_deployer LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_deployer')
\gexec
SELECT 'CREATE ROLE macsad_runtime LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_runtime')
\gexec
SELECT 'CREATE ROLE macsad_viewer LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'macsad_viewer')
\gexec

ALTER ROLE macsad_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_migrator NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_reader NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE alejandro LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD NULL;
ALTER ROLE macsad_deployer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT PASSWORD :'deployer_password';
ALTER ROLE macsad_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS INHERIT PASSWORD :'runtime_password';
ALTER ROLE macsad_viewer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS INHERIT PASSWORD :'viewer_password';

GRANT macsad_owner TO macsad_migrator
  WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT macsad_migrator TO alejandro
  WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT macsad_migrator TO macsad_deployer
  WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT macsad_app TO macsad_runtime
  WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT macsad_reader TO macsad_viewer
  WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;

SELECT 'CREATE DATABASE macsad OWNER macsad_owner ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'macsad')
\gexec

ALTER DATABASE macsad OWNER TO macsad_owner;
REVOKE ALL ON DATABASE macsad FROM PUBLIC;
GRANT CONNECT ON DATABASE macsad TO
  macsad_owner, macsad_migrator, macsad_app, macsad_reader,
  alejandro, macsad_deployer, macsad_runtime, macsad_viewer;

ALTER DATABASE macsad SET search_path = pg_catalog;
ALTER ROLE alejandro IN DATABASE macsad SET search_path = pg_catalog;
ALTER ROLE macsad_deployer IN DATABASE macsad SET search_path = pg_catalog;
ALTER ROLE macsad_owner IN DATABASE macsad SET search_path = macsad, macsad_meta, pg_catalog;
ALTER ROLE macsad_migrator IN DATABASE macsad SET search_path = macsad, macsad_meta, pg_catalog;
ALTER ROLE macsad_app IN DATABASE macsad SET search_path = macsad, pg_catalog;
ALTER ROLE macsad_reader IN DATABASE macsad SET search_path = macsad, pg_catalog;
ALTER ROLE macsad_runtime IN DATABASE macsad SET search_path = macsad, pg_catalog;
ALTER ROLE macsad_viewer IN DATABASE macsad SET search_path = macsad, pg_catalog;
ALTER ROLE macsad_viewer IN DATABASE macsad SET default_transaction_read_only = on;
ALTER ROLE macsad_viewer IN DATABASE macsad SET statement_timeout = '30s';
ALTER ROLE macsad_viewer IN DATABASE macsad SET lock_timeout = '5s';
ALTER ROLE macsad_viewer IN DATABASE macsad SET idle_in_transaction_session_timeout = '30s';

\connect macsad
REVOKE ALL ON SCHEMA public FROM PUBLIC;
