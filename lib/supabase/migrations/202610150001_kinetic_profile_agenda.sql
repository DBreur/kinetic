-- Kinetic: favoriete combinaties, profiel (gebruikersnaam + foto), en de
-- agenda (geplande trainingen + wedstrijden). Puur additief — bestaande
-- kolommen en rijen worden niet aangeraakt, dus Uchivo blijft werken.

-- ── Combinaties: favoriet, net als technieken ────────────────────────────
alter table public.combinations
  add column if not exists favorite boolean not null default false;

-- ── Profiel: weergavenaam en profielfoto ────────────────────────────────
alter table public.profiles
  add column if not exists username text not null default ''
    check (char_length(username) <= 40),
  add column if not exists avatar_url text not null default '';

-- Profielfoto's: één bestand per gebruiker in een eigen map
-- (avatars/<user-id>/...). Lezen is openbaar (de URL bevat een
-- willekeurige versie-suffix), schrijven alleen in je eigen map.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "Avatars are publicly readable" on storage.objects;
create policy "Avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "Users can upload own avatar" on storage.objects;
create policy "Users can upload own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can update own avatar" on storage.objects;
create policy "Users can update own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can delete own avatar" on storage.objects;
create policy "Users can delete own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Geplande trainingen ──────────────────────────────────────────────────
create table if not exists public.planned_trainings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  kind text not null default 'sport_sambo'
    check (kind in ('sport_sambo', 'combat_sambo', 'kracht', 'overig')),
  title text not null default '',
  location text not null default '',
  note text not null default '',
  -- Minuten vóór de start voor een melding; null = geen melding.
  remind_minutes_before integer
    check (remind_minutes_before is null
      or (remind_minutes_before >= 0 and remind_minutes_before <= 2880)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.planned_trainings enable row level security;

drop policy if exists "Users can read own planned trainings" on public.planned_trainings;
create policy "Users can read own planned trainings"
  on public.planned_trainings for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own planned trainings" on public.planned_trainings;
create policy "Users can insert own planned trainings"
  on public.planned_trainings for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own planned trainings" on public.planned_trainings;
create policy "Users can update own planned trainings"
  on public.planned_trainings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own planned trainings" on public.planned_trainings;
create policy "Users can delete own planned trainings"
  on public.planned_trainings for delete
  using (auth.uid() = user_id);

drop trigger if exists planned_trainings_set_updated_at on public.planned_trainings;
create trigger planned_trainings_set_updated_at
  before update on public.planned_trainings
  for each row
  execute function public.set_updated_at();

create index if not exists planned_trainings_user_starts_idx
  on public.planned_trainings (user_id, starts_at);

-- ── Wedstrijden ──────────────────────────────────────────────────────────
create table if not exists public.competitions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  starts_at timestamptz not null,
  discipline text not null default 'sport'
    check (discipline in ('sport', 'combat', 'both')),
  location text not null default '',
  weight_class text not null default '',
  goal text not null default '',
  -- Dagelijkse aftel-melding (met motivatie) om dit tijdstip, "HH:mm".
  daily_reminder boolean not null default true,
  reminder_time text not null default '08:00',
  -- Uitslag, achteraf in te vullen.
  result_place integer check (result_place is null or result_place >= 1),
  result_wins integer check (result_wins is null or result_wins >= 0),
  result_losses integer check (result_losses is null or result_losses >= 0),
  result_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.competitions enable row level security;

drop policy if exists "Users can read own competitions" on public.competitions;
create policy "Users can read own competitions"
  on public.competitions for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own competitions" on public.competitions;
create policy "Users can insert own competitions"
  on public.competitions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own competitions" on public.competitions;
create policy "Users can update own competitions"
  on public.competitions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own competitions" on public.competitions;
create policy "Users can delete own competitions"
  on public.competitions for delete
  using (auth.uid() = user_id);

drop trigger if exists competitions_set_updated_at on public.competitions;
create trigger competitions_set_updated_at
  before update on public.competitions
  for each row
  execute function public.set_updated_at();

create index if not exists competitions_user_starts_idx
  on public.competitions (user_id, starts_at);
