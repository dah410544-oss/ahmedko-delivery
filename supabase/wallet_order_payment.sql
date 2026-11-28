-- AHMEDKO DELIVERY — secure, one-time wallet payment for a confirmed delivery
-- Run in Supabase SQL Editor as project owner. Does not alter existing balances.
begin;

alter table public.wallet_transactions
  add column if not exists order_id uuid references public.orders(id) on delete set null;

create unique index if not exists wallet_transactions_one_delivery_payment_per_order
  on public.wallet_transactions(order_id)
  where order_id is not null and transaction_type = 'delivery_debit';

create or replace function public.wallet_pay_delivery_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_phone text;
  v_phone_digits text;
  v_order public.orders%rowtype;
  v_balance numeric(12,2);
  v_new_balance numeric(12,2);
  v_existing_id uuid;
begin
  if auth.uid() is null then
    raise exception 'يرجى تسجيل الدخول برقم الهاتف الموثّق أولاً.';
  end if;

  select u.phone into v_phone
  from auth.users u
  where u.id = auth.uid()
    and u.phone_confirmed_at is not null;

  if v_phone is null then
    raise exception 'رقم الهاتف غير موثّق.';
  end if;

  v_phone_digits := right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 9);
  if length(v_phone_digits) <> 9 then
    raise exception 'صيغة رقم الهاتف غير مدعومة.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'الطلب غير موجود.';
  end if;

  if right(regexp_replace(coalesce(v_order.customer_phone, ''), '[^0-9]', '', 'g'), 9) <> v_phone_digits then
    raise exception 'هذا الطلب لا يخص حسابك.';
  end if;

  if v_order.status::text <> 'confirmed' then
    raise exception 'يمكن دفع الطلب بعد اعتماد سعره وتأكيده من المكتب فقط.';
  end if;

  if v_order.delivery_price is null or v_order.delivery_price <= 0 then
    raise exception 'لم يعتمد المكتب أجرة التوصيل بعد.';
  end if;

  select id into v_existing_id
  from public.wallet_transactions
  where order_id = p_order_id
    and transaction_type = 'delivery_debit';

  if v_existing_id is not null then
    select balance into v_balance
    from public.customer_wallets
    where user_id = auth.uid();

    return jsonb_build_object(
      'success', true,
      'already_paid', true,
      'transaction_id', v_existing_id,
      'balance', coalesce(v_balance, 0)
    );
  end if;

  insert into public.customer_wallets(user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  select balance into v_balance
  from public.customer_wallets
  where user_id = auth.uid()
  for update;

  if v_balance < v_order.delivery_price then
    raise exception 'رصيد المحفظة غير كافٍ. اشحن رصيدك ثم أعد المحاولة.';
  end if;

  update public.customer_wallets
  set balance = balance - v_order.delivery_price,
      updated_at = now()
  where user_id = auth.uid()
  returning balance into v_new_balance;

  insert into public.wallet_transactions(
    user_id, order_id, transaction_type, amount,
    balance_after, description, created_by
  ) values (
    auth.uid(), p_order_id, 'delivery_debit', -v_order.delivery_price,
    v_new_balance, 'دفع أجرة توصيل الطلب رقم ' || left(p_order_id::text, 8), auth.uid()
  )
  returning id into v_existing_id;

  return jsonb_build_object(
    'success', true,
    'already_paid', false,
    'transaction_id', v_existing_id,
    'amount', v_order.delivery_price,
    'balance', v_new_balance
  );
end;
$function$;

revoke all on function public.wallet_pay_delivery_order(uuid) from public, anon;
grant execute on function public.wallet_pay_delivery_order(uuid) to authenticated;

commit;
notify pgrst, 'reload schema';
