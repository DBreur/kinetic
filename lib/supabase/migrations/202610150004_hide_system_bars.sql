-- Kinetic: systeembalken van de telefoon automatisch verbergen (immersive
-- sticky) in de hele app. Standaard uit; tijdens een live training gebeurt
-- het altijd. Puur additief.
alter table public.profiles
  add column if not exists hide_system_bars boolean not null default false;
