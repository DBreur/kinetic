-- Circuits voor krachttraining: een naam + een lijst oefeningnamen die je
-- in rondes doorloopt (zelfde werktijd/rusttijd voor het hele circuit) —
-- ook warming-ups zijn gewoon een circuit. Herbruikbaar: te selecteren
-- tijdens een live training of op te nemen in een trainingsschema.
create table if not exists public.circuits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exercise_names jsonb not null default '[]'::jsonb,
  rounds integer not null default 3,
  work_seconds integer not null default 40,
  rest_seconds integer not null default 20,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.circuits enable row level security;

drop policy if exists "Users can read own circuits" on public.circuits;
create policy "Users can read own circuits"
  on public.circuits for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own circuits" on public.circuits;
create policy "Users can insert own circuits"
  on public.circuits for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own circuits" on public.circuits;
create policy "Users can update own circuits"
  on public.circuits for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own circuits" on public.circuits;
create policy "Users can delete own circuits"
  on public.circuits for delete
  using (auth.uid() = user_id);

drop trigger if exists circuits_set_updated_at on public.circuits;
create trigger circuits_set_updated_at
  before update on public.circuits
  for each row
  execute function public.set_updated_at();

create index if not exists circuits_user_name_idx
  on public.circuits (user_id, name);

-- Circuits die daadwerkelijk tijdens een training zijn uitgevoerd (snapshot).
alter table public.training_sessions
  add column if not exists circuits jsonb not null default '[]'::jsonb;

-- Circuits die in een trainingsschema zijn opgenomen (embedded kopieën).
alter table public.workout_templates
  add column if not exists circuits jsonb not null default '[]'::jsonb;
