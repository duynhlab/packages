# Operations

Day-2 operations for a host running the duynhlab platform: managing services,
databases, and troubleshooting. All commands assume `root` (or `sudo`).

---

## 1. `duynhctl` — service control

A thin, safe wrapper around `systemctl`/`journalctl` that knows the service
list from `/etc/duynhlab/services.yaml` (parsed with mikefarah `yq`, which the
RPM pulls automatically via `Requires: yq` — no manual install needed).

```
duynhctl <command> [svc|all] [args]
```

| Command | Example | Description |
|---|---|---|
| `list` | `duynhctl list` | List all services from `services.yaml` |
| `status` | `duynhctl status all` | systemd status table |
| `start` | `duynhctl start auth` | Start service(s) |
| `stop` | `duynhctl stop all` | Stop service(s) |
| `restart` | `duynhctl restart order` | Restart service(s) |
| `enable` | `duynhctl enable all` | Enable on boot |
| `disable` | `duynhctl disable user` | Disable on boot |
| `logs` | `duynhctl logs auth -f` | Tail journal (extra args → `journalctl`) |
| `health` | `duynhctl health all` | `curl /health` on each configured port |
| `version` | `duynhctl version all` | Print binary + schema versions |
| `config` | `duynhctl config auth` | Show env file (password masked) |
| `ports` | `duynhctl ports` | Port assignment table |
| `support-bundle` | `duynhctl support-bundle [dir]` | Diagnostics tarball for support: 7 days of journals, unit status, manifest, versions, install history, non-secret configs. **`*.env` / `*.override` are never included** |

`svc` accepts a single name or `all`. Health/version iterate every service.

## 2. `duynhdb` — database management

Operates **per service**. Reads connection settings from
`/etc/duynhlab/<svc>.env`.

```
duynhdb <bootstrap|migrate|status> <svc>
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
  duynhdb bootstrap "$svc"
  duynhdb migrate   "$svc"
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
  E --> V[duynhctl status / health]
```

```bash
# after bootstrap + migrate:
systemctl enable --now duynhlab-platform.target
duynhctl status all
duynhctl health all
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

> Full list of every config file the RPM installs or generates (including the
> nginx/valkey/postgresql/logrotate drops): [`007-file-reference.md`](007-file-reference.md).

### Layering — how a service gets its environment

Every `duynhlab-<svc>.service` unit loads three files **in order; a later file
overrides any variable set by an earlier one** (standard systemd
`EnvironmentFile=` semantics; the `-` prefix means "optional, skip if absent"):

```
EnvironmentFile=-/etc/duynhlab/env-global.properties   ① shared defaults
EnvironmentFile=/etc/duynhlab/<svc>.env                ② machine-generated, REQUIRED
EnvironmentFile=-/etc/duynhlab/<svc>.override          ③ yours — loaded last, wins
```

| Layer | File | Owner | Notes |
|---|---|---|---|
| ① defaults | `env-global.properties` | operator | Shared values (e.g. `DB_HOST`); installed once, editable |
| ② generated | `<svc>.env` | package (1st install) | Rendered from `secret-tpl/<svc>.env.tpl` with a random `DB_PASSWORD`; `0640 root:duynhlab`; **never overwritten** on reinstall/upgrade |
| ③ override | `<svc>.override` | **you** | The RPM never creates or touches it — your per-host customizations live here and survive every upgrade |

Example: `auth.env` says `DB_HOST=localhost`; create `auth.override` with
`DB_HOST=db.prod.internal` and restart — the service now uses the override.
Delete the file to fall back.

**Rule of thumb: never edit the generated `<svc>.env`** (your edit is safe from
the RPM, but mixing hand edits into a machine-managed file makes drift hard to
reason about). Put changes in `<svc>.override`, then
`systemctl restart duynhlab-<svc>`.

## 6. Upgrade

```bash
dnf upgrade -y duynhlab
# apply any migrations shipped in the new payload, per backend:
for svc in auth user product cart order review notification shipping; do
  duynhdb migrate "$svc"
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
| `duynhctl status` shows `inactive (dead)` | DB unreachable / wrong password | `duynhctl config <svc>`, verify with `psql` |
| Service logs SQL errors (missing table/column) after upgrade | Forgot `migrate` | `duynhdb migrate <svc>`, restart |
| `nginx -t` fails after install | Existing `server { listen 80; }` in `nginx.conf` | Remove the default server block; ours is in `conf.d/duynhlab.conf` |
| `health` reports connection refused | Service not started or wrong port | `duynhctl start <svc>`; check `duynhctl ports` |
| `db-setup bootstrap` errors `SUPERUSER_DSN` | Env var not exported | `export SUPERUSER_DSN=postgresql://postgres:…` |
| `db-setup` errors `DB_PASSWORD empty` | Env file not generated | Reinstall, or run `duynhpass` |

See [install.md](002-install.md) for first-time setup and [architecture.md](001-architecture.md)
for the systemd/DB model.
