-- Kinetic: links bij een wedstrijd (reglement en toernooiwebsite). Puur
-- additief.
alter table public.competitions
  add column if not exists rules_url text not null default '',
  add column if not exists website_url text not null default '';
