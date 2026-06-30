# /etc/duynhlab/product.env — generated from secret-tpl/product.env.tpl on first install.
# Override per-host values in product.override (also auto-loaded by systemd unit).
SERVICE_NAME=product
PORT=8003

DB_HOST=localhost
DB_PORT=5432
DB_NAME=product
DB_USER=product
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
