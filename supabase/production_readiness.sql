-- AHMEDKO DELIVERY: focused production-readiness migration
-- Run once in Supabase SQL Editor as project owner.
-- Does not recreate tables, policies, indexes, or existing data.

-- Keep driver assignments referentially valid; preserve all existing rows.
create index if not exists orders_driver_id_created_at_idx
  on public.orders (driver_id, created_at desc);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_driver_id_fkey'
  ) then
    if exists (
      select 1
      from public.orders o
      left join public.drivers d on d.id = o.driver_id
      where o.driver_id is not null
        and d.id is null
    ) then
      raise exception 'Orders contain an unknown driver_id. Review those rows before adding the driver foreign key.';
    end if;

    alter table public.orders
      add constraint orders_driver_id_fkey
      foreign key (driver_id) references public.drivers(id) on delete set null;
  end if;
end;
$$;

create or replace function public.create_customer_order(
  p_customer_name text,
  p_customer_phone text,
  p_pickup_address text,
  p_delivery_address text,
  p_pickup_region_id uuid,
  p_delivery_region_id uuid,
  p_vehicle_type text,
  p_order_type text,
  p_notes text default null
)
returns table(order_id uuid, delivery_price numeric)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_price_count integer := 0;
  v_delivery_price numeric := null;
  v_order_id uuid;
  v_notes text;
begin
  if length(trim(coalesce(p_customer_name, ''))) < 2
     or length(trim(coalesce(p_customer_name, ''))) > 100 then
    raise exception 'يرجى إدخال اسم صحيح.';
  end if;
  if length(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g')) < 7
     or length(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g')) > 15 then
    raise exception 'يرجى إدخال رقم هاتف صحيح.';
  end if;
  if length(trim(coalesce(p_pickup_address, ''))) < 3
     or length(trim(coalesce(p_delivery_address, ''))) < 3 then
    raise exception 'عنوان الاستلام والتسليم مطلوبان.';
  end if;
  if p_vehicle_type is null or p_vehicle_type not in ('car','tuk_tuk','bus','electric_bicycle','bicycle','motorcycle') then
    raise exception 'وسيلة النقل المختارة غير صحيحة.';
  end if;

  -- Validate each supplied region ID. NULL means the customer typed a region not yet listed.
  if p_pickup_region_id is not null and not exists (
    select 1 from public.regions r where r.id = p_pickup_region_id and r.is_active is true
  ) then
    raise exception 'منطقة الاستلام المختارة غير مفعّلة أو غير موجودة.';
  end if;
  if p_delivery_region_id is not null and not exists (
    select 1 from public.regions r where r.id = p_delivery_region_id and r.is_active is true
  ) then
    raise exception 'منطقة التسليم المختارة غير مفعّلة أو غير موجودة.';
  end if;

  -- Calculate a fee only when both regions are registered and exactly one active rate exists.
  if p_pickup_region_id is not null and p_delivery_region_id is not null then
    select count(*), min(dr.price)
      into v_price_count, v_delivery_price
    from public.delivery_rates dr
    where dr.pickup_region_id = p_pickup_region_id
      and dr.delivery_region_id = p_delivery_region_id
      and dr.vehicle_type = p_vehicle_type
      and dr.is_active is true
      and dr.currency = 'ILS';

    if v_price_count > 1 then
      raise exception 'يوجد أكثر من سعر نشط لهذا المسار. يجب على الإدارة مراجعة جدول الأسعار.';
    elsif v_price_count = 1 and (v_delivery_price is null or v_delivery_price <= 0) then
      raise exception 'سعر التوصيل المعتمد غير صحيح. يرجى التواصل مع الإدارة.';
    end if;
  end if;

  v_notes := nullif(trim(coalesce(p_notes, '')), '');
  if v_delivery_price is null then
    v_notes := concat_ws(E'\n', v_notes, 'بانتظار تأكيد أجرة التوصيل من مكتب أحمدكو قبل إسناد الطلب للسائق.');
  end if;

  insert into public.orders (
    customer_name, customer_phone, pickup_address, delivery_address,
    order_type, notes, status, delivery_price,
    pickup_region_id, delivery_region_id, vehicle_type
  )
  values (
    trim(p_customer_name), trim(p_customer_phone), trim(p_pickup_address),
    trim(p_delivery_address), coalesce(nullif(trim(p_order_type), ''), 'delivery'),
    v_notes, 'new', v_delivery_price,
    p_pickup_region_id, p_delivery_region_id, p_vehicle_type
  )
  returning id into v_order_id;

  return query select v_order_id, v_delivery_price;
end;
$$;

revoke all on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) from public;
grant execute on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) to anon, authenticated;

