-- AHMEDKO Wallet foundation
-- Apply once in Supabase SQL Editor after taking a database backup.
-- All amounts are ILS. The browser never writes balances or ledger rows directly.

create table if not exists public.wallet_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(12,2) not null default 0 check (balance >= 0),
  currency text not null default 'ILS' check (currency = 'ILS'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_payment_methods (
  code text primary key check (code in ('palpay','jawwal_pay','bank_palestine')),
  display_name text not null,
  instructions text not null default '',
  account_label text not null default '',
  is_active boolean not null default true,
  sort_order integer not null default 10,
  updated_at timestamptz not null default now()
);

-- Owner-provided receiving details supplied for this wallet setup.
-- Bank transfer is manual; customers submit a reference for admin verification.
insert into public.wallet_payment_methods(
  code, display_name, instructions, account_label, is_active, sort_order
)
values
 (
  'palpay',
  'PalPay',
  'حوّل المبلغ إلى محفظة PalPay على الرقم 0598407547، باسم أحمد سمير الدحبور. أرسل رقم/مرجع الحوالة، وسيُضاف الرصيد بعد مراجعة المكتب.',
  'صاحب المحفظة: أحمد سمير الدحبور | رقم الاستلام: 0598407547',
  true,
  1
 ),
 (
  'jawwal_pay',
  'Jawwal Pay',
  'حوّل المبلغ إلى محفظة Jawwal Pay على الرقم 0598407547، باسم أحمد سمير الدحبور. أرسل رقم/مرجع الحوالة، وسيُضاف الرصيد بعد مراجعة المكتب.',
  'صاحب المحفظة: أحمد سمير الدحبور | رقم الاستلام: 0598407547',
  true,
  2
 ),
 (
  'bank_palestine',
  'بنك فلسطين',
  'بنك فلسطين: رقم الحساب 570183، الهاتف المرتبط 0598407547، ورقم الآيبان (IBAN): PS06PALS045105701830993000000، باسم أحمد سمير الدحبور. أرسل مرجع الحوالة ليتم التحقق من وصولها فعلياً قبل إضافة الرصيد.',
  'صاحب الحساب: أحمد سمير الدحبور | رقم الحساب: 570183 | الهاتف المرتبط: 0598407547 | رقم الآيبان (IBAN): PS06PALS045105701830993000000',
  true,
  3
 )
on conflict (code) do update set
  display_name=excluded.display_name,
  instructions=excluded.instructions,
  account_label=excluded.account_label,
  is_active=excluded.is_active,
  sort_order=excluded.sort_order;

create table if not exists public.wallet_topup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0 and amount <= 10000),
  currency text not null default 'ILS' check (currency = 'ILS'),
  method_code text not null references public.wallet_payment_methods(code),
  transfer_reference text not null check (length(trim(transfer_reference)) between 3 and 120),
  customer_note text not null default '' check (length(customer_note) <= 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text not null default '',
  created_at timestamptz not null default now(),
  constraint wallet_topup_review_consistency check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status <> 'pending' and reviewed_by is not null and reviewed_at is not null)
  )
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  topup_request_id uuid unique references public.wallet_topup_requests(id),
  transaction_type text not null check (transaction_type in ('topup','payment','refund','adjustment')),
  amount numeric(12,2) not null check (amount <> 0),
  balance_after numeric(12,2) not null check (balance_after >= 0),
  currency text not null default 'ILS' check (currency = 'ILS'),
  description text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists wallet_topups_user_created_idx
  on public.wallet_topup_requests(user_id, created_at desc);
create index if not exists wallet_transactions_user_created_idx
  on public.wallet_transactions(user_id, created_at desc);

alter table public.wallet_accounts enable row level security;
alter table public.wallet_payment_methods enable row level security;
alter table public.wallet_topup_requests enable row level security;
alter table public.wallet_transactions enable row level security;

drop policy if exists wallet_accounts_read_own on public.wallet_accounts;
create policy wallet_accounts_read_own on public.wallet_accounts
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists wallet_accounts_admin_read on public.wallet_accounts;
create policy wallet_accounts_admin_read on public.wallet_accounts
  for select to authenticated using (public.is_admin());

drop policy if exists wallet_methods_read_active on public.wallet_payment_methods;
create policy wallet_methods_read_active on public.wallet_payment_methods
  for select to authenticated using (is_active or public.is_admin());
