# /etc/duynhlab/order.env — generated from secret-tpl/order.env.tpl on first install.
# Override per-host values in order.override (also auto-loaded by systemd unit).
SERVICE_NAME=order
PORT=8005

DB_HOST=localhost
DB_PORT=5432
DB_NAME=duynhlab_order
DB_USER=duynhlab_order_app
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25

DB_MIGRATOR_USER=duynhlab_order_app_migrator
DB_MIGRATOR_PASSWORD=__DB_PASSWORD__
