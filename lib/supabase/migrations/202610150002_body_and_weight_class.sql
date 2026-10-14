-- Kinetic: lichaamsgegevens in het profiel en een gewichtsgrens + doel per
-- wedstrijd. Puur additief (alleen nieuwe, optionele kolommen).

alter table public.profiles
  add column if not exists weight_kg numeric(5, 1)
    check (weight_kg is null or (weight_kg >= 20 and weight_kg <= 300)),
  add column if not exists height_cm integer
    check (height_cm is null or (height_cm >= 50 and height_cm <= 250)),
  add column if not exists sex text not null default ''
    check (sex in ('', 'male', 'female', 'other'));

alter table public.competitions
  -- Gewichtsklasse: vechten onder (of boven) deze grens.
  add column if not exists weight_limit_kg numeric(5, 1)
    check (weight_limit_kg is null or (weight_limit_kg >= 20 and weight_limit_kg <= 300)),
  add column if not exists weight_limit_type text not null default ''
    check (weight_limit_type in ('', 'under', 'over')),
  -- Verwacht / gewenst gewicht op de weging.
  add column if not exists target_weight_kg numeric(5, 1)
    check (target_weight_kg is null or (target_weight_kg >= 20 and target_weight_kg <= 300));
