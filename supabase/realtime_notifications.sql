-- AHMEDKO DELIVERY: enable Supabase Realtime events for live office alerts.
-- Run once in Supabase SQL Editor after reviewing the project tables.
-- Realtime respects table RLS; only authorized users should receive row events.
do $$
declare
  table_name text;
  target regclass;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication is not present; enable Realtime in Supabase first.';
    return;
  end if;

  foreach table_name in array array['orders','drivers','store_orders'] loop
    target := to_regclass('public.' || table_name);
    if target is not null and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table %s', target);
      raise notice 'Added public.% to supabase_realtime', table_name;
    end if;
    if target is not null then
      execute format('alter table %s replica identity full', target);
    end if;
  end loop;
end $$;
