-- 202611240001_meal_macros_context.sql: eiwit, vet en context per maaltijd
-- voor de macrobarometer en de context-chips op het Eten-scherm.
-- Puur additief: bestaande kolommen, data en RLS-policies blijven ongewijzigd.

alter table public.food_log_entries
  add column if not exists protein numeric,
  add column if not exists fat numeric,
  add column if not exists context text;

-- Alleen de vier contexten uit de app (of leeg voor oude regels).
alter table public.food_log_entries
  drop constraint if exists food_log_entries_context_check;
alter table public.food_log_entries
  add constraint food_log_entries_context_check
  check (context is null or context in ('pre_training', 'post_training', 'acute', 'recovery'));
