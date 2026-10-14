-- Kinetic: eigen namen voor video's ("Instap", "Detail grip") in plaats van
-- "Video 1, 2, …". Per gebruiker één map van videolink → naam, zodat het
-- voor technieken, combinaties, oefeningen en circuits tegelijk werkt en de
-- bestaande video_urls-kolommen (die Uchivo leest) gewoon tekst blijven.
alter table public.profiles
  add column if not exists video_labels jsonb not null default '{}'::jsonb;
