alter table public.food_log_entries
  add column if not exists insulin_units numeric(4, 1),
  add column if not exists insulin_timing text,
  add column if not exists insulin_note text not null default '';
