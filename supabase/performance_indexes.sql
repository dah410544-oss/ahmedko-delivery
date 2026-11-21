-- AHMEDKO DELIVERY: targeted performance indexes
-- Safe, additive migration: no table recreation, row updates, or policy changes.
-- Take a Supabase backup first. Run once in Supabase SQL Editor as project owner.
-- Existing indexes are left intact; IF NOT EXISTS makes this file repeatable by name.

-- Fast newest-first order lists and admin status filters.
create index if not exists orders_created_at_desc_idx
  on public.orders (created_at desc);

create index if not exists orders_status_created_at_desc_idx
  on public.orders (status, created_at desc);

-- Fast server-side price lookup for an active ILS route and vehicle.
create index if not exists delivery_rates_active_route_vehicle_idx
  on public.delivery_rates (pickup_region_id, delivery_region_id, vehicle_type)
  where is_active is true and currency = 'ILS';

-- Optional partner/finance/announcement tables: add indexes only when present.
do $$
begin
  if to_regclass('public.store_users') is not null then
    execute 'create index if not exists store_users_user_store_idx on public.store_users (user_id, store_id)';
  end if;

  if to_regclass('public.store_order_items') is not null then
    execute 'create index if not exists store_order_items_order_idx on public.store_order_items (order_id)';
  end if;

  if to_regclass('public.driver_earnings') is not null then
    execute 'create index if not exists driver_earnings_created_at_desc_idx on public.driver_earnings (created_at desc)';
  end if;

  if to_regclass('public.public_announcements') is not null then
    execute 'create index if not exists public_announcements_created_at_desc_idx on public.public_announcements (created_at desc)';
  end if;
end;
$$;

-- Public restaurant catalog: fast active-store and menu lookups.
do $
begin
  if to_regclass('public.stores') is not null then
    execute 'create index if not exists stores_active_name_idx on public.stores (store_name) where is_active is true';
    execute 'analyze public.stores';
  end if;
  if to_regclass('public.product_categories') is not null then
    execute 'create index if not exists product_categories_active_store_name_idx on public.product_categories (store_id, name) where is_active is true';
    execute 'analyze public.product_categories';
  end if;
  if to_regclass('public.products') is not null then
    execute 'create index if not exists products_available_store_name_idx on public.products (store_id, name) where is_available is true';
    execute 'analyze public.products';
  end if;
end;
$;

-- Refresh planner statistics after adding indexes.
analyze public.orders;
analyze public.delivery_rates;

do $$
begin
  if to_regclass('public.store_users') is not null then
    execute 'analyze public.store_users';
  end if;
  if to_regclass('public.store_order_items') is not null then
    execute 'analyze public.store_order_items';
  end if;
  if to_regclass('public.driver_earnings') is not null then
    execute 'analyze public.driver_earnings';
  end if;
  if to_regclass('public.public_announcements') is not null then
    execute 'analyze public.public_announcements';
  end if;
end;
$$;

notify pgrst, 'reload schema';
