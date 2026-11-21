-- AHMEDKO DELIVERY: private customer order tracking
-- Run once in Supabase SQL Editor as project owner.
-- A customer can read only orders whose stored phone matches the verified
-- phone number on their authenticated Supabase user.

create or replace function public.get_my_customer_orders()
returns table (
  order_id uuid,
  pickup_address text,
  delivery_address text,
  order_type text,
  status text,
  delivery_price numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  with verified_phone as (
    select
      case
        when digits like '970%' or digits like '972%' then '0' || substring(digits from 4)
        when digits like '00%' then
          case
            when substring(digits from 3) like '970%' or substring(digits from 3) like '972%'
              then '0' || substring(substring(digits from 3) from 4)
            else substring(digits from 3)
          end
        when digits ~ '^5[0-9]{8}$' then '0' || digits
        else digits
      end as phone_key
    from (
      select regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') as digits
      from auth.users u
      where u.id = auth.uid()
        and u.phone_confirmed_at is not null
    ) normalized
    where digits <> ''
  )
  select
    o.id,
    o.pickup_address,
    o.delivery_address,
    o.order_type,
    o.status,
    o.delivery_price,
    o.created_at
  from public.orders o
  where exists (
    select 1
    from verified_phone v
    where
      case
        when regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') like '970%'
          or regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') like '972%'
          then '0' || substring(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') from 4)
        when regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') like '00%'
          then
            case
              when substring(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') from 3) like '970%'
                or substring(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') from 3) like '972%'
                then '0' || substring(substring(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') from 3) from 4)
              else substring(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') from 3)
            end
        when regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') ~ '^5[0-9]{8}$'
          then '0' || regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g')
        else regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g')
      end = v.phone_key
  )
  order by o.created_at desc
  limit 100;
$$;

revoke all on function public.get_my_customer_orders() from public;
revoke all on function public.get_my_customer_orders() from anon;
grant execute on function public.get_my_customer_orders() to authenticated;

comment on function public.get_my_customer_orders() is
  'Returns at most 100 orders matching the authenticated user''s verified Supabase phone number. No phone verification means no rows.';
