-- Regras de saldo e encerramento dos elencos com 23 jogadores por participante.
-- Preserva lotes, lances e jogadores já arrematados na sala de teste.

create or replace function public.guard_lot_proxy_positive_balance()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_part public.participants;
begin
  select * into v_part from public.participants where id=new.participant_id for update;
  if not found then raise exception 'Participante não encontrado.'; end if;
  if greatest(0, v_part.budget-v_part.spent) <= 0 then
    raise exception 'Seu saldo está zerado. Você não pode configurar lances; apenas desistir do lote.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lot_proxy_positive_balance on public.lot_proxy_settings;
create trigger trg_lot_proxy_positive_balance
before insert or update on public.lot_proxy_settings
for each row execute function public.guard_lot_proxy_positive_balance();

create or replace function public.open_random_auction_lot()
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_part public.participants;
  v_player public.player_catalog;
  v_lot public.auction_lots;
  v_total integer;
begin
  select * into v_part
  from public.participants
  where user_id=auth.uid() and is_host
  order by created_at desc limit 1;
  if not found then raise exception 'Somente o organizador pode sortear o próximo jogador.'; end if;
  if (select count(*) from public.participants where room_id=v_part.room_id) <> 2 then
    raise exception 'A sala precisa ter exatamente dois participantes.';
  end if;
  if exists(select 1 from public.auction_lots where room_id=v_part.room_id and status='open') then
    raise exception 'Já existe um jogador em disputa.';
  end if;
  if not exists(select 1 from public.participants where room_id=v_part.room_id and budget>spent) then
    raise exception 'Os dois orçamentos foram encerrados. Execute o preenchimento aleatório dos elencos.';
  end if;
  if exists(
    select 1 from public.participants p
    where p.room_id=v_part.room_id
      and (select count(*) from public.roster r where r.participant_id=p.id) >= 23
  ) then
    raise exception 'Um dos participantes já completou 23 jogadores.';
  end if;

  select count(*) into v_total from public.roster where room_id=v_part.room_id;

  select p.* into v_player
  from public.player_catalog p
  where p.active and upper(trim(p.nationality))='BRASIL'
    and not exists(
      select 1 from public.auction_lots l
      where l.room_id=v_part.room_id
        and (l.player_id=p.id or lower(l.player_name)=lower(p.player_name))
    )
    and not exists(
      select 1 from public.roster r
      where r.room_id=v_part.room_id and lower(r.player_name)=lower(p.player_name)
    )
    and (
      v_total >= 36
      or case p.position
        when 'Goleiro' then 4
        when 'Lateral-direito' then 4
        when 'Zagueiro' then 8
        when 'Lateral-esquerdo' then 4
        when 'Volante' then 4
        when 'Meio-campo' then 6
        when 'Atacante' then 6
        else 0
      end > (select count(*) from public.roster r where r.room_id=v_part.room_id and r.position=p.position)
    )
  order by random()
  limit 1;
  if not found then raise exception 'Não há jogadores brasileiros disponíveis no catálogo para este sorteio.'; end if;

  insert into public.auction_lots
    (room_id,player_id,player_name,position,nationality,wiki_title,rating,is_superstar,starting_bid,current_bid)
  values
    (v_part.room_id,v_player.id,v_player.player_name,v_player.position,v_player.nationality,
     v_player.wiki_title,v_player.rating,v_player.is_superstar,1,1)
  returning * into v_lot;
  update public.rooms set status='active' where id=v_part.room_id;
  return v_lot.id;
end;
$$;

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
  v_count integer;
  v_added integer := 0;
  v_brunocount integer;
  v_roomcount integer;
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
  if exists(
    select 1 from public.participants
    where room_id=v_host.room_id and budget>spent
  ) then
    raise exception 'O preenchimento aleatório só começa quando os dois saldos estiverem zerados.';
  end if;

  loop
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
      raise exception 'Catálogo sem jogadores brasileiros suficientes para completar os dois elencos.';
    end if;

    insert into public.roster(room_id,participant_id,player_name,position,winning_bid)
    values(v_host.room_id,v_target.id,v_player.player_name,v_player.position,0);
    v_added := v_added + 1;
  end loop;

  select count(*) into v_brunocount
  from public.roster r join public.participants p on p.id=r.participant_id
  where p.room_id=v_host.room_id and p.id=v_host.id;
  select count(*) into v_roomcount from public.roster where room_id=v_host.room_id;

  return jsonb_build_object(
    'completed',true,
    'players_added',v_added,
    'room_roster_count',v_roomcount,
    'host_roster_count',v_brunocount,
    'target_per_participant',23
  );
end;
$$;

grant execute on function public.open_random_auction_lot() to authenticated;
grant execute on function public.fill_remaining_rosters_randomly() to authenticated;
