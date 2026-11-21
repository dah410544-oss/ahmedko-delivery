-- AHMEDKO DELIVERY: verified-phone customer order tracking
-- Run once in Supabase SQL Editor as project owner.
-- Customers do not create a profile/password. They verify phone ownership with Supabase SMS OTP.
-- This function returns only the caller's own limited order details.

create or replace function public.get_my_customer_orders()
returns table (
  order_id uuid,
  status text,
  created_at timestamptz,
  pickup_address text,
  delivery_address text,
  delivery_price numeric,
  order_type text,
  vehicle_type text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_verified_phone text;
  v_phone_digits text;
begin
  if auth.uid() is null then
    raise exception 'يجب التحقق من رقم الهاتف أولاً.';
  end if;

  select u.phone
    into v_verified_phone
  from auth.users as u
  where u.id = auth.uid()
    and u.phone_confirmed_at is not null;

  if v_verified_phone is null then
    raise exception 'رقم الهاتف غير موثق. اطلب رمز تحقق جديداً.';
  end if;

  v_phone_digits := right(regexp_replace(v_verified_phone, '[^0-9]', '', 'g'), 9);

  if length(v_phone_digits) <> 9 then
    raise exception 'صيغة رقم الهاتف غير مدعومة. تواصل مع أحمدكو.';
  end if;

  return query
  select
    o.id,
    o.status::text,
    o.created_at,
    o.pickup_address,
    o.delivery_address,
    o.delivery_price,
    o.order_type,
    o.vehicle_type
  from public.orders as o
  where right(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g'), 9) = v_phone_digits
  order by o.created_at desc
  limit 50;
end;
$function$;

revoke all on function public.get_my_customer_orders() from public;
revoke all on function public.get_my_customer_orders() from anon;
grant execute on function public.get_my_customer_orders() to authenticated;

notify pgrst, 'reload schema';
