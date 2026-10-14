alter table public.food_log_entries
  add column if not exists preset_counts jsonb not null default '{}'::jsonb,
  add column if not exists carbs numeric(5, 1),
  drop column if exists checklist;
