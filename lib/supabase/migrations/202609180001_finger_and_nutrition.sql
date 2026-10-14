-- Vingerprik-log: handmatig ingevoerde glucosewaardes, los van Nightscout.
create table if not exists public.glucose_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mmol numeric(4, 1) not null check (mmol > 0 and mmol < 40),
  at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.glucose_entries enable row level security;

drop policy if exists "Users can read own glucose entries" on public.glucose_entries;
create policy "Users can read own glucose entries"
  on public.glucose_entries for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own glucose entries" on public.glucose_entries;
create policy "Users can insert own glucose entries"
  on public.glucose_entries for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own glucose entries" on public.glucose_entries;
create policy "Users can delete own glucose entries"
  on public.glucose_entries for delete
  using (auth.uid() = user_id);

create index if not exists glucose_entries_user_at_idx
  on public.glucose_entries (user_id, at desc);

-- Voedingspresets die je in de instellingen samenstelt.
alter table public.profiles
  add column if not exists carb_presets jsonb not null default '[]'::jsonb;

-- Voeding gelogd tijdens een training (label, tijdstip, glucose op dat moment).
alter table public.training_sessions
  add column if not exists nutrition jsonb not null default '[]'::jsonb;
