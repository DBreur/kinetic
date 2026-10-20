-- Kinetic: sluimertijd voor het glucose-alarm, standaard rust bij
-- krachttraining, en wegen met datum (geschiedenis + herinnering).
-- Puur additief — bestaande kolommen en rijen worden niet aangeraakt.

-- ── Profiel: nieuwe instellingen ────────────────────────────────────────
alter table public.profiles
  add column if not exists alarm_snooze_minutes integer not null default 15
    check (alarm_snooze_minutes between 1 and 120),
  add column if not exists default_rest_seconds integer not null default 90
    check (default_rest_seconds between 0 and 600),
  add column if not exists weigh_in_interval_days integer not null default 7
    check (weigh_in_interval_days between 0 and 90),
  add column if not exists weigh_in_reminder_time text not null default '08:00';

-- ── Wegingen ─────────────────────────────────────────────────────────────
create table if not exists public.weigh_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null default now(),
  weight_kg numeric(5,1) not null check (weight_kg between 20 and 300),
  created_at timestamptz not null default now()
);

alter table public.weigh_ins enable row level security;

drop policy if exists "Users can read own weigh-ins" on public.weigh_ins;
create policy "Users can read own weigh-ins"
  on public.weigh_ins for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own weigh-ins" on public.weigh_ins;
create policy "Users can insert own weigh-ins"
  on public.weigh_ins for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own weigh-ins" on public.weigh_ins;
create policy "Users can update own weigh-ins"
  on public.weigh_ins for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own weigh-ins" on public.weigh_ins;
create policy "Users can delete own weigh-ins"
  on public.weigh_ins for delete
  using (auth.uid() = user_id);

create index if not exists weigh_ins_user_measured_idx
  on public.weigh_ins (user_id, measured_at desc);
