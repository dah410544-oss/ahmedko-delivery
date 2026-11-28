-- AHMEDKO wallet: block direct client writes.
-- Run only after wallet_foundation.sql has created these three tables.
-- The application must use the guarded wallet RPC functions for all changes.

revoke insert, update, delete, truncate, references, trigger
  on public.wallet_accounts,
     public.wallet_topup_requests,
     public.wallet_transactions
  from anon, authenticated;

-- Keep read access governed by the existing SELECT grants and RLS policies.
