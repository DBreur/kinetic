-- Vervangt de losse ground_position-kolom (één waarde) door een lijst —
-- eenzelfde afwerking lukt vaak vanuit meer dan één positie.
alter table public.techniques
  add column if not exists ground_positions jsonb not null default '[]'::jsonb;

update public.techniques
  set ground_positions = jsonb_build_array(ground_position)
  where ground_position is not null and ground_position <> '';

alter table public.techniques drop column if exists ground_position;
