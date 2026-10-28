-- Kinetic: focus op een techniek, niet alleen "de eerstvolgende training"
-- maar ook voor een aantal trainingen of tot een datum.
--   focus_mode: 'none' | 'next' | 'count' | 'until'
--   focus_trainings_left: bij 'count' — telt af bij elke opgeslagen
--     training waarin je de techniek oefende
--   focus_until: bij 'until' — t/m deze dag
-- practice_next blijft bestaan (andere apps lezen hem) en volgt de focus.
-- Puur additief; bestaande "eerstvolgende training" wordt focus_mode 'next'.
alter table public.techniques
  add column if not exists focus_mode text not null default 'none'
    check (focus_mode in ('none', 'next', 'count', 'until')),
  add column if not exists focus_trainings_left integer
    check (focus_trainings_left is null or focus_trainings_left >= 0),
  add column if not exists focus_until timestamptz,
  add column if not exists focus_started_at timestamptz;

update public.techniques
set focus_mode = 'next', focus_started_at = coalesce(focus_started_at, now())
where practice_next and focus_mode = 'none';
