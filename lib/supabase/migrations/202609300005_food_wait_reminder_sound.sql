alter table public.profiles
  add column if not exists food_wait_reminder_sound boolean not null default true;
