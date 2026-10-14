alter table public.techniques
  add column if not exists learning_status text not null default 'none',
  add column if not exists planned_for timestamptz,
  add column if not exists learning_goal text not null default '',
  add column if not exists learning_started_at timestamptz;
