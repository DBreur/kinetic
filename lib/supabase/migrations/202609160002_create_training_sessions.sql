create table if not exists public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('sambo', 'kracht')),
  title text not null,
  started_at timestamptz not null,
  duration_minutes integer not null default 0,
  note text not null default '',
  glucose_series jsonb not null default '[]'::jsonb,
  blocks jsonb not null default '[]'::jsonb,
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.training_sessions enable row level security;

drop policy if exists "Users can read own sessions" on public.training_sessions;
create policy "Users can read own sessions"
  on public.training_sessions for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own sessions" on public.training_sessions;
create policy "Users can insert own sessions"
  on public.training_sessions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own sessions" on public.training_sessions;
create policy "Users can update own sessions"
  on public.training_sessions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own sessions" on public.training_sessions;
create policy "Users can delete own sessions"
  on public.training_sessions for delete
  using (auth.uid() = user_id);

drop trigger if exists training_sessions_set_updated_at on public.training_sessions;
create trigger training_sessions_set_updated_at
  before update on public.training_sessions
  for each row
  execute function public.set_updated_at();

create index if not exists training_sessions_user_started_idx
  on public.training_sessions (user_id, started_at desc);
