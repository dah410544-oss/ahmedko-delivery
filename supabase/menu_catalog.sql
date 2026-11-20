-- AHMEDKO DELIVERY: restaurant/store menu catalog
-- Idempotent migration: creates the catalog tables only when absent.
-- Existing stores and menu data are preserved.
-- Run once in Supabase SQL Editor as project owner.

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint product_categories_store_name_unique unique (store_id, name)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  category_id uuid references public.product_categories(id) on delete set null,
  name text not null check (char_length(trim(name)) between 1 and 140),
  description text,
  price numeric(10,2) null check (price is null or price >= 0),
  is_available boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists product_categories_store_active_idx
  on public.product_categories (store_id, is_active);
create index if not exists products_store_available_idx
  on public.products (store_id, is_available);
create index if not exists products_category_idx
  on public.products (category_id);

alter table public.product_categories enable row level security;
alter table public.products enable row level security;

drop policy if exists "Public reads active store categories" on public.product_categories;
create policy "Public reads active store categories"
on public.product_categories for select
to anon, authenticated
using (
  is_active is true
  and exists (
    select 1 from public.stores s
    where s.id = product_categories.store_id
      and s.is_active is true
  )
);

drop policy if exists "Admins manage product categories" on public.product_categories;
create policy "Admins manage product categories"
on public.product_categories for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Public reads available store products" on public.products;
create policy "Public reads available store products"
on public.products for select
to anon, authenticated
using (
  is_available is true
  and exists (
    select 1 from public.stores s
    where s.id = products.store_id
      and s.is_active is true
  )
  and (
    category_id is null
    or exists (
      select 1 from public.product_categories c
      where c.id = products.category_id
        and c.is_active is true
    )
  )
);

drop policy if exists "Admins manage products" on public.products;
create policy "Admins manage products"
on public.products for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select on public.product_categories, public.products to anon, authenticated;
grant insert, update, delete on public.product_categories, public.products to authenticated;

notify pgrst, 'reload schema';
