# AlphaPos production readiness

Payment gateway and gateway refund are intentionally outside the current scope.

The repository gate is `scripts/verify_release_readiness.sh`. A production
candidate must run the same command with `ALPHAPOS_RELEASE_MODE=production`.
Set `ALPHAPOS_RUN_SIMULATOR=1` to include a clean iPad Simulator
build/install/launch smoke test in either mode.
Production mode fails closed unless biometric identity/liveness and e-Tax
provider configuration are present and the hardware manifest contains results
from physical devices.

Simulator results prove build, launch, unit and integration behavior only. They
do not certify cameras, liveness, printers, cash drawers, scanners, network
recovery on physical terminals, or acceptance by the Thai Revenue Department.

Hardware evidence belongs in `config/hardware-certification.json`; never add
credentials, biometric templates, customer data, or private keys to that file.

## VPS deployment status (2026-08-25)

- Migrations `20260825000100` through `20260825000500` are applied to the
  production Docker PostgreSQL instance and recorded in `schema_migrations`.
- A pre-deployment custom-format dump and schema dump are retained under
  `/opt/alphapos/backups` with mode `0600`.
- CAS migration smoke tests passed on a restored clone and production inside a
  rolled-back transaction.
- Direct Internet access to Docker-published Kong port `54321` is blocked by
  `alphapos-docker-firewall.service`; public API traffic remains HTTPS-only via
  `https://api.alphaposweb.com`.
- Production release remains fail-closed until physical hardware evidence and
  biometric/e-Tax provider configuration are supplied.
- APNs credential rotation completed on 2026-08-25: production Edge Runtime
  uses key `BC973MVWJ4`; retired key `7PS3J7Y6T8` was revoked after a direct
  APNs provider-authentication check passed without notifying a real device.
