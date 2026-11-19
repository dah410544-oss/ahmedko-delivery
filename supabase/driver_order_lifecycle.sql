-- AHMEDKO DELIVERY: secure driver order lifecycle
-- Run this file once in Supabase SQL Editor as project owner.
-- Drivers can change ONLY their own assigned order status through this RPC.

do $$
begin
  if exists (
    select 1
    from public.driver_earnings
    where order_id is not null
    group by order_id
    having count(*) > 1
  ) then
    raise exception 'Duplicate driver_earnings rows exist for an order. Review duplicates before applying the unique index.';
  end if;
end;
$$;

create unique index if not exists driver_earnings_order_id_unique
  on public.driver_earnings (order_id)
  where order_id is not null;

create or replace function public.driver_update_order_status(
  p_order_id uuid,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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

  if p_new_status not in ('picked_up', 'delivered') then
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
      raise exception 'نسبة عمولة المكتب في الإعدادات غير صحيحة.';
    end if;

    v_office_commission := round(v_delivery_price * v_commission_rate / 100, 2);
    v_driver_amount := round(v_delivery_price - v_office_commission, 2);
  end if;

  -- Safe retry: do not create duplicate earnings for an already delivered order.
  if v_current_status = p_new_status then
    if p_new_status = 'delivered' then
      insert into public.driver_earnings (
        driver_id, order_id, delivery_amount, office_commission,
        driver_amount, payment_status, notes
      )
      values (
        v_driver_id, p_order_id, v_delivery_price, v_office_commission,
        v_driver_amount, 'pending',
        'عمولة المكتب ' || v_commission_rate || '% ومستحق السائق ' || (100 - v_commission_rate) || '%'
      )
      on conflict (order_id) where order_id is not null do update
      set delivery_amount = excluded.delivery_amount,
          office_commission = excluded.office_commission,
          driver_amount = excluded.driver_amount,
          driver_id = excluded.driver_id
      where public.driver_earnings.payment_status <> 'paid';
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
      v_driver_amount, 'pending',
      'عمولة المكتب ' || v_commission_rate || '% ومستحق السائق ' || (100 - v_commission_rate) || '%'
    )
    on conflict (order_id) where order_id is not null do update
    set delivery_amount = excluded.delivery_amount,
        office_commission = excluded.office_commission,
        driver_amount = excluded.driver_amount,
        driver_id = excluded.driver_id
    where public.driver_earnings.payment_status <> 'paid';
  end if;

  return jsonb_build_object('success', true, 'status', p_new_status, 'unchanged', false);
end;
$$;

revoke all on function public.driver_update_order_status(uuid, text) from public;
revoke all on function public.driver_update_order_status(uuid, text) from anon;
grant execute on function public.driver_update_order_status(uuid, text) to authenticated;
