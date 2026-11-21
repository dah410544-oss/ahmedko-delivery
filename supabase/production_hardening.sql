-- AHMEDKO DELIVERY: close direct anonymous order-table inserts
-- Run after driver_order_lifecycle.sql, as the Supabase project owner.
-- Customer orders must be created only through create_customer_order(),
-- which validates fields and calculates the price on the database side.

revoke insert on table public.orders from public;
revoke insert on table public.orders from anon;
revoke insert on table public.orders from authenticated;

-- Do not expose raw customer order rows to anonymous clients.
revoke select on table public.orders from public;
revoke select on table public.orders from anon;

-- The authenticated admin dashboard and approved-driver portal rely on
-- existing RLS policies. This migration intentionally does not grant broad
-- SELECT/UPDATE rights and does not change those existing policies.

comment on table public.orders is
  'Customer order records. Public clients create orders only through the validated create_customer_order RPC; row visibility and updates are controlled by RLS.';
