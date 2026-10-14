-- Kinetic: eet-herinneringen. Vaste eetmomenten (dagelijks, met optioneel
-- een melding vooraf) en een eenmalige herinnering vanaf de Eten-pagina,
-- elk apart aan/uit. Puur additief.
alter table public.profiles
  add column if not exists meal_reminders_enabled boolean not null default false,
  -- [{ "label": "Ontbijt", "time": "07:30" }, ...]
  add column if not exists meal_reminders jsonb not null default '[]'::jsonb,
  add column if not exists meal_reminder_offset integer not null default 0
    check (meal_reminder_offset >= 0 and meal_reminder_offset <= 120),
  add column if not exists meal_one_off_enabled boolean not null default true;
