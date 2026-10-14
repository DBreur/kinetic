create table if not exists public.techniques (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null default 'Overig',
  updates jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.techniques enable row level security;

drop policy if exists "Users can read own techniques" on public.techniques;
create policy "Users can read own techniques"
  on public.techniques for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own techniques" on public.techniques;
create policy "Users can insert own techniques"
  on public.techniques for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own techniques" on public.techniques;
create policy "Users can update own techniques"
  on public.techniques for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own techniques" on public.techniques;
create policy "Users can delete own techniques"
  on public.techniques for delete
  using (auth.uid() = user_id);

drop trigger if exists techniques_set_updated_at on public.techniques;
create trigger techniques_set_updated_at
  before update on public.techniques
  for each row
  execute function public.set_updated_at();

create index if not exists techniques_user_name_idx
  on public.techniques (user_id, name);
