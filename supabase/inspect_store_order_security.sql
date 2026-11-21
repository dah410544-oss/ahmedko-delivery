-- AHMEDKO DELIVERY: read-only restaurant order security inspection.
-- This query does NOT create, alter, update, or delete anything.
-- Run in Supabase SQL Editor and share the result before enabling restaurant order actions.

with target_tables(table_name) as (
  values ('store_orders'), ('store_order_items'), ('store_users'),
         ('stores'), ('products'), ('product_categories')
),
table_grants as (
  select
    'grants'::text as section,
    table_name::text as object_name,
    jsonb_agg(jsonb_build_object(
      'grantee', grantee,
      'privilege', privilege_type,
      'grantable', is_grantable
    ) order by grantee, privilege_type) as details
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name in (select table_name from target_tables)
  group by table_name
),
triggers_info as (
  select
    'triggers'::text as section,
    c.relname::text as object_name,
    jsonb_agg(jsonb_build_object(
      'trigger', t.tgname,
      'definition', pg_get_triggerdef(t.oid, true),
      'enabled', t.tgenabled
    ) order by t.tgname) as details
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (select table_name from target_tables)
    and not t.tgisinternal
  group by c.relname
),
functions_info as (
  select
    'functions'::text as section,
    p.proname::text as object_name,
    jsonb_agg(jsonb_build_object(
      'arguments', pg_get_function_identity_arguments(p.oid),
      'returns', pg_get_function_result(p.oid),
      'security_definer', p.prosecdef,
      'definition', pg_get_functiondef(p.oid)
    ) order by p.oid) as details
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (
      p.proname ilike '%store%'
      or p.proname ilike '%branch%'
      or p.proname in ('is_admin')
    )
  group by p.proname
),
status_values as (
  select
    'store_order_status_values'::text as section,
    'store_orders'::text as object_name,
    coalesce(jsonb_agg(status_value order by status_value), '[]'::jsonb) as details
  from (
    select distinct status as status_value
    from public.store_orders
    order by status
    limit 100
  ) s
),
foreign_keys as (
  select
    'foreign_keys'::text as section,
    c.relname::text as object_name,
    jsonb_agg(jsonb_build_object(
      'name', con.conname,
      'definition', pg_get_constraintdef(con.oid)
    ) order by con.conname) as details
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (select table_name from target_tables)
    and con.contype = 'f'
  group by c.relname
)
select section, object_name, details from table_grants
union all
select section, object_name, details from triggers_info
union all
select section, object_name, details from functions_info
union all
select section, object_name, details from status_values
union all
select section, object_name, details from foreign_keys
order by section, object_name;
