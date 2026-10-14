alter table public.techniques
  add column if not exists transition text not null default '',
  add column if not exists favorite boolean not null default false;
