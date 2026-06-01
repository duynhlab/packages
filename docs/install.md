# Install duynhlab from the YUM repository

The `duynhlab/packages` project publishes a YUM repository at
<https://duynhlab.github.io/packages> hosting the **duynhlab mega-RPM**:
8 Go backend services + frontend SPA + CLI tools + systemd units, all in a
single package.

> **Status (Phase 2)**: RPM-only, EL9 / x86_64, unsigned (`gpgcheck=0`).
> GPG signing lands in Phase 3.

---

## Supported targets

| Target | Status |
|---|---|
| Rocky Linux 9 / AlmaLinux 9 / RHEL 9 (x86_64) | Supported |
| EL10, Fedora, Debian/Ubuntu | Planned (Phase 3 / Phase 4) |
| aarch64 | Planned (Phase 3) |

## Prerequisites

Install once on the target host:

```bash
sudo dnf install -y epel-release
sudo dnf module enable -y postgresql:16
sudo dnf install -y \
  nginx \
  valkey \
  postgresql      # client only; the server may live on another host
```

(Replace `valkey` with `redis` if you prefer; the RPM accepts either.)

If PostgreSQL is on the same host, also install `postgresql-server` and run
`postgresql-setup --initdb && systemctl enable --now postgresql`.

## 1. Add the repository

```bash
sudo curl -fsSL \
  -o /etc/yum.repos.d/duynhlab.repo \
  https://duynhlab.github.io/packages/duynhlab.repo
```

The shipped `duynhlab.repo` looks like:

```ini
[duynhlab]
name=duynhlab platform packages (EL$releasever)
baseurl=https://duynhlab.github.io/packages/rpm/el$releasever/$basearch/
enabled=1
gpgcheck=0
repo_gpgcheck=0
```

Confirm `dnf` sees it:

```bash
sudo dnf repolist | grep duynhlab
sudo dnf --refresh search duynhlab
```

## 2. Install

```bash
sudo dnf install -y duynhlab
```

The post-install scriptlet:

- creates the `duynhlab` system user/group
- generates `/etc/duynhlab/<svc>.env` with a random 32-char `DB_PASSWORD`
  (preserved on upgrade / reinstall — never overwritten)
- drops nginx vhost into `/etc/nginx/conf.d/duynhlab.conf`
- drops valkey + logrotate snippets if those layouts exist
- registers per-service systemd units and the `duynhlab-platform.target`
- **does not** enable or start anything — that is your job

## 3. Bootstrap the database (one-time)

Provide a PostgreSQL superuser DSN via `SUPERUSER_DSN` and let
`duynhlab-db-setup` create one database + two roles per service (`app`,
`migrator`), then apply migrations:

```bash
SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \
  sudo -E duynhlab-db-setup bootstrap

sudo duynhlab-db-setup migrate
```

`duynhlab-db-setup` reads `/etc/duynhlab/services.yaml` to know which services
need a DB, and stores the generated app-role password in each
`/etc/duynhlab/<svc>.env`.

## 4. Start the platform

```bash
sudo systemctl enable --now duynhlab-platform.target
```

Verify:

```bash
duynhlab-ctl status            # per-service status table
duynhlab-ctl ports             # listening port mapping
curl -fsS http://localhost/health
journalctl -u 'duynhlab-*' -e --no-pager
```

## 5. Upgrade

```bash
sudo dnf upgrade -y duynhlab
# Apply any new migrations shipped in the new RPM:
sudo duynhlab-db-setup migrate
sudo systemctl restart duynhlab-platform.target
```

Upgrades:

- **Preserve** `/etc/duynhlab/*.env` and the database.
- **Refuse to start** a service whose binary expects a higher
  `SCHEMA_VERSION` than what is applied in the DB — run
  `duynhlab-db-setup migrate` first.

## 6. Remove

```bash
sudo systemctl disable --now duynhlab-platform.target
sudo dnf remove -y duynhlab
```

`dnf remove` deletes `/opt/duynhlab/` and the systemd units but leaves
`/etc/duynhlab/` (env files + generated passwords) and your PostgreSQL data
intact. To purge those:

```bash
sudo rm -rf /etc/duynhlab /var/log/duynhlab /var/lib/duynhlab
# And, only if you know what you're doing:
sudo -u postgres psql -c "DROP DATABASE duynhlab_auth;" ...
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `dnf install` fails: `Curl error (60): SSL certificate problem` | Mirror reach is restricted | `dnf install --setopt=sslverify=false` once, then fix CA |
| `systemctl start duynhlab-auth` fails: "schema version mismatch" | Forgot `duynhlab-db-setup migrate` after upgrade | Run it, then restart |
| `nginx -t` fails after install | Existing `nginx.conf` already defines `server { listen 80; }` | Edit `/etc/nginx/nginx.conf` to remove the default `server` block; ours lives in `conf.d/duynhlab.conf` |
| `duynhlab-ctl status` shows `inactive (dead)` | DB unreachable or password wrong | `grep DB_PASSWORD /etc/duynhlab/<svc>.env`, verify via `psql` |

## Local-mirror testing

If you want to exercise the install path without GitHub Pages:

```bash
cd packages
make build-local-all build smoke
# Stage a local YUM tree:
REPO_OUT=/tmp/duynhlab-repo \
  BASE_URL=http://localhost:8080 \
  ./scripts/publish-yum-repo.sh
python3 -m http.server -d /tmp/duynhlab-repo 8080 &
# Then in a Rocky 9 container or VM:
sudo curl -fsSL -o /etc/yum.repos.d/duynhlab.repo \
  http://localhost:8080/duynhlab.repo
sudo dnf install duynhlab
```

See also: [`docs/release-process.md`](release-process.md) for the publish
flow, and [`plan.md`](../plan.md) §2 for the broader Phase 2 design.
