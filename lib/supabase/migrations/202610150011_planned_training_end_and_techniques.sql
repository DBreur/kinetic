-- Kinetic: eindtijd (duur) bij geplande trainingen, technieken om te oefenen
-- per training met eigen herinneringen, en instellingen daarvoor. Puur
-- additief — Uchivo kent deze kolommen niet en hoeft ze niet te kennen.

alter table public.planned_trainings
  -- Duur in minuten; eind = starts_at + duration_minutes. Null = onbekend.
  add column if not exists duration_minutes integer
    check (duration_minutes is null or duration_minutes between 0 and 1440),
  -- Ids van technieken die je bij deze training wilt oefenen.
  add column if not exists technique_ids jsonb not null default '[]'::jsonb,
  -- Herinneringen voor die technieken: minuten vóór de start (0 = bij de
  -- start; nooit na de start), bv. [60, 0].
  add column if not exists technique_reminders jsonb not null default '[]'::jsonb;

alter table public.techniques
  -- "Oefenen bij de eerstvolgende training" (ook als die niet gepland is).
  add column if not exists practice_next boolean not null default false;

alter table public.profiles
  add column if not exists technique_reminders_enabled boolean not null default true,
  -- Standaard voorgestelde herinneringen (minuten vóór de start).
  add column if not exists technique_reminder_defaults jsonb not null default '[60, 0]'::jsonb,
  add column if not exists technique_reminder_sound boolean not null default false;
