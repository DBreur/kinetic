alter table public.profiles
  add column if not exists bolus_calculator_enabled boolean not null default false,
  add column if not exists bolus_periods jsonb not null default '[]'::jsonb,
  add column if not exists correction_factor numeric(5, 2) not null default 2.0,
  add column if not exists correction_target_day numeric(4, 1) not null default 8.0,
  add column if not exists correction_target_night numeric(4, 1) not null default 10.0,
  add column if not exists correction_night_start text not null default '19:00',
  add column if not exists correction_night_end text not null default '05:00';

alter table public.food_log_entries
  add column if not exists insulin_food_units numeric(5, 2),
  add column if not exists insulin_correction_units numeric(5, 2);
