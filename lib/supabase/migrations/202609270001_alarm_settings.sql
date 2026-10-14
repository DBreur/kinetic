-- Eén centrale alarm-instelling (AppController.alarmDecision()) vervangt de
-- losse "ondergrens tijdens training aan/uit"-vlag met een echte
-- dagelijkse ondergrens (buiten training) en een master aan/uit/stil-modus.
alter table public.profiles
  add column if not exists alarm_mode text not null default 'sound',
  add column if not exists daily_low_below numeric(3, 1) not null default 3.9
    check (daily_low_below >= 3.0 and daily_low_below <= 6.0),
  add column if not exists daily_low_enabled boolean not null default true,
  add column if not exists break_silent_mode boolean not null default true,
  drop column if exists low_alarm_enabled;
