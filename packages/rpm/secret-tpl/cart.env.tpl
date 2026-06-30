# /etc/duynhlab/cart.env — generated from secret-tpl/cart.env.tpl on first install.
# Override per-host values in cart.override (also auto-loaded by systemd unit).
SERVICE_NAME=cart
PORT=8004

DB_HOST=localhost
DB_PORT=5432
DB_NAME=cart
DB_USER=cart
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
