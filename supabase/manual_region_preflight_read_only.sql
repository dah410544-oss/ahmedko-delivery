-- AHMEDKO DELIVERY: READ-ONLY preflight for manual pickup/delivery regions.
-- Safe to run in Supabase SQL Editor. SELECT statements only; no schema or data changes.

-- 1) Confirm nullable columns and exact types used by the manual-region RPC.
select
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'orders' and column_name in (
      'id', 'customer_name', 'customer_phone', 'pickup_address',
      'delivery_address', 'order_type', 'notes', 'status',
      'delivery_price', 'pickup_region_id', 'delivery_region_id',
      'vehicle_type', 'created_at'
    ))
    or (table_name = 'regions' and column_name in ('id', 'name', 'is_active'))
    or (table_name = 'delivery_rates' and column_name in (
      'pickup_region_id', 'delivery_region_id', 'vehicle_type',
      'price', 'is_active', 'currency'
    ))
  )
order by table_name, ordinal_position;

-- 2) Inspect constraints that could reject a manual-region order or a NULL fee.
select
  c.relname as table_name,
  con.conname as constraint_name,
  con.contype::text as constraint_type,
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('orders', 'regions', 'delivery_rates')
order by c.relname, con.conname;

-- 3) Inspect existing order triggers before changing the order RPC.
select
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'orders'
  and not t.tgisinternal
order by t.tgname;