drop policy if exists wallet_methods_admin_manage on public.wallet_payment_methods;
create policy wallet_methods_admin_manage on public.wallet_payment_methods
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists wallet_topups_read_own on public.wallet_topup_requests;
create policy wallet_topups_read_own on public.wallet_topup_requests
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists wallet_topups_admin_read on public.wallet_topup_requests;
create policy wallet_topups_admin_read on public.wallet_topup_requests
  for select to authenticated using (public.is_admin());

drop policy if exists wallet_transactions_read_own on public.wallet_transactions;
create policy wallet_transactions_read_own on public.wallet_transactions
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists wallet_transactions_admin_read on public.wallet_transactions;
create policy wallet_transactions_admin_read on public.wallet_transactions
  for select to authenticated using (public.is_admin());

-- No INSERT/UPDATE/DELETE policies are granted on balances or ledger tables.
-- New users get an empty wallet automatically.
create or replace function public.ahmedko_create_wallet_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.wallet_accounts(user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists ahmedko_create_wallet_after_signup on auth.users;
create trigger ahmedko_create_wallet_after_signup
  after insert on auth.users
  for each row execute function public.ahmedko_create_wallet_for_new_user();

-- Backfill wallets for existing auth users.
insert into public.wallet_accounts(user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.wallet_create_topup_request(
  p_amount numeric,
  p_method_code text,
  p_transfer_reference text,
  p_customer_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_id uuid;
begin
  if v_user_id is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000 then
    raise exception 'قيمة الشحن يجب أن تكون أكبر من صفر ولا تتجاوز 10000 شيكل';
  end if;
  if p_transfer_reference is null or length(trim(p_transfer_reference)) not between 3 and 120 then
    raise exception 'أدخل رقم أو مرجع الحوالة الصحيح';
  end if;
  if length(coalesce(p_customer_note,'')) > 500 then raise exception 'الملاحظات طويلة جداً'; end if;
  if not exists (
    select 1 from public.wallet_payment_methods
    where code = p_method_code and is_active = true
  ) then raise exception 'وسيلة الشحن غير متاحة حالياً'; end if;

  insert into public.wallet_accounts(user_id) values (v_user_id)
  on conflict (user_id) do nothing;

  insert into public.wallet_topup_requests(
    user_id, amount, method_code, transfer_reference, customer_note
  ) values (
    v_user_id, round(p_amount,2), p_method_code, trim(p_transfer_reference), coalesce(trim(p_customer_note),'')
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.wallet_review_topup(
  p_request_id uuid,
  p_approve boolean,
  p_review_note text default ''
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.wallet_topup_requests%rowtype;
  v_balance numeric(12,2);
  v_admin uuid := auth.uid();
begin
  if v_admin is null or not public.is_admin() then raise exception 'غير مصرح: هذه العملية للإدارة فقط'; end if;
  if length(coalesce(p_review_note,'')) > 500 then raise exception 'ملاحظة المراجعة طويلة جداً'; end if;

  select * into v_request
  from public.wallet_topup_requests
  where id = p_request_id
  for update;

  if not found then raise exception 'طلب الشحن غير موجود'; end if;
  if v_request.status <> 'pending' then raise exception 'تمت مراجعة طلب الشحن مسبقاً'; end if;

  update public.wallet_topup_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = v_admin,
      reviewed_at = now(),
      review_note = coalesce(trim(p_review_note),'')
  where id = p_request_id;

  if not p_approve then return 'rejected'; end if;

  insert into public.wallet_accounts(user_id) values (v_request.user_id)
  on conflict (user_id) do nothing;

  update public.wallet_accounts
  set balance = balance + v_request.amount, updated_at = now()
  where user_id = v_request.user_id
  returning balance into v_balance;

  insert into public.wallet_transactions(
    user_id, topup_request_id, transaction_type, amount, balance_after, description
  ) values (
    v_request.user_id, v_request.id, 'topup', v_request.amount, v_balance,
    'شحن محفظة عبر ' || v_request.method_code || ' - ' || v_request.transfer_reference
  );

  return 'approved';
end;
$$;

revoke all on function public.wallet_create_topup_request(numeric,text,text,text) from public, anon;
grant execute on function public.wallet_create_topup_request(numeric,text,text,text) to authenticated;
revoke all on function public.wallet_review_topup(uuid,boolean,text) from public, anon;
grant execute on function public.wallet_review_topup(uuid,boolean,text) to authenticated;

grant select on public.wallet_accounts, public.wallet_payment_methods,
  public.wallet_topup_requests, public.wallet_transactions to authenticated;
