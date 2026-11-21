-- AHMEDKO DELIVERY: set the existing office settings row to 16% / ILS.
-- Run once in Supabase SQL Editor as project owner, after taking a backup.
-- This updates the existing row only; it never inserts or duplicates settings.
-- The script stops if the table shape or expected single-row setup differs.

do $$
declare
  v_rows bigint;
  v_updated bigint;
begin
  if to_regclass('public.business_settings') is null then
    raise exception 'public.business_settings does not exist; no changes made.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'business_settings'
      and column_name = 'office_commission_percent'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'business_settings'
      and column_name = 'currency'
  ) then
    raise exception 'Expected office_commission_percent and currency columns are missing; no changes made.';
  end if;

  select count(*) into v_rows from public.business_settings;
  if v_rows <> 1 then
    raise exception 'Expected exactly one business_settings row, found %. Review manually; no changes made.', v_rows;
  end if;

  update public.business_settings
  set office_commission_percent = 16,
      currency = 'ILS';

  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'Expected to update exactly one settings row, updated %. ', v_updated;
  end if;
end
$$;

-- Verify the saved business values.
select office_commission_percent, currency
from public.business_settings;
