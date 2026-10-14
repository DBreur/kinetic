-- Kinetic: eerste dag van de week in kalenders (0 = zondag, 1 = maandag,
-- 6 = zaterdag; standaard maandag). Puur additief.
alter table public.profiles
  add column if not exists week_start smallint not null default 1
    check (week_start in (0, 1, 6));
