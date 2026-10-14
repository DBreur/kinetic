create table if not exists public.food_log_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now(),
  description text not null default '',
  checklist jsonb not null default '[]'::jsonb,
  mmol numeric(4, 1),
  created_at timestamptz not null default now()
);

alter table public.food_log_entries enable row level security;

create policy "Users can read own food log entries"
  on public.food_log_entries for select
  using (auth.uid() = user_id);

create policy "Users can insert own food log entries"
  on public.food_log_entries for insert
  with check (auth.uid() = user_id);

create policy "Users can update own food log entries"
  on public.food_log_entries for update
  using (auth.uid() = user_id);

create policy "Users can delete own food log entries"
  on public.food_log_entries for delete
  using (auth.uid() = user_id);

create index if not exists food_log_entries_user_at_idx
  on public.food_log_entries (user_id, at desc);

alter table public.profiles
  add column if not exists food_checklist jsonb not null default
    '["Bloedsuiker gemeten", "Koolhydraten geteld", "Insuline genomen"]'::jsonb;
