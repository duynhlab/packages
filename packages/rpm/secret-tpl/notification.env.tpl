# /etc/duynhlab/notification.env — generated from secret-tpl/notification.env.tpl on first install.
# Override per-host values in notification.override (also auto-loaded by systemd unit).
SERVICE_NAME=notification
PORT=8007
GRPC_PORT=9007

DB_HOST=localhost
DB_PORT=5432
DB_NAME=notification
DB_USER=notification
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
