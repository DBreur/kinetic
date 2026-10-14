-- Kinetic: indeling van het dashboard (Vandaag): volgorde en aan/uit van de
-- blokken en de snelle acties, en of de lijsten in de instellingen op slot
-- staan. Leeg = de standaardindeling. Puur additief.
alter table public.profiles
  add column if not exists dashboard jsonb not null default '{}'::jsonb;
