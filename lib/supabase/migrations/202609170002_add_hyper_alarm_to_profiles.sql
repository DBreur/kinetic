alter table public.profiles
  add column if not exists hyper_limit numeric(3, 1) not null default 10.0
    check (hyper_limit >= 7.0 and hyper_limit <= 20.0),
  add column if not exists hyper_alarm_enabled boolean not null default true;
