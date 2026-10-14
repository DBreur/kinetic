create table if not exists public.combinations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type text not null default 'mixed',
  techniques jsonb not null default '[]'::jsonb,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.combinations enable row level security;

drop policy if exists "Users can read own combinations" on public.combinations;
create policy "Users can read own combinations"
  on public.combinations for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own combinations" on public.combinations;
create policy "Users can insert own combinations"
  on public.combinations for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own combinations" on public.combinations;
create policy "Users can update own combinations"
  on public.combinations for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own combinations" on public.combinations;
create policy "Users can delete own combinations"
  on public.combinations for delete
  using (auth.uid() = user_id);

drop trigger if exists combinations_set_updated_at on public.combinations;
create trigger combinations_set_updated_at
  before update on public.combinations
  for each row
  execute function public.set_updated_at();

create index if not exists combinations_user_name_idx
  on public.combinations (user_id, name);
