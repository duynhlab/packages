-- bootstrap.sql — duynhlab per-service databases + roles.
--
-- Rendered/applied by /usr/bin/duynhdb as the postgres superuser.
-- Idempotent: uses DO blocks + IF NOT EXISTS guards.
--
-- This file is a TEMPLATE — duynhdb substitutes:
--   :svc        short name (e.g. auth)
--   :db         duynhlab_<svc>
--   :app_user   duynhlab_<svc>_app
--   :mig_user   duynhlab_<svc>_migrator
--   :app_pw     random 32-char password (from /etc/duynhlab/<svc>.env)
--   :mig_pw     random 32-char password
--
-- Run order, once per service:
--   psql "$SUPERUSER_DSN" -v ON_ERROR_STOP=1 \
--        -v svc=auth -v db=duynhlab_auth \
--        -v app_user=duynhlab_auth_app  -v app_pw='xxx' \
--        -v mig_user=duynhlab_auth_migrator -v mig_pw='yyy' \
--        -f /opt/duynhlab/postgresql/bootstrap.sql

\set ON_ERROR_STOP on

-- 1. Roles ───────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_pw');
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_pw');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'mig_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'mig_user', :'mig_pw');
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'mig_user', :'mig_pw');
  END IF;
END
$$;

-- 2. Database ────────────────────────────────────────────────────────────────
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'mig_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db')
\gexec

-- 3. Connect privileges ──────────────────────────────────────────────────────
\connect :"db"

GRANT CONNECT ON DATABASE :"db" TO :"app_user";
GRANT USAGE ON SCHEMA public TO :"app_user", :"mig_user";

-- Migrator owns schema; app gets CRUD on everything it creates.
ALTER SCHEMA public OWNER TO :"mig_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"mig_user" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"mig_user" IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"mig_user" IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO :"app_user";
