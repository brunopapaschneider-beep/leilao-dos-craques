-- Corrige o catálogo: somente atletas brasileiros podem ser sorteados.
-- 1) Desativa registros estrangeiros que entraram na carga inicial.
update public.player_catalog
set active = false
where upper(trim(nationality)) not in ('BRASIL','BRASILEIRA','BRASILEIRO');

-- 2) Fecha como não vendidos os lotes estrangeiros que ainda estejam abertos.
update public.auction_lots
set status = 'unsold',
    closed_at = coalesce(closed_at, now())
where status = 'open'
  and coalesce(nationality,'') <> 'Brasil';

-- 3) Reforça a regra no próprio sorteio: nacionalidade brasileira obrigatória.
create or replace function public.open_random_auction_lot()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
  v_player public.player_catalog;
  v_lot public.auction_lots;
begin
  select * into v_part
  from public.participants
  where user_id = auth.uid() and is_host
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'Somente o organizador pode sortear o próximo jogador.';
  end if;

  if (select count(*) from public.participants where room_id = v_part.room_id) < 2 then
    raise exception 'Aguardando o segundo participante.';
  end if;

  if exists (
    select 1 from public.auction_lots
    where room_id = v_part.room_id and status = 'open'
  ) then
    raise exception 'Já existe um jogador em disputa.';
  end if;

  select p.* into v_player
  from public.player_catalog p
  where p.active
    and upper(trim(p.nationality)) = 'BRASIL'
    and not exists (
      select 1 from public.auction_lots l
      where l.room_id = v_part.room_id
        and (l.player_id = p.id or lower(l.player_name) = lower(p.player_name))
    )
    and exists (
      select 1
      from public.participants participant
      where participant.room_id = v_part.room_id
        and (
          select count(*)
          from public.roster r
          where r.room_id = participant.room_id
            and r.participant_id = participant.id
            and r.position = p.position
        ) < case p.position
              when 'Goleiro' then 2
              when 'Lateral-direito' then 2
              when 'Zagueiro' then 4
              when 'Lateral-esquerdo' then 2
              when 'Volante' then 2
              when 'Meio-campo' then 3
              when 'Atacante' then 3
              else 0
            end
    )
  order by random()
  limit 1;

  if not found then
    raise exception 'Não há jogadores brasileiros ativos disponíveis para as vagas restantes.';
  end if;

  insert into public.auction_lots
    (room_id, player_id, player_name, position, nationality, wiki_title, rating,
     is_superstar, starting_bid, current_bid)
  values
    (v_part.room_id, v_player.id, v_player.player_name, v_player.position,
     v_player.nationality, v_player.wiki_title, v_player.rating,
     v_player.is_superstar, 1, 1)
  returning * into v_lot;

  update public.rooms set status = 'active' where id = v_part.room_id;
  return v_lot.id;
end;
$$;

grant execute on function public.open_random_auction_lot() to authenticated;
