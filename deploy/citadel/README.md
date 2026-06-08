# Plane CE (OIDC fork) — citadel deployment

Self-hosted Plane with generic OIDC SSO (Keycloak), fronted by citadel's nginx.

## Architecture

```
browser ──TLS──> reverse_proxy (nginx, :443, docker_internal)
                   └─ pm.int.soltysik.net ──> plane-proxy (Caddy :80)
                                                ├─ /          web:3000
                                                ├─ /god-mode  admin:3000
                                                ├─ /spaces    space:3000
                                                ├─ /api /auth api:8000
                                                ├─ /live      live:3000
                                                └─ /uploads   plane-minio:9000
```

- Plane services run on the private `plane` network. Only `plane-proxy` is also on
  `docker_internal`, where nginx reaches it by name. TLS terminates at nginx; the
  wildcard `*.int.soltysik.net` cert is served there.
- `SECURE_PROXY_SSL_HEADER` (production settings) + nginx `X-Forwarded-Proto` +
  Caddy `trusted_proxies` make Django see HTTPS, so OIDC `redirect_uri` is correct.

## Images

`api`, `web`, `admin` are built locally from this fork (contain the OIDC changes).
`space`, `live`, `proxy` are unchanged from v1.3.1 and pulled from `makeplane/*`.

```bash
cd ~/agent-work/plane
git checkout feat/oidc-keycloak && git pull
docker build -t plane-oidc/api:v1.3.1-oidc   -f apps/api/Dockerfile.api   apps/api
docker build -t plane-oidc/web:v1.3.1-oidc   -f apps/web/Dockerfile.web   .
docker build -t plane-oidc/admin:v1.3.1-oidc -f apps/admin/Dockerfile.admin .
```

## Deploy

```bash
# /srv/plane holds the operational compose + secrets (not in git).
cp deploy/citadel/docker-compose.yml /srv/plane/
cp deploy/citadel/backup.sh /srv/plane/ && chmod +x /srv/plane/backup.sh
# create /srv/plane/plane.env from plane.env.example (chmod 600)
cp deploy/citadel/nginx-pm.conf /srv/nginx/sites/pm   # then reload reverse_proxy

cd /srv/plane
docker compose up -d
docker compose run --rm migrator     # first run + every upgrade
```

First admin user is created via the god-mode setup at `/god-mode` on first visit.

## OIDC / Keycloak

Client `plane` in realm `soltysik-int` (confidential, standard flow):
- Redirect URI: `https://pm.int.soltysik.net/auth/oidc/callback/`
- Web origin:   `https://pm.int.soltysik.net`

OIDC is seeded via `plane.env` (`IS_OIDC_ENABLED`, `OIDC_CLIENT_ID/SECRET`,
`OIDC_ISSUER_URL`). It can also be managed at `/god-mode` → Authentication → OIDC.

## Backups

`backup.sh` dumps Postgres + tars MinIO uploads to `/srv/plane/backups`
(keeps 14). Run it on a daily timer **and before every upgrade**.

## Upgrade procedure (IMPORTANT)

Plane has a documented history of migration breakage and is mid-restructure, so
upgrades are a maintenance event, not `docker pull`:

1. `bash /srv/plane/backup.sh` — verified backup first.
2. Rebase the fork's `feat/oidc-keycloak` onto the new upstream tag. The OIDC
   patch touches auth (api), the admin auth UI, the web OAuth hook, and shared
   types — expect rebase conflicts there; re-port rather than assume clean.
3. Rebuild the three images, `docker compose up -d`, `docker compose run --rm migrator`.
4. Re-test the OIDC round-trip (login via Keycloak).

Pin to a release tag; do not track `preview`.
