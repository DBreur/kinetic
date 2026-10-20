-- Kinetic: hoe de rondes van een circuit met blokken lopen. true = per
-- blok (blok A al zijn rondes, dan blok B), false = het hele circuit
-- telkens één keer door (blokken zijn dan alleen een groepering). Puur
-- additief; Uchivo negeert deze kolom.
alter table public.circuits
  add column if not exists rounds_per_block boolean not null default true;
