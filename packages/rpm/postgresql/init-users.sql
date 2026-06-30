-- init-users.sql — create/refresh ONE login role per service (idempotent).
--
-- Applied once PER SERVICE by duynhlab-bootstrap as the postgres superuser:
--   psql ... -v role=auth -v pass='<generated>' -f init-users.sql
--
-- One role per service, named after the service (auth, user, …). The role owns
-- its same-named database (see init-databases.sql) and is what the service AND
-- its migrations connect as. Password is generated per install (per customer)
-- by password-generator.sh and lives in /etc/duynhlab/<svc>.env.
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pass');
  ELSE
    -- Keep the role's password in sync with the env file on re-run/upgrade.
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'role', :'pass');
  END IF;
END
$$;
