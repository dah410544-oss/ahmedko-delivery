-- AHMEDKO DELIVERY — wallet checkout for authenticated customer delivery orders.
-- Safe additive migration: preserves existing orders, balances, and wallet history.
begin;

alter table public.orders
  add column if not exists customer_user_id uuid references auth.users(id) on delete set null;

alter table public.wallet_transactions
  add column if not exists order_id uuid references public.orders(id) on delete restrict;

create unique index if not exists wallet_transactions_one_delivery_debit_per_order
  on public.wallet_transactions(order_id)
  where transaction_type = 'delivery_debit' and order_id is not null;

-- Keep anonymous order intake working, while linking signed-in customers to their own orders.
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

  if p_pickup_region_id is not null then
    select count(*) into v_regions_count from public.regions r
    where r.id = p_pickup_region_id and r.is_active is true;
    if v_regions_count <> 1 then raise exception 'منطقة الاستلام المختارة غير مفعّلة أو غير موجودة.'; end if;
  end if;
  if p_delivery_region_id is not null then
    select count(*) into v_regions_count from public.regions r
    where r.id = p_delivery_region_id and r.is_active is true;
    if v_regions_count <> 1 then raise exception 'منطقة التسليم المختارة غير مفعّلة أو غير موجودة.'; end if;
  end if;

  v_price_count := 0;
  v_delivery_price := null;
  if p_pickup_region_id is not null and p_delivery_region_id is not null then
    select count(*), min(dr.price) into v_price_count, v_delivery_price
    from public.delivery_rates dr
    where dr.pickup_region_id = p_pickup_region_id
      and dr.delivery_region_id = p_delivery_region_id
      and dr.vehicle_type = p_vehicle_type
      and dr.is_active is true and dr.currency = 'ILS';
    if v_price_count > 1 then
      raise exception 'يوجد أكثر من سعر نشط لهذا المسار. يجب على الإدارة مراجعة جدول الأسعار قبل استقبال الطلب.';
    elsif v_price_count = 1 and (v_delivery_price is null or v_delivery_price <= 0) then
      raise exception 'سعر التوصيل المعتمد غير صحيح. يرجى التواصل مع الإدارة.';
    elsif v_price_count = 0 then
      v_delivery_price := null;
    end if;
  end if;

  insert into public.orders (
    customer_name, customer_phone, pickup_address, delivery_address,
    order_type, notes, status, delivery_price,
    pickup_region_id, delivery_region_id, vehicle_type, customer_user_id
  )
  values (
    trim(p_customer_name), trim(p_customer_phone), trim(p_pickup_address),
    trim(p_delivery_address), coalesce(nullif(trim(p_order_type), ''), 'delivery'),
    nullif(trim(coalesce(p_notes, '')), ''), 'new', v_delivery_price,
    p_pickup_region_id, p_delivery_region_id, p_vehicle_type, auth.uid()
  )
  returning id into v_order_id;

  return query select v_order_id, v_delivery_price;
end;
$function$;

revoke all on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) from public;
grant execute on function public.create_customer_order(text,text,text,text,uuid,uuid,text,text,text) to anon, authenticated;

-- After OTP verification, safely attach previous anonymous orders matching this verified phone.
create or replace function public.wallet_claim_orders_by_phone()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_phone text;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'سجّل الدخول برقم الهاتف أولاً.'; end if;
  select right(regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g'), 9)
    into v_phone from auth.users where id = auth.uid();
  if v_phone is null or length(v_phone) <> 9 then
    raise exception 'تعذر التحقق من رقم الهاتف المرتبط بحسابك.';
  end if;
  update public.orders
  set customer_user_id = auth.uid()
  where customer_user_id is null
    and right(regexp_replace(coalesce(customer_phone,''), '[^0-9]', '', 'g'), 9) = v_phone;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
revoke all on function public.wallet_claim_orders_by_phone() from public, anon;
grant execute on function public.wallet_claim_orders_by_phone() to authenticated;

-- A customer may pay only their own confirmed order, once, using a locked wallet balance.
create or replace function public.wallet_pay_delivery_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_order public.orders%rowtype;
  v_balance numeric(12,2);
  v_new_balance numeric(12,2);
begin
  if auth.uid() is null then
    raise exception 'سجّل الدخول إلى حسابك أولاً لاستخدام المحفظة.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id and customer_user_id = auth.uid()
  for update;

  if not found then
    raise exception 'الطلب غير موجود أو غير مرتبط بحسابك.';
  end if;
  if v_order.status <> 'confirmed' then
    raise exception 'يمكن الدفع من المحفظة بعد تأكيد الطلب من مكتب أحمدكو فقط.';
  end if;
  if v_order.delivery_price is null or v_order.delivery_price <= 0 then
    raise exception 'أجرة التوصيل لم تعتمد بعد.';
  end if;

  if exists (
    select 1 from public.wallet_transactions
    where order_id = p_order_id and transaction_type = 'delivery_debit'
  ) then
    raise exception 'تم دفع هذا الطلب من المحفظة مسبقاً.';
  end if;

  insert into public.customer_wallets(user_id)
  values (auth.uid()) on conflict (user_id) do nothing;

  select balance into v_balance
  from public.customer_wallets
  where user_id = auth.uid()
  for update;

  if v_balance < v_order.delivery_price then
    raise exception 'رصيد محفظتك غير كافٍ. اشحن رصيدك ثم حاول مجدداً.';
  end if;

  update public.customer_wallets
  set balance = balance - v_order.delivery_price, updated_at = now()
  where user_id = auth.uid()
  returning balance into v_new_balance;

  insert into public.wallet_transactions(
    user_id, order_id, transaction_type, amount, balance_after, description, created_by
  ) values (
    auth.uid(), p_order_id, 'delivery_debit', -v_order.delivery_price,
    v_new_balance, 'دفع أجرة طلب توصيل من محفظة أحمدكو', auth.uid()
  );

  return jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'paid_amount', v_order.delivery_price,
    'balance', v_new_balance
  );
end;
$function$;

revoke all on function public.wallet_pay_delivery_order(uuid) from public, anon;
grant execute on function public.wallet_pay_delivery_order(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
