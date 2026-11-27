-- Atributos dos jogadores para a primeira versão da simulação.
alter table public.roster add column if not exists rating integer;
update public.roster r
set rating = coalesce((
  select c.rating from public.player_catalog c
  where lower(trim(c.player_name)) = lower(trim(r.player_name))
  order by c.active desc
  limit 1
), 75)
where r.rating is null;
alter table public.roster alter column rating set default 75;
alter table public.roster alter column rating set not null;

create or replace function public.set_roster_player_rating()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_rating integer;
begin
  select c.rating into v_rating
  from public.player_catalog c
  where lower(trim(c.player_name))=lower(trim(new.player_name))
  order by c.active desc
  limit 1;
  new.rating := coalesce(v_rating,new.rating,75);
  return new;
end;
$$;

drop trigger if exists trg_set_roster_player_rating on public.roster;
create trigger trg_set_roster_player_rating
before insert or update of player_name on public.roster
for each row execute function public.set_roster_player_rating();
