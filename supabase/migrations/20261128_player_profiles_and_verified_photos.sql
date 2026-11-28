-- Perfil do atleta: dados biográficos e imagem somente quando verificados.
-- Campos vazios permanecem como "Não informado" na interface; não preencher por suposição.

alter table public.player_catalog
  add column if not exists last_club text,
  add column if not exists last_club_country text,
  add column if not exists last_club_season text,
  add column if not exists peak_career text,
  add column if not exists peak_season text,
  add column if not exists profile_source_url text,
  add column if not exists image_url text,
  add column if not exists image_source_url text;

alter table public.auction_lots
  add column if not exists last_club text,
  add column if not exists last_club_country text,
  add column if not exists last_club_season text,
  add column if not exists peak_career text,
  add column if not exists peak_season text,
  add column if not exists profile_source_url text,
  add column if not exists image_url text,
  add column if not exists image_source_url text;

create or replace function public.copy_player_profile_to_auction_lot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.player_id is not null then
    select
      coalesce(new.last_club, p.last_club),
      coalesce(new.last_club_country, p.last_club_country),
      coalesce(new.last_club_season, p.last_club_season),
      coalesce(new.peak_career, p.peak_career),
      coalesce(new.peak_season, p.peak_season),
      coalesce(new.profile_source_url, p.profile_source_url),
      coalesce(new.image_url, p.image_url),
      coalesce(new.image_source_url, p.image_source_url)
    into
      new.last_club,
      new.last_club_country,
      new.last_club_season,
      new.peak_career,
      new.peak_season,
      new.profile_source_url,
      new.image_url,
      new.image_source_url
    from public.player_catalog p
    where p.id = new.player_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_copy_player_profile_to_auction_lot on public.auction_lots;
create trigger trg_copy_player_profile_to_auction_lot
before insert or update of player_id on public.auction_lots
for each row execute function public.copy_player_profile_to_auction_lot();

-- Atualiza os lotes existentes com os dados que já estiverem cadastrados no catálogo.
update public.auction_lots l
set
  last_club = coalesce(l.last_club, p.last_club),
  last_club_country = coalesce(l.last_club_country, p.last_club_country),
  last_club_season = coalesce(l.last_club_season, p.last_club_season),
  peak_career = coalesce(l.peak_career, p.peak_career),
  peak_season = coalesce(l.peak_season, p.peak_season),
  profile_source_url = coalesce(l.profile_source_url, p.profile_source_url),
  image_url = coalesce(l.image_url, p.image_url),
  image_source_url = coalesce(l.image_source_url, p.image_source_url)
from public.player_catalog p
where l.player_id = p.id;
