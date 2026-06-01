# /etc/duynhlab/shipping.env — generated from secret-tpl/shipping.env.tpl on first install.
# Override per-host values in shipping.override (also auto-loaded by systemd unit).
SERVICE_NAME=shipping
PORT=8008

DB_HOST=localhost
DB_PORT=5432
DB_NAME=duynhlab_shipping
DB_USER=duynhlab_shipping_app
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25

DB_MIGRATOR_USER=duynhlab_shipping_app_migrator
DB_MIGRATOR_PASSWORD=__DB_PASSWORD__
