# /etc/duynhlab/auth.env — generated from secret-tpl/auth.env.tpl on first install.
# Override per-host values in auth.override (also auto-loaded by systemd unit).
SERVICE_NAME=auth
PORT=8001
GRPC_PORT=9001

DB_HOST=localhost
DB_PORT=5432
DB_NAME=auth
DB_USER=auth
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
