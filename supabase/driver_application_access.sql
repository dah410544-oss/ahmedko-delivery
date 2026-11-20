-- AHMEDKO DELIVERY: secure self-service driver application access
-- Run once in Supabase SQL Editor as project owner.
-- This does not create or alter tables and does not grant drivers admin privileges.
-- Drivers may read only their own profile and submit only a pending, inactive application.
-- Existing admin policies remain in place and continue to govern office management.

alter table public.drivers enable row level security;

drop policy if exists "Drivers read own profile" on public.drivers;
create policy "Drivers read own profile"
  on public.drivers
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Drivers submit own pending application" on public.drivers;
create policy "Drivers submit own pending application"
  on public.drivers
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and application_status = 'pending'
    and is_active is false
  );

notify pgrst, 'reload schema';
