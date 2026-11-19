-- AHMEDKO DELIVERY: public announcements
-- Run this once in Supabase SQL Editor.
create table if not exists public.public_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 90),
  message text not null check (char_length(message) between 1 and 700),
  is_active boolean not null default true,
  starts_at timestamptz null default null,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcement_valid_dates check (starts_at is null or ends_at is null or ends_at > starts_at)
);

alter table public.public_announcements enable row level security;

drop policy if exists "Public can read active current announcements" on public.public_announcements;
create policy "Public can read active current announcements"
on public.public_announcements for select
to anon, authenticated
using (
  is_active = true
  and (starts_at is null or starts_at <= now())
  and (ends_at is null or ends_at >= now())
);

drop policy if exists "Admins can read all announcements" on public.public_announcements;
create policy "Admins can read all announcements"
on public.public_announcements for select
to authenticated
using (
  exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid()
      and user_roles.role = 'admin'
  )
);

drop policy if exists "Admins can insert announcements" on public.public_announcements;
create policy "Admins can insert announcements"
on public.public_announcements for insert
to authenticated
with check (
  exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid()
      and user_roles.role = 'admin'
  )
);

drop policy if exists "Admins can update announcements" on public.public_announcements;
create policy "Admins can update announcements"
on public.public_announcements for update
to authenticated
using (
  exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid()
      and user_roles.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid()
      and user_roles.role = 'admin'
  )
);

drop policy if exists "Admins can delete announcements" on public.public_announcements;
create policy "Admins can delete announcements"
on public.public_announcements for delete
to authenticated
using (
  exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid()
      and user_roles.role = 'admin'
  )
);

grant select on public.public_announcements to anon, authenticated;
grant insert, update, delete on public.public_announcements to authenticated;
