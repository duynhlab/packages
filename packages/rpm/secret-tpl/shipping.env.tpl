# /etc/duynhlab/shipping.env — generated from secret-tpl/shipping.env.tpl on first install.
# Override per-host values in shipping.override (also auto-loaded by systemd unit).
SERVICE_NAME=shipping
PORT=8008
GRPC_PORT=9008

DB_HOST=localhost
DB_PORT=5432
DB_NAME=shipping
DB_USER=shipping
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
