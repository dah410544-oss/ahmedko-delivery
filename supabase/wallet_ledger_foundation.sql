-- AHMEDKO DELIVERY: secure wallet ledger foundation
-- Apply manually in Supabase SQL Editor only after reviewing on a backup/project copy.
-- This migration records top-up requests and credits wallets ONLY after admin verification.
-- It does not connect to PalPay, Jawwal Pay, or a bank API and does not auto-confirm transfers.

create table if not exists public.wallet_topup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0 and amount <= 50000),
  payment_method text not null check (payment_method in ('palpay','jawwal_pay','bank_transfer')),
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint wallet_topup_review_state_check check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or
    (status in ('approved','rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);

create unique index if not exists wallet_topup_payment_reference_uidx
  on public.wallet_topup_requests(payment_method, payment_reference)
  where payment_reference is not null and length(trim(payment_reference)) > 0;

create index if not exists wallet_topup_user_created_idx
  on public.wallet_topup_requests(user_id, created_at desc);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  topup_request_id uuid unique references public.wallet_topup_requests(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('topup_credit','order_debit','refund','admin_adjustment')),
  amount numeric(12,2) not null check (amount <> 0),
  description text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists wallet_transactions_user_created_idx
  on public.wallet_transactions(user_id, created_at desc);

alter table public.wallet_topup_requests enable row level security;
alter table public.wallet_transactions enable row level security;

drop policy if exists wallet_topups_read_own_or_admin on public.wallet_topup_requests;
create policy wallet_topups_read_own_or_admin
  on public.wallet_topup_requests for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists wallet_transactions_read_own_or_admin on public.wallet_transactions;
create policy wallet_transactions_read_own_or_admin
  on public.wallet_transactions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- No direct INSERT/UPDATE/DELETE policies are granted to browser clients.
-- Mutations below are narrowly scoped SECURITY DEFINER RPCs.

create or replace function public.request_wallet_topup(
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
  v_user_id uuid := auth.uid();
  v_request_id uuid;
  v_reference text := nullif(trim(coalesce(p_payment_reference, '')), '');
begin
  if v_user_id is null then
    raise exception 'يجب تسجيل الدخول أولاً.';
  end if;

  if p_amount is null or p_amount < 1 or p_amount > 50000 then
    raise exception 'مبلغ الشحن يجب أن يكون بين 1 و50000 شيكل.';
  end if;

  if p_payment_method not in ('palpay','jawwal_pay','bank_transfer') then
    raise exception 'وسيلة الشحن غير مدعومة.';
  end if;

  insert into public.wallet_topup_requests(user_id, amount, payment_method, payment_reference)
  values (v_user_id, round(p_amount, 2), p_payment_method, v_reference)
  returning id into v_request_id;

  return v_request_id;
end;
$function$;

create or replace function public.review_wallet_topup(
  p_request_id uuid,
  p_approve boolean,
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_request public.wallet_topup_requests%rowtype;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'غير مصرح لك بمراجعة طلبات الشحن.';
  end if;

  if p_request_id is null or p_approve is null then
    raise exception 'بيانات مراجعة طلب الشحن غير مكتملة.';
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

  if p_approve then
    insert into public.wallet_transactions(
      user_id, topup_request_id, transaction_type, amount, description, created_by
    )
    values (
      v_request.user_id,
      v_request.id,
      'topup_credit',
      v_request.amount,
      'شحن رصيد بعد التحقق اليدوي من وصول الحوالة',
      v_admin_id
    );
  end if;

  update public.wallet_topup_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      reviewed_by = v_admin_id,
      reviewed_at = now()
  where id = v_request.id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'status', case when p_approve then 'approved' else 'rejected' end
  );
end;
$function$;

create or replace function public.get_my_wallet_balance()
returns table(balance numeric, currency text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً.';
  end if;

  return query
  select
    coalesce(sum(t.amount), 0)::numeric(12,2),
    coalesce((select bs.currency from public.business_settings bs limit 1), 'ILS')
  from public.wallet_transactions t
  where t.user_id = auth.uid();
end;
$function$;

revoke all on function public.request_wallet_topup(numeric,text,text) from public;
revoke all on function public.review_wallet_topup(uuid,boolean,text) from public;
revoke all on function public.get_my_wallet_balance() from public;

grant execute on function public.request_wallet_topup(numeric,text,text) to authenticated;
grant execute on function public.review_wallet_topup(uuid,boolean,text) to authenticated;
grant execute on function public.get_my_wallet_balance() to authenticated;

notify pgrst, 'reload schema';

-- Read-only verification after applying:
-- select count(*) from public.wallet_topup_requests;
-- select count(*) from public.wallet_transactions;
-- select proname from pg_proc where proname in
-- ('request_wallet_topup','review_wallet_topup','get_my_wallet_balance');
