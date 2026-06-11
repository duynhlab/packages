# Operations

Day-2 operations for a host running the duynhlab platform: managing services,
databases, and troubleshooting. All commands assume `root` (or `sudo`).

---

## 1. `duynhlab-ctl` — service control

A thin, safe wrapper around `systemctl`/`journalctl` that knows the service
list from `/etc/duynhlab/services.yaml` (parsed with mikefarah `yq`, which the
RPM pulls automatically via `Requires: yq` — no manual install needed).

```
duynhlab-ctl <command> [svc|all] [args]
```

| Command | Example | Description |
|---|---|---|
| `list` | `duynhlab-ctl list` | List all services from `services.yaml` |
| `status` | `duynhlab-ctl status all` | systemd status table |
| `start` | `duynhlab-ctl start auth` | Start service(s) |
| `stop` | `duynhlab-ctl stop all` | Stop service(s) |
| `restart` | `duynhlab-ctl restart order` | Restart service(s) |
| `enable` | `duynhlab-ctl enable all` | Enable on boot |
| `disable` | `duynhlab-ctl disable user` | Disable on boot |
| `logs` | `duynhlab-ctl logs auth -f` | Tail journal (extra args → `journalctl`) |
| `health` | `duynhlab-ctl health all` | `curl /health` on each configured port |
| `version` | `duynhlab-ctl version all` | Print binary + schema versions |
| `config` | `duynhlab-ctl config auth` | Show env file (password masked) |
| `ports` | `duynhlab-ctl ports` | Port assignment table |

`svc` accepts a single name or `all`. Health/version iterate every service.

## 2. `duynhlab-db-setup` — database management

Operates **per service**. Reads connection settings from
`/etc/duynhlab/<svc>.env`.

```
duynhlab-db-setup <bootstrap|migrate|status> <svc>
```

| Subcommand | Needs | Description |
|---|---|---|
| `bootstrap <svc>` | `SUPERUSER_DSN` | Create database + `app`/`migrator` roles + grants |
| `migrate <svc>` | — | Apply pending migrations by exec'ing the service binary's own `migrate` subcommand (embedded golang-migrate) as the migrator role |
| `status <svc>` | — | Installed `schema_migrations` version (+ dirty flag) vs shipped `SCHEMA_VERSION` |

> Migrations are **forward-only** and embedded in each service binary — there is no
> `rollback`. Roll forward with a new migration in the service repo.

> There is **no `all`** target — bootstrap/migrate each service explicitly, or
> loop in the shell.

### One-time bootstrap (all backends)

```bash
export SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres"
for svc in auth user product cart order review notification shipping; do
  duynhlab-db-setup bootstrap "$svc"
  duynhlab-db-setup migrate   "$svc"
done
```

`bootstrap` is idempotent: re-running will not recreate existing roles/DBs.
The generated app password lives in each `/etc/duynhlab/<svc>.env`.

## 3. Bringing the platform up

```mermaid
flowchart LR
  I[dnf install duynhlab] --> B["db-setup bootstrap &lt;svc&gt;<br/>(per backend)"]
  B --> M["db-setup migrate &lt;svc&gt;"]
  M --> E[systemctl enable --now<br/>duynhlab-platform.target]
  E --> V[duynhlab-ctl status / health]
```

```bash
# after bootstrap + migrate:
systemctl enable --now duynhlab-platform.target
duynhlab-ctl status all
duynhlab-ctl health all
curl -fsS http://localhost/health
```

## 4. systemd targets

| Unit | Purpose |
|---|---|
| `duynhlab-platform.target` | Operator entry point — starts all backends |
| `duynhlab-infra.target` | Orders external infra (`nginx`, `postgresql`, `valkey`); does not own them |
| `duynhlab-<svc>.service` | One per backend, `PartOf=` the platform target |

```bash
systemctl start  duynhlab-platform.target     # all backends
systemctl status duynhlab-auth.service        # one backend
systemctl restart duynhlab-platform.target    # rolling-ish restart
journalctl -u 'duynhlab-*' -e --no-pager      # all logs
```

## 5. Configuration

| File | Owner | Notes |
|---|---|---|
| `/etc/duynhlab/env-global.properties` | operator | Shared env (DB host, etc.), loaded first |
| `/etc/duynhlab/<svc>.env` | package (1st install) | Per-service env incl. random `DB_PASSWORD`, `0640`, never overwritten on upgrade |
| `/etc/duynhlab/<svc>.override` | operator | Optional last-wins overrides (`EnvironmentFile=-`) |

To change a service's runtime setting without touching package files, write it
to `<svc>.override` and `systemctl restart duynhlab-<svc>`.

## 6. Upgrade

```bash
dnf upgrade -y duynhlab
# apply any migrations shipped in the new payload, per backend:
for svc in auth user product cart order review notification shipping; do
  duynhlab-db-setup migrate "$svc"
done
systemctl restart duynhlab-platform.target
```

Upgrades preserve `/etc/duynhlab/*.env` and the database. Nothing blocks a
backend from starting against an outdated schema (`SCHEMA_VERSION` is audit
metadata only) — a binary running ahead of its migrations fails at runtime
with SQL errors, so always run `migrate` before restarting.

## 7. Remove

```bash
systemctl disable --now duynhlab-platform.target
dnf remove -y duynhlab
```

`dnf remove` deletes `/opt/duynhlab` and the units, but **keeps**
`/etc/duynhlab` (env + passwords) and PostgreSQL data. Full purge:

```bash
rm -rf /etc/duynhlab /var/log/duynhlab /var/lib/duynhlab
# and, deliberately:
sudo -u postgres psql -c "DROP DATABASE duynhlab_auth;"   # … per service
```

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `duynhlab-ctl status` shows `inactive (dead)` | DB unreachable / wrong password | `duynhlab-ctl config <svc>`, verify with `psql` |
| Service logs SQL errors (missing table/column) after upgrade | Forgot `migrate` | `duynhlab-db-setup migrate <svc>`, restart |
| `nginx -t` fails after install | Existing `server { listen 80; }` in `nginx.conf` | Remove the default server block; ours is in `conf.d/duynhlab.conf` |
| `health` reports connection refused | Service not started or wrong port | `duynhlab-ctl start <svc>`; check `duynhlab-ctl ports` |
| `db-setup bootstrap` errors `SUPERUSER_DSN` | Env var not exported | `export SUPERUSER_DSN=postgresql://postgres:…` |
| `db-setup` errors `DB_PASSWORD empty` | Env file not generated | Reinstall, or run `duynhlab-gen-password` |

See [install.md](002-install.md) for first-time setup and [architecture.md](001-architecture.md)
for the systemd/DB model.
