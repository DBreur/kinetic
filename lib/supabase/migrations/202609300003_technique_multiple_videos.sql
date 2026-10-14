-- Meerdere video's per techniek i.p.v. één link. Bestaande video's worden
-- overgezet naar de nieuwe lijst voordat de oude kolom verdwijnt, dus er
-- gaat niets verloren.
alter table public.techniques
  add column if not exists video_urls jsonb not null default '[]'::jsonb;

update public.techniques
  set video_urls = to_jsonb(array[video_url])
  where video_url is not null
    and video_url <> ''
    and video_urls = '[]'::jsonb;

alter table public.techniques drop column if exists video_url;
