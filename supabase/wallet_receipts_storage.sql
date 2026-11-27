-- AHMEDKO Wallet receipt storage hardening
-- Apply only AFTER wallet_foundation.sql, after reviewing the schema and is_admin().
-- This migration creates a PRIVATE bucket. It does not expose receipt files publicly.

alter table public.wallet_topup_requests
  add column if not exists receipt_object_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'wallet-receipts',
  'wallet-receipts',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

drop policy if exists "wallet_receipts_insert_own" on storage.objects;
create policy "wallet_receipts_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'wallet-receipts'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and coalesce((storage.foldername(name))[2], '') <> ''
  and coalesce((storage.foldername(name))[3], '') = ''
  and exists (
    select 1
    from public.wallet_topup_requests r
    where r.id::text = (storage.foldername(name))[2]
      and r.user_id = (select auth.uid())
      and r.status = 'pending'
  )
);

drop policy if exists "wallet_receipts_read_own" on storage.objects;
create policy "wallet_receipts_read_own"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'wallet-receipts'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);

-- Attach an uploaded object to the caller's own pending top-up request.
-- The client cannot update receipt paths directly or attach another user's file.
create or replace function public.wallet_attach_topup_receipt(
  p_request_id uuid,
  p_object_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.wallet_topup_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  if p_object_path is null
     or length(p_object_path) > 500
     or split_part(p_object_path, '/', 1) <> v_user_id::text
     or split_part(p_object_path, '/', 2) <> p_request_id::text
     or split_part(p_object_path, '/', 3) = ''
     or split_part(p_object_path, '/', 4) <> ''
     or position('..' in p_object_path) > 0 then
    raise exception 'مسار ملف الإيصال غير صالح';
  end if;

  select * into v_request
  from public.wallet_topup_requests
  where id = p_request_id
  for update;

  if not found or v_request.user_id <> v_user_id then
    raise exception 'طلب الشحن غير موجود';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'لا يمكن تعديل إيصال طلب تمت مراجعته';
  end if;

  update public.wallet_topup_requests
  set receipt_object_path = p_object_path
  where id = p_request_id;
end;
$$;

revoke all on function public.wallet_attach_topup_receipt(uuid, text) from public, anon;
grant execute on function public.wallet_attach_topup_receipt(uuid, text) to authenticated;

-- No public read access, no anonymous uploads, and no client-side balance updates.
