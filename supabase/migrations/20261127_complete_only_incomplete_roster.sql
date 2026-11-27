-- Permite concluir o elenco incompleto quando o outro participante já atingiu 23.
-- Não altera jogadores, lances ou arremates existentes; apenas adiciona jogadores gratuitos faltantes.

create or replace function public.fill_remaining_rosters_randomly()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_host public.participants;
  v_target public.participants;
  v_player public.player_catalog;
  v_added integer := 0;
  v_roomcount integer;
  v_complete_count integer;
begin
  select * into v_host
  from public.participants
  where user_id=auth.uid() and is_host
  order by created_at desc limit 1
  for update;
  if not found then raise exception 'Somente o organizador pode concluir os elencos.'; end if;

  if (select count(*) from public.participants where room_id=v_host.room_id) <> 2 then
    raise exception 'A sala precisa ter exatamente dois participantes.';
  end if;
  if exists(select 1 from public.auction_lots where room_id=v_host.room_id and status='open') then
    raise exception 'Conclua ou encerre a disputa atual antes do preenchimento aleatório.';
  end if;

  select count(*) into v_complete_count
  from public.participants p
  where p.room_id=v_host.room_id
    and (select count(*) from public.roster r where r.participant_id=p.id) >= 23;

  -- Se ninguém completou 23, só permite o preenchimento quando ambos os saldos acabaram.
  if v_complete_count = 0 and exists(
    select 1 from public.participants where room_id=v_host.room_id and budget>spent
  ) then
    raise exception 'O preenchimento aleatório só começa quando os dois saldos estiverem zerados ou um participante completar 23 jogadores.';
  end if;

  loop
    -- Se alguém já completou 23, seleciona exclusivamente quem ainda tem vagas.
    select p.* into v_target
    from public.participants p
    where p.room_id=v_host.room_id
      and (select count(*) from public.roster r where r.participant_id=p.id) < 23
    order by random()
    limit 1
    for update;
    exit when not found;

    select c.* into v_player
    from public.player_catalog c
    where c.active and upper(trim(c.nationality))='BRASIL'
      and not exists(
        select 1 from public.roster r
        where r.room_id=v_host.room_id and lower(r.player_name)=lower(c.player_name)
      )
      and not exists(
        select 1 from public.auction_lots l
        where l.room_id=v_host.room_id
          and (l.player_id=c.id or lower(l.player_name)=lower(c.player_name))
      )
    order by random()
    limit 1;
    if not found then
      raise exception 'Catálogo sem jogadores brasileiros suficientes para completar os elencos.';
    end if;

    insert into public.roster(room_id,participant_id,player_name,position,winning_bid)
    values(v_host.room_id,v_target.id,v_player.player_name,v_player.position,0);
    v_added := v_added + 1;
  end loop;

  select count(*) into v_roomcount from public.roster where room_id=v_host.room_id;

  return jsonb_build_object(
    'completed',true,
    'players_added',v_added,
    'room_roster_count',v_roomcount,
    'target_per_participant',23
  );
end;
$$;

grant execute on function public.fill_remaining_rosters_randomly() to authenticated;
