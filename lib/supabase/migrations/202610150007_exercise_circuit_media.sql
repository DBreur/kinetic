-- Kinetic: video's bij eigen oefeningen; beschrijving, video's en stappen
-- (elke stap een tijd óf een aantal herhalingen) bij circuits. Puur
-- additief — exercise_names en work_seconds blijven bestaan en worden
-- gewoon meegeschreven, dus Uchivo blijft circuits kunnen lezen.

alter table public.exercises
  add column if not exists video_urls jsonb not null default '[]'::jsonb;

alter table public.circuits
  add column if not exists description text not null default '',
  add column if not exists video_urls jsonb not null default '[]'::jsonb,
  -- [{ "name": "Schaduwboksen", "seconds": 60 }, { "name": "Push-up", "reps": 10 }]
  add column if not exists steps jsonb not null default '[]'::jsonb;
