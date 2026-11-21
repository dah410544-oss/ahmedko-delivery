-- AHMEDKO DELIVERY: read-only live database diagnostics
-- Safe to run in Supabase SQL Editor. This script does not create, alter,
-- update, delete, grant, revoke, or change any database setting.
-- Run against the AHMEDKO-DELIVERY project and review every result set.

-- 1) Core and partner table presence + RLS state.
with expected(table_name, purpose) as (
  values
    ('orders','Customer delivery orders'),
    ('drivers','Driver profiles and approvals'),
    ('driver_earnings','Driver settlements'),
    ('delivery_rates','Route and vehicle pricing'),
    ('regions','Pickup and delivery zones'),
    ('business_settings','Office commission and currency'),
    ('stores','Restaurant/store directory'),
    ('product_categories','Restaurant menu categories'),
    ('products','Restaurant menu items'),
    ('store_users','Restaurant account-to-store access'),
    ('store_orders','Restaurant order inbox'),
    ('store_order_items','Restaurant order line items'),
    ('public_announcements','Public notices')
)
select
  e.table_name,
  e.purpose,
  (c.oid is not null) as exists,
  coalesce(c.relrowsecurity, false) as rls_enabled,
  coalesce(c.relforcerowsecurity, false) as rls_forced
from expected e
left join pg_namespace n on n.nspname = 'public'
left join pg_class c on c.relnamespace = n.oid
  and c.relname = e.table_name
  and c.relkind in ('r','p')
order by e.table_name;

-- 2) Actual columns for the expected tables (no assumptions about optional columns).
select
  table_name,
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'orders','drivers','driver_earnings','delivery_rates','regions',
    'business_settings','stores','product_categories','products',
    'store_users','store_orders','store_order_items','public_announcements',
    'user_roles'
  )
order by table_name, ordinal_position;

-- 3) Existing RLS policies on relevant tables.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'orders','drivers','driver_earnings','delivery_rates','regions',
    'business_settings','stores','product_categories','products',
    'store_users','store_orders','store_order_items','public_announcements',
    'user_roles'
  )
order by tablename, policyname;

-- 4) Existing indexes on high-traffic tables.
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in (
    'orders','delivery_rates','drivers','driver_earnings',
    'stores','product_categories','products','store_orders','store_order_items'
  )
order by tablename, indexname;

-- 5) Important RPC functions and whether they are SECURITY DEFINER.
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  coalesce(array_to_string(p.proacl, ', '), '(default privileges)') as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'is_admin',
    'create_customer_order',
    'get_my_customer_orders',
    'driver_update_order_status',
    'restaurant_update_order_status',
    'create_store_order_for_delivery'
  )
order by p.proname, arguments;

-- 6) Realtime publication membership for the public catalog.
select
  t.tablename,
  exists (
    select 1
    from pg_publication_tables p
    where p.pubname = 'supabase_realtime'
      and p.schemaname = 'public'
      and p.tablename = t.tablename
  ) as included_in_supabase_realtime
from (values ('stores'),('product_categories'),('products')) as t(tablename)
order by t.tablename;

-- 7) Active catalog counts (returns zero when an optional table is absent).
select
  (select count(*) from public.stores where is_active is true) as active_stores,
  case when to_regclass('public.product_categories') is not null
    then (select count(*) from public.product_categories where is_active is true)
    else null end as active_menu_categories,
  case when to_regclass('public.products') is not null
    then (select count(*) from public.products where is_available is true)
    else null end as available_menu_products;

-- 8) Office settings: inspect only the business values needed for release checks.
select *
from public.business_settings
order by 1
limit 20;

-- End of read-only diagnostics.
