-- AHMEDKO DELIVERY — customer wallet foundation
-- Review and run once in Supabase SQL Editor as project owner.
-- This creates an auditable wallet ledger. It does NOT verify external payments:
-- the office must approve a top-up only after confirming funds were received.

begin;

create table if not exists public.customer_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(12,2) not null default 0 check (balance >= 0),
  currency text not null default 'ILS' check (currency = 'ILS'),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_topup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 1 and amount <= 50000),
  currency text not null default 'ILS' check (currency = 'ILS'),
  payment_method text not null check (payment_method in ('palpay','jawwal_pay','bank_transfer','cash')),
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  office_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  topup_request_id uuid unique references public.wallet_topup_requests(id),
  transaction_type text not null check (transaction_type in ('topup','adjustment','delivery_debit','refund')),
  amount numeric(12,2) not null check (amount <> 0),
  balance_after numeric(12,2) not null check (balance_after >= 0),
  description text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists wallet_topup_requests_user_created_idx
  on public.wallet_topup_requests(user_id, created_at desc);
create index if not exists wallet_topup_requests_status_created_idx
  on public.wallet_topup_requests(status, created_at desc);
create index if not exists wallet_transactions_user_created_idx
  on public.wallet_transactions(user_id, created_at desc);

alter table public.customer_wallets enable row level security;
alter table public.wallet_topup_requests enable row level security;
alter table public.wallet_transactions enable row level security;

drop policy if exists "Customers read own wallet" on public.customer_wallets;
create policy "Customers read own wallet"
  on public.customer_wallets for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Customers read own topup requests" on public.wallet_topup_requests;
create policy "Customers read own topup requests"
  on public.wallet_topup_requests for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Admins read wallet transactions" on public.wallet_transactions;
create policy "Customers read own wallet transactions"
  on public.wallet_transactions for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

revoke all on public.customer_wallets from anon, authenticated;
revoke all on public.wallet_topup_requests from anon, authenticated;
revoke all on public.wallet_transactions from anon, authenticated;
grant select on public.customer_wallets, public.wallet_topup_requests, public.wallet_transactions to authenticated;

create or replace function public.wallet_request_topup(
  p_amount numeric,
  p_payment_method text,
  p_payment_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول برقم الهاتف أولاً.';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 50000 then
    raise exception 'مبلغ الشحن يجب أن يكون بين 1 و50000 شيكل.';
  end if;
  if p_payment_method not in ('palpay','jawwal_pay','bank_transfer','cash') then
    raise exception 'وسيلة الدفع غير معتمدة.';
  end if;
  if length(coalesce(p_payment_reference,'')) > 120 then
    raise exception 'رقم المرجع طويل جداً.';
  end if;

  insert into public.customer_wallets(user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  insert into public.wallet_topup_requests(user_id, amount, payment_method, payment_reference)
  values (auth.uid(), round(p_amount,2), p_payment_method, nullif(trim(p_payment_reference),''))
  returning id into v_request_id;

  return v_request_id;
end;
$function$;

create or replace function public.wallet_admin_review_topup(
  p_request_id uuid,
  p_approve boolean,
  p_office_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_request public.wallet_topup_requests%rowtype;
  v_balance numeric(12,2);
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'غير مصرح: هذه العملية للمكتب فقط.';
  end if;

  select * into v_request
  from public.wallet_topup_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'طلب الشحن غير موجود.';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'تمت مراجعة طلب الشحن مسبقاً.';
  end if;

  if not p_approve then
    update public.wallet_topup_requests
    set status='rejected',
        office_note=left(coalesce(p_office_note,''),500),
        reviewed_by=auth.uid(),
        reviewed_at=now()
    where id=p_request_id;
    return jsonb_build_object('success',true,'status','rejected');
  end if;

  insert into public.customer_wallets(user_id)
  values (v_request.user_id)
  on conflict (user_id) do nothing;

  update public.customer_wallets
  set balance = balance + v_request.amount,
      updated_at = now()
  where user_id = v_request.user_id
  returning balance into v_balance;

  insert into public.wallet_transactions(
    user_id, topup_request_id, transaction_type, amount,
    balance_after, description, created_by
  ) values (
    v_request.user_id, v_request.id, 'topup', v_request.amount,
    v_balance, 'شحن محفظة بعد تحقق المكتب من استلام الدفعة', auth.uid()
  );

  update public.wallet_topup_requests
  set status='approved',
      office_note=left(coalesce(p_office_note,''),500),
      reviewed_by=auth.uid(),
      reviewed_at=now()
  where id=p_request_id;

  return jsonb_build_object('success',true,'status','approved','balance',v_balance);
end;
$function$;

revoke all on function public.wallet_request_topup(numeric,text,text) from public, anon;
grant execute on function public.wallet_request_topup(numeric,text,text) to authenticated;
revoke all on function public.wallet_admin_review_topup(uuid,boolean,text) from public, anon;
grant execute on function public.wallet_admin_review_topup(uuid,boolean,text) to authenticated;

commit;

notify pgrst, 'reload schema';

-- Acceptance checks after running:
-- 1) A signed-in customer can call wallet_request_topup and sees a pending request.
-- 2) The customer cannot insert/update wallet balances or ledger rows directly.
-- 3) A non-admin cannot call wallet_admin_review_topup successfully.
-- 4) The admin can approve once; a second approval is rejected and does not add funds twice.
-- 5) A rejected request never changes the balance.
