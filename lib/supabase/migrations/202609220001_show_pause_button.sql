alter table public.profiles
  add column if not exists show_pause_button boolean not null default true;
