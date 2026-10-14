update public.profiles set glucose_source = 'nightscout' where glucose_source = 'cgm';

alter table public.profiles
  add column if not exists dexcom_username text not null default '',
  add column if not exists dexcom_server text not null default 'shareous1.dexcom.com';
