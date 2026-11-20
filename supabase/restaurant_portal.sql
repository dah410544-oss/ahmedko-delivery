-- AHMEDKO restaurant order handoff and guarded status transitions.
-- Uses the EXISTING stores/store_users/store_orders/store_order_items tables.
-- Run once in Supabase SQL Editor after reviewing a backup.

alter table public.store_orders
  add column if not exists delivery_order_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.store_orders'::regclass
      and conname = 'store_orders_delivery_order_id_fkey'
  ) then
    alter table public.store_orders
      add constraint store_orders_delivery_order_id_fkey
      foreign key (delivery_order_id) references public.orders(id) on delete set null;
  end if;
end $$;

create unique index if not exists store_orders_delivery_order_id_uidx
  on public.store_orders(delivery_order_id)
  where delivery_order_id is not null;

create index if not exists store_orders_store_created_idx
  on public.store_orders(store_id, created_at desc);

-- Never allow browser clients to edit totals, ownership, items, or status directly.
revoke insert, update, delete on public.store_orders from anon, authenticated;
revoke insert, update, delete on public.store_order_items from anon, authenticated;
grant select on public.store_orders, public.store_order_items to authenticated;

create or replace function public.create_store_order_for_delivery(
  p_store_id uuid,
  p_delivery_order_id uuid,
  p_items jsonb,
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_notes text default null
)
returns table(store_order_id uuid, subtotal numeric, total numeric)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_store_order_id uuid;
  v_subtotal numeric(12,2);
  v_item_count integer;
  v_matched_count integer;
begin
  if p_store_id is null or p_delivery_order_id is null then
    raise exception 'بيانات المتجر أو طلب التوصيل غير مكتملة';
  end if;
  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 50 then
    raise exception 'قائمة المنتجات غير صالحة';
  end if;
  if length(trim(coalesce(p_customer_name,''))) not between 2 and 100
     or length(trim(coalesce(p_customer_phone,''))) not between 7 and 20
     or length(trim(coalesce(p_delivery_address,''))) not between 3 and 300 then
    raise exception 'بيانات العميل أو عنوان التسليم غير صالحة';
  end if;

  if not exists (
    select 1 from public.stores s
    where s.id = p_store_id and s.is_active is true
  ) then
    raise exception 'المتجر غير متاح حالياً';
  end if;

  if not exists (
    select 1 from public.orders o
    where o.id = p_delivery_order_id
      and o.order_type = 'restaurant_order'
      and lower(trim(o.customer_name)) = lower(trim(p_customer_name))
      and regexp_replace(o.customer_phone, '\D', '', 'g') = regexp_replace(p_customer_phone, '\D', '', 'g')
      and trim(o.delivery_address) = trim(p_delivery_address)
  ) then
    raise exception 'تعذر مطابقة طلب التوصيل مع بيانات طلب المطعم';
  end if;

  select count(*), count(distinct x.product_id)
    into v_item_count, v_matched_count
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer);

  if v_item_count < 1 or v_item_count > 50
     or v_matched_count <> v_item_count
     or exists (
       select 1 from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
       where x.product_id is null or x.quantity is null or x.quantity not between 1 and 99
     ) then
    raise exception 'يوجد صنف مكرر أو كمية غير صالحة';
  end if;

  select round(sum(p.price * x.quantity), 2), count(*)
    into v_subtotal, v_matched_count
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
  join public.products p
    on p.id = x.product_id
   and p.store_id = p_store_id
   and p.is_available is true;

  if v_matched_count <> v_item_count or v_subtotal is null then
    raise exception 'بعض المنتجات لم تعد متاحة؛ حدّث المنيو وحاول مجدداً';
  end if;

  insert into public.store_orders (
    store_id, customer_id, customer_name, customer_phone,
    delivery_address, notes, subtotal, delivery_fee, total, status, delivery_order_id
  )
  values (
    p_store_id, auth.uid(), trim(p_customer_name), trim(p_customer_phone),
    trim(p_delivery_address), nullif(trim(coalesce(p_notes,'')), ''),
    v_subtotal, 0, v_subtotal, 'pending', p_delivery_order_id
  )
  returning id into v_store_order_id;

  insert into public.store_order_items (
    order_id, product_id, product_name, unit_price, quantity
  )
  select v_store_order_id, p.id, p.name, p.price, x.quantity
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
  join public.products p
    on p.id = x.product_id
   and p.store_id = p_store_id
   and p.is_available is true;

  return query select v_store_order_id, v_subtotal, v_subtotal;
end;
$$;

create or replace function public.restaurant_update_order_status(
  p_order_id uuid,
  p_new_status text
)
returns table(order_id uuid, status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_store_id uuid;
  v_current_status text;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  select o.store_id, o.status
    into v_store_id, v_current_status
  from public.store_orders o
  where o.id = p_order_id
    and exists (
      select 1 from public.store_users su
      where su.store_id = o.store_id and su.user_id = auth.uid()
    )
    and exists (
      select 1 from public.stores s
      where s.id = o.store_id and s.is_active is true
    )
  for update;

  if v_store_id is null then
    raise exception 'الطلب غير موجود أو لا تملك صلاحية الوصول إليه';
  end if;

  if not (
    (v_current_status = 'pending' and p_new_status in ('accepted','rejected'))
    or (v_current_status = 'accepted' and p_new_status in ('preparing','cancelled'))
    or (v_current_status = 'preparing' and p_new_status in ('ready','cancelled'))
    or (v_current_status = 'ready' and p_new_status = 'completed')
  ) then
    raise exception 'انتقال حالة الطلب غير مسموح: % → %', v_current_status, p_new_status;
  end if;

  update public.store_orders
     set status = p_new_status
   where id = p_order_id;

  return query select p_order_id, p_new_status;
end;
$$;

revoke all on function public.create_store_order_for_delivery(uuid,uuid,jsonb,text,text,text,text) from public;
grant execute on function public.create_store_order_for_delivery(uuid,uuid,jsonb,text,text,text,text) to anon, authenticated;
revoke all on function public.restaurant_update_order_status(uuid,text) from public;
grant execute on function public.restaurant_update_order_status(uuid,text) to authenticated;

notify pgrst, 'reload schema';
