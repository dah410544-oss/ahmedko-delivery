-- AHMEDKO DELIVERY: read-only production inventory.
-- SAFE: SELECT statements only. Does not create, alter, update, delete, or grant anything.
-- Run in Supabase SQL Editor and inspect ALL result sets before preparing any migration.

-- 1) Existing columns and defaults for the core business tables.
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'business_settings', 'delivery_rates', 'driver_earnings', 'drivers',
    'orders', 'regions', 'stores', 'store_users', 'store_orders',
    'store_order_items', 'branches', 'branch_users', 'products',
    'product_categories'
  )
order by table_name, ordinal_position;

-- 2) RLS enabled/forced state for those tables.
select c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relname in (
    'business_settings', 'delivery_rates', 'driver_earnings', 'drivers',
    'orders', 'regions', 'stores', 'store_users', 'store_orders',
    'store_order_items', 'branches', 'branch_users', 'products',
    'product_categories'
  )
order by c.relname;

-- 3) Existing policies: roles, commands, USING and WITH CHECK expressions.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'business_settings', 'delivery_rates', 'driver_earnings', 'drivers',
    'orders', 'regions', 'stores', 'store_users', 'store_orders',
    'store_order_items', 'branches', 'branch_users', 'products',
    'product_categories'
  )
order by tablename, policyname;

-- 4) Existing application functions and exact definitions/security settings.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer,
       p.proconfig as function_settings,
       pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'create_customer_order', 'driver_update_order_status',
    'get_available_drivers', 'is_admin', 'calculate_driver_earnings'
  )
order by p.proname, pg_get_function_identity_arguments(p.oid);

-- 5) Triggers on order, driver, and finance tables.
select event_object_table as table_name,
       trigger_name,
       action_timing,
       event_manipulation,
       action_statement
from information_schema.triggers
where trigger_schema = 'public'
  and event_object_table in ('orders', 'drivers', 'driver_earnings')
order by event_object_table, trigger_name, event_manipulation;

-- 6) Existing indexes relevant to order assignment and one-earning-per-order integrity.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('orders', 'drivers', 'driver_earnings', 'delivery_rates')
order by tablename, indexname;

-- 7) Current office commission setting (read-only; should remain 15% unless manager changed it).
select office_commission_percent, currency
from public.business_settings
order by created_at nulls first
limit 10;
