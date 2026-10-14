alter table public.profiles
  add column if not exists low_alarm_enabled boolean not null default true;
