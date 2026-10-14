-- Kinetic: spiergroepen bij oefeningen (geen, één of meer), om op te
-- filteren en om het spierfiguurtje in te kleuren. Puur additief.
alter table public.exercises
  add column if not exists muscle_groups jsonb not null default '[]'::jsonb;
