# /etc/duynhlab/user.env — generated from secret-tpl/user.env.tpl on first install.
# Override per-host values in user.override (also auto-loaded by systemd unit).
SERVICE_NAME=user
PORT=8002

DB_HOST=localhost
DB_PORT=5432
DB_NAME=user
DB_USER=user
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
