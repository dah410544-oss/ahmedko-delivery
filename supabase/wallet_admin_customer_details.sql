-- Admin-only wallet top-up queue with customer contact details.
-- Apply after wallet_foundation.sql in Supabase SQL Editor.
create or replace function public.wallet_admin_list_topups()
returns table (
  request_id uuid,
  user_id uuid,
  customer_name text,
  customer_phone text,
  amount numeric,
  method_code text,
  transfer_reference text,
  customer_note text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'غير مصرح: هذه البيانات للإدارة فقط';
  end if;

  return query
  select
    r.id,
    r.user_id,
    coalesce(
      nullif(u.raw_user_meta_data ->> 'full_name', ''),
      nullif(u.raw_user_meta_data ->> 'name', ''),
      nullif(u.raw_user_meta_data ->> 'display_name', ''),
      'عميل أحمدكو'
    ),
    coalesce(u.phone, ''),
    r.amount,
    r.method_code,
    r.transfer_reference,
    r.customer_note,
    r.status,
    r.created_at
  from public.wallet_topup_requests r
  left join auth.users u on u.id = r.user_id
  order by r.created_at desc
  limit 100;
end;
$$;

revoke all on function public.wallet_admin_list_topups() from public, anon;
grant execute on function public.wallet_admin_list_topups() to authenticated;
