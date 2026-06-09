# /etc/duynhlab/review.env — generated from secret-tpl/review.env.tpl on first install.
# Override per-host values in review.override (also auto-loaded by systemd unit).
SERVICE_NAME=review
PORT=8006
GRPC_PORT=9006

DB_HOST=localhost
DB_PORT=5432
DB_NAME=duynhlab_review
DB_USER=duynhlab_review_app
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25

DB_MIGRATOR_USER=duynhlab_review_app_migrator
DB_MIGRATOR_PASSWORD=__DB_PASSWORD__
