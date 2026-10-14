alter table public.combinations
  add column if not exists video_urls jsonb not null default '[]'::jsonb;
