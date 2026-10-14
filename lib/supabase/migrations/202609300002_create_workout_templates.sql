-- Trainingsschema's voor krachttraining: een naam + een vaste lijst
-- oefeningen met vaste sets (kg/reps), die je bij het starten van een
-- sessie als startpunt kunt kiezen en daarna gewoon kunt aanpassen.
create table if not exists public.workout_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.workout_templates enable row level security;

drop policy if exists "Users can read own workout templates" on public.workout_templates;
create policy "Users can read own workout templates"
  on public.workout_templates for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own workout templates" on public.workout_templates;
create policy "Users can insert own workout templates"
  on public.workout_templates for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own workout templates" on public.workout_templates;
create policy "Users can update own workout templates"
  on public.workout_templates for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own workout templates" on public.workout_templates;
create policy "Users can delete own workout templates"
  on public.workout_templates for delete
  using (auth.uid() = user_id);

drop trigger if exists workout_templates_set_updated_at on public.workout_templates;
create trigger workout_templates_set_updated_at
  before update on public.workout_templates
  for each row
  execute function public.set_updated_at();

create index if not exists workout_templates_user_name_idx
  on public.workout_templates (user_id, name);
