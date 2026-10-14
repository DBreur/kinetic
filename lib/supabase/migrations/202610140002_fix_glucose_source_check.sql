-- De vorige migratie (202610130004) zette bestaande 'cgm'-waarden om naar
-- 'nightscout' en voegde de Dexcom-kolommen toe, maar liet de oorspronkelijke
-- check-constraint op glucose_source (alleen 'cgm'/'finger') onaangeroerd —
-- daardoor weigerde elke opslag met 'nightscout' of 'dexcomShare' nog steeds,
-- met "Instellingen konden niet worden opgeslagen" als gevolg. Dit haalt die
-- oude constraint op naam op (in plaats van de autogegenereerde naam te
-- gokken) en vervangt hem door een die de drie huidige bronnen toestaat.

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    join pg_attribute att on att.attrelid = rel.oid and att.attnum = any(con.conkey)
    where nsp.nspname = 'public'
      and rel.relname = 'profiles'
      and att.attname = 'glucose_source'
      and con.contype = 'c'
  loop
    execute format('alter table public.profiles drop constraint %I', r.conname);
  end loop;
end $$;

update public.profiles set glucose_source = 'nightscout' where glucose_source = 'cgm';

alter table public.profiles
  add constraint profiles_glucose_source_check
  check (glucose_source in ('nightscout', 'dexcomShare', 'finger'));
