-- init-databases.sql — one PostgreSQL database per backend service.
--
-- Applied ONCE by duynhlab-bootstrap as the postgres superuser, AFTER the roles
-- exist (init-users.sql). Each database is OWNED by its same-named login role,
-- so that role (which the service + its migrations connect as) can run DDL with
-- no extra schema grants:
--   * PostgreSQL 15+: the `public` schema is owned by `pg_database_owner`, i.e.
--     the database owner — so the role owns public and can create objects.
--   * PostgreSQL <15: `public` grants CREATE to PUBLIC by default.
--
-- Idempotent (CREATE only when absent). Reserved words (user, order) are safe:
-- format(%I) quotes the generated identifier.
--
-- THE place to add a new service database: add a line below (plus a registry
-- entry in scripts/lib/common.sh and a secret-tpl) and bootstrap picks it up.
\set ON_ERROR_STOP on

SELECT format('CREATE DATABASE %I OWNER %I', 'auth', 'auth')                 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'auth')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'user', 'user')                 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'user')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'product', 'product')           WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'product')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'cart', 'cart')                 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cart')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'order', 'order')               WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'order')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'review', 'review')             WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'review')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'notification', 'notification') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'notification')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'shipping', 'shipping')         WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'shipping')\gexec
