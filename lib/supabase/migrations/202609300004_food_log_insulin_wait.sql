-- Optionele wachttijd (in minuten, stappen van 2,5) tussen insuline nemen en
-- gaan eten. Puur additief.
alter table public.food_log_entries
  add column if not exists insulin_wait_minutes numeric(5, 1);
