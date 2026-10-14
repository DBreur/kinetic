alter table public.profiles
  add column if not exists prep_items jsonb not null default '[]'::jsonb;
