-- Kinetic: waar de Spotify-knop staat, een eigen alarmstand tijdens
-- trainingen (los van het dagelijkse alarm) en een voorbereidingstijd vóór
-- elke oefening in een circuit. Puur additief.
alter table public.profiles
  add column if not exists spotify_button text not null default 'both'
    check (spotify_button in ('both', 'strength', 'mat', 'off')),
  -- null = zelfde als alarm_mode
  add column if not exists training_alarm_mode text
    check (training_alarm_mode is null
      or training_alarm_mode in ('sound', 'silent', 'off')),
  add column if not exists circuit_prep_seconds integer not null default 10
    check (circuit_prep_seconds between 0 and 120);
