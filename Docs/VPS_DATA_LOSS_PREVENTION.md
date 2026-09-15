# VPS production data-loss controls

Incident baseline: on 2026-08-28 the Supabase CLI stopped the production stack
and the PostgreSQL Docker volume was recreated. Production must not be managed
with the local-development database lifecycle.

## Forbidden on production

Never run `supabase stop`, `supabase stop --no-backup`, or
`supabase db reset`. The installed `/usr/local/bin/supabase` guard blocks these
commands and writes the attempt to the persistent system journal.

Restart only the affected container, for example `docker restart
supabase_auth_AlphaPos`. A database container restart requires a fresh verified
backup and a maintenance window. Never remove `supabase_db_AlphaPos` or its
volume.

## Automated controls

- `alphapos-production-backup.timer`: verified custom-format dump every six
  hours, SHA-256 checksum, count manifest, 30-day retention, a 5 GB hard cap,
  and a 10 GB minimum-free-space guard.
- `alphapos-db-integrity-guard.timer`: compares auth, merchant, branch, menu,
  and inventory row counts every five minutes and alerts on any decrease.
- journald uses persistent storage so guard and deployment evidence survives a
  reboot.

Backups are written to `/var/backups/alphapos/postgres`. Set
`ALPHAPOS_BACKUP_REMOTE` in the backup service environment to an rclone remote
on a different provider/host. An on-host backup alone does not protect against
disk or VPS loss.

## Before database maintenance

1. Run `systemctl start alphapos-production-backup.service`.
2. Verify the service succeeded and check the newest SHA-256 file.
3. Record current row counts from the newest manifest.
4. Apply additive migrations through `psql` inside the existing DB container.
5. Run the integrity guard and application smoke tests.

PITR requires a WAL archive located outside the Docker volume and outside this
VPS. Do not enable WAL archiving to the same volume and call it a backup.
