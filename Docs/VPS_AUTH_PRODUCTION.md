# VPS Auth — Production Standard

AlphaPos production auth must never emit `127.0.0.1:54321` links in signup / password-reset emails.

## Canonical production values

| Setting | Value |
|---|---|
| `external_url` | `https://api.alphaposweb.com/auth/v1` |
| `site_url` | `https://alphaposweb.com/auth/callback` |
| Email verify link | `https://api.alphaposweb.com/auth/v1/verify` |
| Redirect after verify | HTTPS bridge → `alphapos://auth/callback` (opens iOS app) |

The HTTPS bridge page (`/var/www/alphaposweb/auth/callback/`) exists because desktop browsers cannot open custom URL schemes cleanly and would otherwise show a blank page after `/auth/v1/verify`.

Local Mac dev keeps `supabase/config.toml` on localhost — that file is **not** copied blindly to VPS.

## After every VPS `supabase start`

```bash
cd /opt/alphapos
./scripts/fix-vps-auth-urls.sh apply
./scripts/fix-vps-auth-urls.sh verify
./scripts/vps-configure.sh
```

Or from your Mac:

```bash
./scripts/deploy-vps-auth-production.sh
```

## Commands

```bash
./scripts/fix-vps-auth-urls.sh status   # expected vs running
./scripts/fix-vps-auth-urls.sh verify   # exit 1 if misconfigured
./scripts/fix-vps-auth-urls.sh apply    # patch + restart only when needed
```

## CI / monitoring

Use `verify` in deploy pipelines. It fails when:

- auth container is down
- mailer paths still contain `127.0.0.1:54321`
- `GOTRUE_SITE_URL` is not `https://alphaposweb.com/auth/callback`

## iOS requirement

Production email deep links require an AlphaPos build that registers the `alphapos://` URL scheme and handles `auth/callback`.
