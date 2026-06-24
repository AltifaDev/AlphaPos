# Supabase Local via Docker

`supabase/migrations` is the only executable migration source. The older
`Database/migrations` directory is retained only as historical reference and
must not be copied back into the Supabase migration path.

## Daily use

```sh
./scripts/supabase-local.sh start
./scripts/supabase-local.sh verify
./scripts/supabase-local.sh backup
./scripts/supabase-local.sh stop
```

`start` detects the Mac LAN address, updates the ignored app configuration
files, and provisions the Vault values used by the order notification webhook.
Run `configure` again whenever the Mac receives a new LAN address.

Physical iPads, iPhones, and customer phones must be on the same network as
the Mac. `127.0.0.1` is valid only for the simulator or a browser on the Mac.

## Schema changes

Migration filenames use a 14-digit UTC timestamp. Never edit or rename a
migration after it has been shared or applied outside this rebuilt Local
baseline. Add a new, monotonically increasing timestamp and verify it with:

```sh
supabase db reset
./scripts/supabase-local.sh configure
./scripts/supabase-local.sh verify
```

`db reset` deletes local data, so create a backup first if the data matters.

## First-time setup / resetting after migration lineage fix

The migration set was rebuilt from scratch on 2026-06-22 using 14-digit UTC
timestamps to fix the broken lexicographic ordering from the legacy short-name
scheme (`009`, `0093`, `016`, `0162`, …).  All 35 migrations are monotonically
ordered and apply cleanly from a fresh `db reset`.

```sh
# Back up any data you want to keep first
./scripts/supabase-local.sh backup

# Wipe and replay all migrations from scratch
supabase db reset

# Provision Vault secrets and update app Config.plist / .env
./scripts/supabase-local.sh configure

# Confirm migration list, lint, and service status
./scripts/supabase-local.sh verify
```

## Migration overview (35 migrations)

| Range | Date | Content |
|---|---|---|
| 0001–0004 | 2026-06-09 | Initial schema, extended columns, missing tables, printer routing |
| 0005–0010 | 2026-06-11 | Table sessions sync, elapsed time, PromptPay, face embedding, device secret, restaurant walls |
| 0011–0016 | 2026-06-14 | Enterprise compliance, header fallback, audit logging, register sessions, table settings, sync alignment |
| 0017–0029 | 2026-06-15 | RLS policies, promotion engine, archiving, staff permissions, localization, floor plan, media, order reliability, webhook, sync fixes |
| 0033–0035 | 2026-06-22 | **Local Docker hardening** (session_token, get_table_guest_count fix, archive proc, RLS), **configurable webhook** (Vault-based URL), **explicit API privileges** (auto-grant + catalog read + SECURITY DEFINER checkout) |

## Key schema decisions

### Row Level Security
Every table with a `merchant_id` column has RLS enabled and a `tenant_isolation`
policy gating reads and writes by `public.get_active_merchant_id()`.  Archive
tables (`*_archive`) are internal-only and excluded from the auto-grant loop.

### Customer checkout (anon)
`create_customer_order` is `SECURITY DEFINER` and accepts orders from anonymous
customers provided a valid `session_token` matching an active `table_sessions`
row for the given merchant/table.  No merchant JWT is required for web ordering.

### Order push webhook
`trg_send_order_push` fires `AFTER INSERT` on `orders` and calls the
`send-order-push` Edge Function via `net.http_post`.  The base URL and
service-role key are read from Vault at runtime so the same trigger works for
both Local Docker (`http://kong:8000`) and hosted Supabase
(`https://<project>.supabase.co`).

## Push notifications

The webhook is configured automatically by `scripts/supabase-local.sh configure`,
which writes `service_role_key` and `edge_function_base_url` into Vault.

APNs delivery additionally needs `APNS_KEY_ID`, `APNS_TEAM_ID`,
`APNS_PRIVATE_KEY`, and the two bundle IDs in the Edge Function environment.
Missing APNs credentials produce a clear 503 and do not roll back customer
orders.

For hosted Supabase, store the hosted project URL as Vault secret
`edge_function_base_url` and its service-role key as `service_role_key`.

## End-to-end test checklist

After `db reset` + `configure`, verify each flow before considering Local ready:

- [ ] Customer web order: place order from browser → appears in iPad POS
- [ ] iOS sync: create menu item on iPad → visible in Supabase Studio
- [ ] RLS: `anon` key can read catalogue but cannot read another merchant's orders
- [ ] Push: new order triggers Edge Function call (check Supabase function logs)
- [ ] Archive: `CALL archive_historical_data(1)` completes without error