create or replace function public.driver_update_order_status(
  p_order_id uuid,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_driver_id uuid;
  v_driver_active boolean;
  v_application_status text;
  v_order_driver_id uuid;
  v_current_status text;
  v_delivery_price numeric;
  v_commission_rate numeric;
  v_office_commission numeric;
  v_driver_amount numeric;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً.';
  end if;

  if p_new_status is null or p_new_status not in ('picked_up', 'delivered') then
    raise exception 'الحالة المطلوبة غير مسموح بها.';
  end if;

  select d.id, d.is_active, d.application_status
    into v_driver_id, v_driver_active, v_application_status
  from public.drivers as d
  where d.user_id = auth.uid()
  for update;

  if not found
     or v_driver_active is distinct from true
     or v_application_status is distinct from 'approved' then
    raise exception 'حساب السائق غير معتمد أو غير نشط.';
  end if;

  select o.driver_id, o.status, o.delivery_price
    into v_order_driver_id, v_current_status, v_delivery_price
  from public.orders as o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'الطلب غير موجود.';
  end if;

  if v_order_driver_id is distinct from v_driver_id then
    raise exception 'هذا الطلب غير مسند إلى حسابك.';
  end if;

  if p_new_status = 'delivered' then
    if v_delivery_price is null or v_delivery_price <= 0 then
      raise exception 'أجرة التوصيل غير محددة؛ تواصل مع الإدارة.';
    end if;

    select bs.office_commission_percent
      into v_commission_rate
    from public.business_settings as bs
    limit 1;

    v_commission_rate := coalesce(v_commission_rate, 15);
    if v_commission_rate < 0 or v_commission_rate > 100 then
      raise exception 'إعدادات توزيع أجرة التوصيل غير صحيحة.';
    end if;

    v_office_commission := round(v_delivery_price * v_commission_rate / 100, 2);
    v_driver_amount := round(v_delivery_price - v_office_commission, 2);
  end if;

  if v_current_status = p_new_status then
    if p_new_status = 'delivered' then
      insert into public.driver_earnings (
        driver_id, order_id, delivery_amount, office_commission,
        driver_amount, payment_status, notes
      )
      values (
        v_driver_id, p_order_id, v_delivery_price, v_office_commission,
        v_driver_amount, 'pending', 'تم تسجيل مستحقات الطلب عند تأكيد التسليم'
      )
      on conflict (order_id) where order_id is not null do update
      set delivery_amount = excluded.delivery_amount,
          office_commission = excluded.office_commission,
          driver_amount = excluded.driver_amount,
          driver_id = excluded.driver_id
      where driver_earnings.payment_status <> 'paid';
    end if;

    return jsonb_build_object('success', true, 'status', v_current_status, 'unchanged', true);
  end if;

  if not (
    (v_current_status = 'assigned' and p_new_status = 'picked_up')
    or
    (v_current_status = 'picked_up' and p_new_status = 'delivered')
  ) then
    raise exception 'تسلسل الحالة غير صحيح. يجب استلام الطلب أولاً ثم تسليمه.';
  end if;

  update public.orders
  set status = p_new_status
  where id = p_order_id;

  if p_new_status = 'delivered' then
    insert into public.driver_earnings (
      driver_id, order_id, delivery_amount, office_commission,
      driver_amount, payment_status, notes
    )
    values (
      v_driver_id, p_order_id, v_delivery_price, v_office_commission,
      v_driver_amount, 'pending', 'تم تسجيل مستحقات الطلب عند تأكيد التسليم'
    )
    on conflict (order_id) where order_id is not null do update
    set delivery_amount = excluded.delivery_amount,
        office_commission = excluded.office_commission,
        driver_amount = excluded.driver_amount,
        driver_id = excluded.driver_id
    where driver_earnings.payment_status <> 'paid';
  end if;

  return jsonb_build_object('success', true, 'status', p_new_status, 'unchanged', false);
end;
$function$;

revoke all on function public.driver_update_order_status(uuid, text) from public;
revoke all on function public.driver_update_order_status(uuid, text) from anon;
grant execute on function public.driver_update_order_status(uuid, text) to authenticated;

-- The homepage no longer requests or exposes a public directory of driver names.
revoke all on function public.get_available_drivers() from public, anon, authenticated;

-- Authenticated RLS policies still need to call this helper.
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

notify pgrst, 'reload schema';

-- Read-only post-migration readiness snapshot.
select
  (select count(*) from public.regions where is_active is true) as active_regions,
  (select count(*) from public.delivery_rates where is_active is true and currency = 'ILS') as active_ils_delivery_rates,
  (select count(*) from public.drivers where is_active is true and application_status = 'approved') as active_approved_drivers,
  (select count(*) from public.orders where status in ('new','confirmed','assigned','picked_up')) as active_orders;
