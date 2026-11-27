-- AHMEDKO payment gateway readiness foundation
-- Prepared only: do NOT run until the existing wallet SQL has been reviewed and a backup is taken.
-- No provider is enabled by this migration. No credentials or private keys belong in this file.

create table if not exists public.payment_provider_configs (
  provider_code text primary key check (provider_code in ('jawwal_pay','palpay','bank_palestine')),
  display_name text not null,
  is_enabled boolean not null default false,
  merchant_reference text not null default '',
  webhook_secret_vault_key text not null default '',
  checkout_mode text not null default 'hosted' check (checkout_mode in ('hosted','api')),
  updated_at timestamptz not null default now()
);

insert into public.payment_provider_configs(provider_code,display_name,is_enabled)
values
 ('jawwal_pay','جوال بي',false),
 ('palpay','بال بي',false),
 ('bank_palestine','بنك فلسطين',false)
on conflict (provider_code) do nothing;

create table if not exists public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_code text not null references public.payment_provider_configs(provider_code),
  purpose text not null check (purpose in ('wallet_topup','order_payment')),
  order_id uuid,
  amount numeric(12,2) not null check (amount > 0 and amount <= 10000),
  currency text not null default 'ILS' check (currency = 'ILS'),
  status text not null default 'initiated'
    check (status in ('initiated','pending','paid','failed','expired','cancelled')),
  idempotency_key text not null unique,
  provider_transaction_id text,
  checkout_url text,
  expires_at timestamptz,
  verified_at timestamptz,
  failure_code text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_attempt_provider_tx_unique unique(provider_code,provider_transaction_id)
);

create index if not exists payment_attempts_user_created_idx
  on public.payment_attempts(user_id,created_at desc);
create index if not exists payment_attempts_pending_idx
  on public.payment_attempts(status,created_at)
  where status in ('initiated','pending');

create table if not exists public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null references public.payment_provider_configs(provider_code),
  provider_event_id text not null,
  event_type text not null default '',
  provider_transaction_id text not null default '',
  signature_valid boolean not null default false,
  processing_status text not null default 'received'
    check (processing_status in ('received','processed','ignored','failed')),
  payload_sha256 text not null default '',
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(provider_code,provider_event_id)
);

alter table public.wallet_transactions
  add column if not exists payment_attempt_id uuid
  references public.payment_attempts(id);

create unique index if not exists wallet_transactions_payment_attempt_unique
  on public.wallet_transactions(payment_attempt_id)
  where payment_attempt_id is not null;

alter table public.payment_provider_configs enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.payment_webhook_events enable row level security;

drop policy if exists payment_attempts_read_own on public.payment_attempts;
create policy payment_attempts_read_own on public.payment_attempts
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists payment_attempts_admin_read on public.payment_attempts;
create policy payment_attempts_admin_read on public.payment_attempts
  for select to authenticated using (public.is_admin());

-- Provider configuration and webhook events are server-only.
revoke all on public.payment_provider_configs from public, anon, authenticated;
revoke all on public.payment_webhook_events from public, anon, authenticated;
revoke all on public.payment_attempts from public, anon, authenticated;
grant select on public.payment_attempts to authenticated;

-- The server may call this only after validating the provider's signature and transaction.
-- It re-checks amount/currency/status and credits a wallet top-up exactly once.
create or replace function public.wallet_confirm_gateway_topup(
  p_attempt_id uuid,
  p_provider_transaction_id text,
  p_amount numeric,
  p_currency text,
  p_signature_verified boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.payment_attempts%rowtype;
  v_balance numeric(12,2);
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'server role required';
  end if;
  if p_signature_verified is distinct from true then
    raise exception 'provider signature was not verified';
  end if;
  if p_provider_transaction_id is null or length(trim(p_provider_transaction_id)) < 3 then
    raise exception 'invalid provider transaction reference';
  end if;

  select * into v_attempt
  from public.payment_attempts
  where id = p_attempt_id
  for update;

  if not found then raise exception 'payment attempt not found'; end if;
  if v_attempt.purpose <> 'wallet_topup' then raise exception 'payment attempt is not a wallet top-up'; end if;
  if v_attempt.status = 'paid' then return 'already_paid'; end if;
  if v_attempt.status not in ('initiated','pending') then raise exception 'payment attempt is not payable'; end if;
  if v_attempt.amount <> round(p_amount,2) or v_attempt.currency <> upper(coalesce(p_currency,'')) then
    raise exception 'payment amount or currency mismatch';
  end if;

  update public.payment_attempts
  set status='paid',
      provider_transaction_id=trim(p_provider_transaction_id),
      verified_at=now(),
      updated_at=now()
  where id=p_attempt_id;

  insert into public.wallet_accounts(user_id)
  values(v_attempt.user_id)
  on conflict(user_id) do nothing;

  update public.wallet_accounts
  set balance=balance+v_attempt.amount,updated_at=now()
  where user_id=v_attempt.user_id
  returning balance into v_balance;

  insert into public.wallet_transactions(
    user_id,payment_attempt_id,transaction_type,amount,balance_after,currency,description
  ) values (
    v_attempt.user_id,v_attempt.id,'topup',v_attempt.amount,v_balance,'ILS',
    'شحن آلي موثّق عبر ' || v_attempt.provider_code
  );

  return 'paid';
end;
$$;

revoke all on function public.wallet_confirm_gateway_topup(uuid,text,numeric,text,boolean) from public, anon, authenticated;
grant execute on function public.wallet_confirm_gateway_topup(uuid,text,numeric,text,boolean) to service_role;
