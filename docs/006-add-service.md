# Adding a New Service

How to onboard a new backend service (example used throughout: `payments`,
HTTP port **8009**) into the mega-RPM. [`services.yaml`](../services.yaml) is
the declared source of truth, but several places still hardcode the service
list — §3 is the honest checklist of every one of them.

## 1. Service repo prerequisites

The packages repo only *repacks* — the service repo must follow the duynhlab
conventions or the pipeline can't build/run it:

- **Go service** with `main` at `./cmd` (overridable via `build_path`), builds
  with `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`.
- **Migrations embedded in the binary**: `db/migrations/sql/000NNN_*.up.sql`
  (forward-only, no `.down.sql`), embedded via `//go:embed` and applied by the
  binary's own `migrate` subcommand through `github.com/duynhlab/pkg/migratex`.
  `duynhdb migrate payments` execs exactly that.
- **Config via discrete env vars** (no `DATABASE_URL`): `DB_HOST DB_PORT
  DB_NAME DB_USER DB_PASSWORD DB_SSLMODE`, plus `PORT` (and `GRPC_PORT` if it
  serves gRPC). Defaults of 8080/9090 in code are fine — the RPM overrides
  them per service.
- **`GET /health`** returning 200 on the HTTP port — `duynhctl health` and
  the integration test poll it.
- Logs to stdout/stderr (journald captures them).

## 2. The declarative step — `services.yaml`

```yaml
  - name: payments
    repo: duynhlab/payments-service
    src_dir: payments-service
    binary: payments-service
    build_path: ./cmd
    port: 8009
    # grpc_port: 9009        # only if it runs a gRPC server
    type: backend
    database:
      name: duynhlab_payments
      app_user: duynhlab_payments_app
      migrator_user: duynhlab_payments_migrator
    dependencies:
      after: []
      env_files: []
```

This alone makes the **dynamic** parts pick the service up (see §4).

## 3. The hardcoded touch points — checklist

> These are known SSOT gaps (see the automation backlog note in §7). Until they
> are generated from `services.yaml`, every new service must edit ALL of them.
> Line numbers are indicative — search for the 8-service list nearby.

| # | File | Where | What to add |
|---|---|---|---|
| 1 | `packages/rpm/duynhlab.spec` | `%check` ELF loop (~106) | `payments` in the `for svc in …` list |
| 2 | `packages/rpm/duynhlab.spec` | `%post` systemd preset loop (~151) | same |
| 3 | `packages/rpm/duynhlab.spec` | `%post` first-install hint heredoc (~170) | same (cosmetic) |
| 4 | `packages/rpm/duynhlab.spec` | `%preun` stop loop (~196) | same |
| 5 | `packages/rpm/duynhlab.spec` | `%postun` restart loop (~207) | same |
| 6 | `packages/rpm/duynhlab.spec` | `%files` payload dirs (~219) | `%{duynhlab_prefix}/payments` |
| 7 | `packages/rpm/duynhlab.spec` | `%files` ghost env list (~262) | `%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/payments.env` |
| 8 | `packages/rpm/lib/init-service.sh` | `BACKENDS` array (~19) | `payments` |
| 9 | `packages/rpm/secret-tpl/payments.env.tpl` | **new file** | copy `auth.env.tpl`, set `SERVICE_NAME`/`PORT=8009`/(`GRPC_PORT`)/`DB_NAME=duynhlab_payments`/`DB_USER=duynhlab_payments_app`/migrator names; keep `__DB_PASSWORD__` placeholders |
| 10 | `scripts/test-integration.sh` | `BACKENDS` array (~50) | `payments` |
| 11 | `scripts/test-integration.sh` | `PORTS` map (~51) | `[payments]=8009` |
| 12 | `scripts/test-integration.sh` | pod port-publish loop (~78) | `8009` |
| 13 | `scripts/test-install.sh` | binary-check loop (~62), `expected_services` (~107), env-file loop (~122), log-dir loop (~148) | `payments` in all four |
| 14 | `packages/rpm/nginx/duynhlab.conf` | upstream block (~5) + location block (~50) | `upstream duynhlab_payments { server 127.0.0.1:8009; }` and `location /api/payments/ { proxy_pass http://duynhlab_payments/; }` |

Grep guard before committing — every hardcoded list should now contain the new
name:

```bash
grep -rn "notification shipping" scripts/ packages/ | grep -v payments && echo "MISSED A SPOT" || echo OK
```

## 4. What you do NOT touch (dynamic — driven by services.yaml)

`fetch-sources.sh`, `build-local.sh`, `render-systemd.sh` (unit + platform
target), `stage-all.sh` (staging + composition manifest), `Makefile
build-local-all`, `duynhctl` (list/health/ports), `password-generator.sh`
(scans `secret-tpl/*.env.tpl`), `duynhdb` (per-service args),
`bootstrap.sql`. They all iterate the registry — no edits needed.

## 5. Build & verify locally

```bash
make fetch-sources                      # clones payments-service alongside
make build-local SERVICE=payments       # binary tarball + build-info.env
make build-local-all                    # or rebuild everything
make build                              # mega-RPM with payments inside
make test-install                       # asserts the new loops you edited in §3
make test-integration                   # boots all backends incl. payments, /health ×9
```

`test-install` failing on a missing binary/env/unit usually means you missed a
§3 touch point — the error names the file.

## 6. Database + first run, then ship

On a test host (or in the integration container):

```bash
SUPERUSER_DSN="postgresql://postgres:…@localhost:5432/postgres" \
  sudo -E duynhdb bootstrap payments
sudo duynhdb migrate payments
sudo systemctl start duynhlab-payments && curl -fsS localhost:8009/health
```

Ship: open the PR (CI runs the same `test-install`; the integration test runs
after merge), then cut a release per [`005-release.md`](005-release.md) —
`make release`. The new service appears in the release's composition manifest
automatically.

## 7. Automation note

Touch points 1–8 and 10–14 exist because the spec/test/nginx files predate the
registry. Generating them from `services.yaml` is tracked in the internal
backlog (`plan-spec.md` B5 render-nginx + B16 render hardcoded lists). If you
automate one of them, delete its row from §3.
