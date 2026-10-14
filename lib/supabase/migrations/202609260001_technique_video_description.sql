alter table public.techniques
  add column if not exists description text not null default '',
  add column if not exists video_url text not null default '';
