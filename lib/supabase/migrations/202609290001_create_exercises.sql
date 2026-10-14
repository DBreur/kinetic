create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.exercises enable row level security;

drop policy if exists "Users can read own exercises" on public.exercises;
create policy "Users can read own exercises"
  on public.exercises for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own exercises" on public.exercises;
create policy "Users can insert own exercises"
  on public.exercises for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own exercises" on public.exercises;
create policy "Users can update own exercises"
  on public.exercises for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own exercises" on public.exercises;
create policy "Users can delete own exercises"
  on public.exercises for delete
  using (auth.uid() = user_id);

drop trigger if exists exercises_set_updated_at on public.exercises;
create trigger exercises_set_updated_at
  before update on public.exercises
  for each row
  execute function public.set_updated_at();

create index if not exists exercises_user_name_idx
  on public.exercises (user_id, name);
