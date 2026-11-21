-- AHMEDKO DELIVERY: read-only partner portal schema inspection.
-- This query does NOT create, alter, update, or delete anything.
-- Run in Supabase SQL Editor and share the result before implementing partner login/order access.

with target_tables(table_name) as (
  values
    ('stores'),
    ('store_users'),
    ('store_orders'),
    ('store_order_items'),
    ('branches'),
    ('branch_users'),
    ('products'),
    ('product_categories'),
    ('orders'),
    ('user_roles')
),
columns_info as (
  select
    'columns'::text as section,
    c.table_name as object_name,
    jsonb_agg(
      jsonb_build_object(
        'column', c.column_name,
        'type', c.data_type,
        'udt', c.udt_name,
        'nullable', c.is_nullable,
        'default', c.column_default
      ) order by c.ordinal_position
    ) as details
  from information_schema.columns c
  join target_tables t on t.table_name = c.table_name
  where c.table_schema = 'public'
  group by c.table_name
),
policies_info as (
  select
    'policies'::text as section,
    p.tablename as object_name,
    jsonb_agg(
      jsonb_build_object(
        'name', p.policyname,
        'command', p.cmd,
        'roles', p.roles,
        'using', p.qual,
        'with_check', p.with_check
      ) order by p.policyname
    ) as details
  from pg_policies p
  join target_tables t on t.table_name = p.tablename
  where p.schemaname = 'public'
  group by p.tablename
),
constraints_info as (
  select
    'constraints'::text as section,
    c.relname::text as object_name,
    jsonb_agg(
      jsonb_build_object(
        'name', con.conname,
        'type', con.contype,
        'definition', pg_get_constraintdef(con.oid)
      ) order by con.conname
    ) as details
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  join target_tables t on t.table_name = c.relname
  where n.nspname = 'public'
  group by c.relname
),
rls_info as (
  select
    'rls'::text as section,
    c.relname::text as object_name,
    jsonb_build_object(
      'enabled', c.relrowsecurity,
      'forced', c.relforcerowsecurity
    ) as details
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join target_tables t on t.table_name = c.relname
  where n.nspname = 'public'
    and c.relkind = 'r'
)
select section, object_name, details from columns_info
union all
select section, object_name, details from policies_info
union all
select section, object_name, details from constraints_info
union all
select section, object_name, details from rls_info
order by section, object_name;
