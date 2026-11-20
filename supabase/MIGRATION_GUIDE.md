# AHMEDKO DELIVERY — Supabase migration safety

## Current repository situation

Several SQL files contain overlapping definitions of the customer-order RPC:

- `supabase/create_customer_order.sql`
- `supabase/production_readiness.sql`
- `supabase/driver_order_lifecycle.sql`

The lifecycle and production-readiness files also contain overlapping order/driver logic. They are **not safe to execute in arbitrary order**. Do not run all three as a batch and do not delete any of them until the live database definitions and migration history have been compared.

## Required inspection first

Run `supabase/diagnostics_read_only.sql` in the Supabase SQL Editor. It contains SELECT statements only and reports:

1. Existing table columns and defaults.
2. RLS enabled/forced status.
3. Existing policies.
4. Exact function signatures, definitions, and SECURITY DEFINER settings.
5. Triggers.
6. Relevant indexes.
7. Current business commission and currency.

Save/export every result set. The output is needed to produce one consolidated, idempotent migration that matches the live schema rather than guessing.

## Production invariants

- Keep one Android application ID: `com.ahmedko.delivery`.
- Keep the existing Supabase project and business records.
- Currency is ILS; the configured office commission is 15% unless the manager changes it.
- Driver earnings are the remaining 85% at the current 15% commission.
- Driver status transitions must be authorized server-side and create earnings atomically.
- Public customer checkout must not receive privileged table access.
- Never put a Supabase service-role key, signing key, keystore, or passwords in browser code or Git.

## Release signing

The signed Android workflow requires the four repository Actions secrets documented in `ANDROID_RELEASE_SETUP.md`. Keep the same private keystore for every future update. A debug APK is not an official signed release.

## Do not infer completion

A committed SQL file does not mean it has been applied to Supabase. A successful Android build does not prove the app's real customer, driver, store, and admin workflows are production-ready. Record and verify each separately.
