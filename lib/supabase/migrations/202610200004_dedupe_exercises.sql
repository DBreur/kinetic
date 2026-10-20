-- Kinetic: dubbele oefeningen samenvoegen en voortaan voorkomen.
--
-- Bij het starten van een training uit een schema werd elke oefening in de
-- catalogus "aangemaakt als hij nog niet bestond" — maar dat controleerde de
-- app voordat de catalogus geladen was, dus bij elke start kwam er een kopie
-- bij. Trainingen en schema's verwijzen op naam naar oefeningen (niet op
-- id), dus samenvoegen raakt niets.
--
-- Per gebruiker en naam (hoofdletters/spaties maken niet uit) blijft één
-- oefening over: de oudste. Die krijgt de langste beschrijving en alle
-- video's en spiergroepen van de kopieën. Daarna een unieke index, zodat de
-- database zelf geen dubbele meer toelaat. Kan veilig opnieuw draaien.

begin;

with g as (
  select
    user_id,
    lower(btrim(name)) as key,
    (array_agg(id order by created_at, id))[1] as keep_id,
    (array_agg(description order by length(description) desc))[1]
      as description
  from public.exercises
  group by user_id, lower(btrim(name))
),
v as (
  select e.user_id, lower(btrim(e.name)) as key, jsonb_agg(distinct x) as vids
  from public.exercises e,
    jsonb_array_elements(coalesce(e.video_urls, '[]'::jsonb)) x
  group by e.user_id, lower(btrim(e.name))
),
m as (
  select e.user_id, lower(btrim(e.name)) as key, jsonb_agg(distinct x) as mgs
  from public.exercises e,
    jsonb_array_elements(coalesce(e.muscle_groups, '[]'::jsonb)) x
  group by e.user_id, lower(btrim(e.name))
),
merged as (
  select g.keep_id, g.description,
    coalesce(v.vids, '[]'::jsonb) as video_urls,
    coalesce(m.mgs, '[]'::jsonb) as muscle_groups
  from g
  left join v on v.user_id = g.user_id and v.key = g.key
  left join m on m.user_id = g.user_id and m.key = g.key
)
update public.exercises x
set description = merged.description,
    video_urls = merged.video_urls,
    muscle_groups = merged.muscle_groups,
    name = btrim(x.name)
from merged
where x.id = merged.keep_id;

delete from public.exercises x
using public.exercises k
where x.user_id = k.user_id
  and lower(btrim(x.name)) = lower(btrim(k.name))
  and (k.created_at, k.id) < (x.created_at, x.id);

create unique index if not exists exercises_user_name_unique
  on public.exercises (user_id, lower(btrim(name)));

commit;
