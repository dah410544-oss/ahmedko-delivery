-- AHMEDKO DELIVERY: enable live catalog events for the public restaurant catalog.
-- This migration changes only the Supabase Realtime publication; it does not
-- alter catalog rows, table schemas, or Row Level Security policies.
-- Public clients still receive only rows allowed by the existing SELECT policies.

do $$
declare
  table_name text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'Supabase Realtime publication "supabase_realtime" does not exist.';
  end if;

  foreach table_name in array array['stores', 'product_categories', 'products']
  loop
    if to_regclass(format('public.%I', table_name)) is not null
       and not exists (
         select 1
         from pg_catalog.pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = table_name
       ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end
$$;

-- Refresh PostgREST metadata after the migration.
notify pgrst, 'reload schema';
