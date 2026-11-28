-- AHMEDKO: allow orders with no configured delivery rate.
-- Run once in Supabase SQL Editor AFTER the baseline files in PRODUCTION_SETUP.md.
-- Missing rate => order is saved with NULL delivery_price for office pricing.
-- Duplicate active rates or invalid configured prices still reject the request.
begin;
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
as $function$
declare
  v_price_count integer;
  v_delivery_price numeric;
  v_order_id uuid;
  v_regions_count integer;
begin
  if length(trim(coalesce(p_customer_name, ''))) not between 2 and 100 then
    raise exception 'يرجى إدخال اسم صحيح.';
  end if;

  if length(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g')) not between 7 and 15 then
    raise exception 'يرجى إدخال رقم هاتف صحيح.';
  end if;

  if length(trim(coalesce(p_pickup_address, ''))) not between 3 and 300
     or length(trim(coalesce(p_delivery_address, ''))) not between 3 and 300 then
    raise exception 'عنوان الاستلام والتسليم مطلوبان.';
  end if;

  if p_vehicle_type is null
     or p_vehicle_type not in ('car','tuk_tuk','bus','electric_bicycle','bicycle','motorcycle') then
    raise exception 'وسيلة النقل المختارة غير صحيحة.';
  end if;

  if coalesce(p_order_type, 'delivery') not in ('delivery','restaurant_order') then
    raise exception 'نوع الطلب غير معتمد.';
  end if;

  if p_pickup_region_id is null or p_delivery_region_id is null then
    raise exception 'يرجى اختيار منطقة الاستلام ومنطقة التسليم.';
  end if;

  select count(*) into v_regions_count
  from public.regions r
  where r.id in (p_pickup_region_id, p_delivery_region_id)
    and r.is_active is true;

  if p_pickup_region_id = p_delivery_region_id then
    if v_regions_count <> 1 then
      raise exception 'المنطقة المختارة غير مفعّلة أو غير موجودة.';
    end if;
  elsif v_regions_count <> 2 then
    raise exception 'إحدى المناطق المختارة غير مفعّلة أو غير موجودة.';
  end if;

  select count(*), min(dr.price)
    into v_price_count, v_delivery_price
  from public.delivery_rates dr
  where dr.pickup_region_id = p_pickup_region_id
    and dr.delivery_region_id = p_delivery_region_id
    and dr.vehicle_type = p_vehicle_type
    and dr.is_active is true
    and dr.currency = 'ILS';

  if v_price_count > 1 then
    raise exception 'يوجد أكثر من سعر نشط لهذا المسار. يجب على الإدارة مراجعة جدول الأسعار قبل استقبال الطلب.';
  elsif v_price_count = 1 then
    if v_delivery_price is null or v_delivery_price <= 0 then
      raise exception 'سعر التوصيل المعتمد غير صحيح. يرجى التواصل مع الإدارة.';
    end if;
  else
    -- No configured rate: accept the request with a NULL price.
    -- The office must set the price through its protected admin workflow.
    v_delivery_price := null;
  end if;

  insert into public.orders (
    customer_name, customer_phone, pickup_address, delivery_address,
    order_type, notes, status, delivery_price,
    pickup_region_id, delivery_region_id, vehicle_type
  )
  values (
    trim(p_customer_name), trim(p_customer_phone), trim(p_pickup_address),
    trim(p_delivery_address), coalesce(nullif(trim(p_order_type), ''), 'delivery'),
    nullif(trim(coalesce(p_notes, '')), ''), 'new', v_delivery_price,
    p_pickup_region_id, p_delivery_region_id, p_vehicle_type
  )
  returning id into v_order_id;

  return query select v_order_id, v_delivery_price;
end;
$function$;

revoke all on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) from public;
grant execute on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) to anon, authenticated;
notify pgrst, 'reload schema';
commit;