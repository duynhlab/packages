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

The RPM declares `Requires:` for nginx, the PostgreSQL **client**, and valkey,
so `dnf install duynhlab` (next section) pulls them in for you. You only need to
make those packages resolvable, and — if PostgreSQL runs on the same host —
initialise the server:

```bash
# 1. Enable EPEL — provides valkey and yq (duynhctl's YAML parser).
sudo dnf install -y epel-release

# 2. Same-host PostgreSQL only — install and initialise the server.
#    Skip this entirely if your database lives on another host.
sudo dnf module enable -y postgresql:16
sudo dnf install -y postgresql-server
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
```

> Don't hand-install nginx / valkey / the `postgresql` client — they are RPM
> `Requires` and get pulled automatically once EPEL is enabled.

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

`duynhdb` is **per-service**: each invocation takes a single service
name (`bootstrap <svc>` / `migrate <svc>`). It creates one database + two roles
(`app`, `migrator`) for that service and stores the generated app-role password
in `/etc/duynhlab/<svc>.env`.

Provide a PostgreSQL superuser DSN via `SUPERUSER_DSN` and loop over the
backend services:

```bash
export SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres"

for svc in auth user product cart order review notification shipping; do
  sudo -E duynhdb bootstrap "$svc"
done

for svc in auth user product cart order review notification shipping; do
  sudo duynhdb migrate "$svc"
done
```

(`migrate` uses the migrator role and does not need `SUPERUSER_DSN`.)

## 4. Start the platform

```bash
sudo systemctl enable --now duynhlab-platform.target
```

Verify:

```bash
duynhctl status            # per-service status table
duynhctl ports             # listening port mapping
curl -fsS http://localhost/health
journalctl -u 'duynhlab-*' -e --no-pager
```

## 5. Upgrade

```bash
sudo dnf upgrade -y duynhlab
# Apply any new migrations shipped in the new RPM:
for svc in auth user product cart order review notification shipping; do
  sudo duynhdb migrate "$svc"
done
sudo systemctl restart duynhlab-platform.target
```

Upgrades:

- **Preserve** `/etc/duynhlab/*.env` and the database.
- **Do not auto-migrate.** Always run `duynhdb migrate <svc>` after an
  upgrade — a new binary may query tables/columns its embedded migrations have
  not created yet, failing at runtime with SQL errors. (`SCHEMA_VERSION` under
  `/opt/duynhlab/<svc>/` is audit metadata only — nothing blocks startup.)

### Downgrade / pin a version

The repository metadata indexes the **last 3 releases**, so dnf can see and
install older versions directly:

```bash
dnf list duynhlab --showduplicates       # see the available versions
sudo dnf downgrade -y duynhlab           # one release back
sudo dnf install -y duynhlab-2026.06.09  # or pin an exact version
```

> ⚠️ Downgrading the package does **not** downgrade the database schema —
> migrations are forward-only. Only downgrade across versions whose
> `SCHEMA_VERSION` matches (check the release notes), or restore the DB from a
> backup taken before the upgrade.

Releases older than the last 3: download the RPM from
[GitHub Releases](https://github.com/duynhlab/packages/releases) and
`sudo dnf install ./duynhlab-<ver>-1.el9.x86_64.rpm`. Every release ships a
`MANIFEST.txt` asset recording the exact service commits it was built from.

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

When contacting support, attach a diagnostics bundle —
`sudo duynhctl support-bundle` collects journals, unit status, versions and
non-secret configs into one tarball (**your `*.env` secrets are never
included**).

| Symptom | Likely cause | Fix |
|---|---|---|
| `dnf install` fails: `Curl error (60): SSL certificate problem` | Mirror reach is restricted | `dnf install --setopt=sslverify=false` once, then fix CA |
| Service starts but logs SQL errors (missing table/column) after an upgrade | Forgot `duynhdb migrate auth` | Run it, then `systemctl restart duynhlab-auth` |
| `nginx -t` fails after install | Existing `nginx.conf` already defines `server { listen 80; }` | Edit `/etc/nginx/nginx.conf` to remove the default `server` block; ours lives in `conf.d/duynhlab.conf` |
| `duynhctl status` shows `inactive (dead)` | DB unreachable or password wrong | `grep DB_PASSWORD /etc/duynhlab/<svc>.env`, verify via `psql` |

## Local-mirror testing

If you want to exercise the install path without GitHub Pages:

```bash
cd packages
make build-local-all build test-install
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

See also: [`docs/README.md`](README.md) for the full documentation index —
in particular [`004-build.md`](004-build.md) for the publish flow and
[`003-operations.md`](003-operations.md) for day-2 operations.
