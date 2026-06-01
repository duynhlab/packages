# /etc/duynhlab/notification.env — generated from secret-tpl/notification.env.tpl on first install.
# Override per-host values in notification.override (also auto-loaded by systemd unit).
SERVICE_NAME=notification
PORT=8007

DB_HOST=localhost
DB_PORT=5432
DB_NAME=duynhlab_notification
DB_USER=duynhlab_notification_app
DB_PASSWORD=__DB_PASSWORD__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25

DB_MIGRATOR_USER=duynhlab_notification_app_migrator
DB_MIGRATOR_PASSWORD=__DB_PASSWORD__
