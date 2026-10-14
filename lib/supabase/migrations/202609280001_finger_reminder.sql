-- Periodieke vingerprik-herinnering (geen alarm) — los in te stellen van het
-- hypo-alarm: aan/uit, onder welke glucosebron, en met welk interval.
alter table public.profiles
  add column if not exists finger_reminder_enabled boolean not null default false,
  add column if not exists finger_reminder_scope text not null default 'fingerOnly',
  add column if not exists finger_reminder_interval_minutes integer not null default 120
    check (finger_reminder_interval_minutes >= 15 and finger_reminder_interval_minutes <= 480);
