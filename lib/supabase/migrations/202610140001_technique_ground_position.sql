alter table public.techniques
  add column if not exists ground_position text not null default '';
