-- Leilão dos Craques: disputa automática por teto privado e incremento individual.
-- O lote só é resolvido quando os dois participantes salvam seus parâmetros.
-- A função é transacional: bloqueia o lote, calcula o preço e liquida o vencedor no servidor.

create or replace function public.get_my_lot_proxy_setting(p_lot_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    (select jsonb_build_object(
      'configured', true,
      'max_bid', s.max_bid,
      'increment', s.increment
    )
    from public.lot_proxy_settings s
    join public.auction_lots l on l.id=s.lot_id
    join public.participants p on p.id=s.participant_id
    where s.lot_id=p_lot_id
      and p.user_id=auth.uid()
      and p.room_id=l.room_id
    limit 1),
    jsonb_build_object('configured', false)
  );
$$;

create or replace function public.save_lot_proxy(
  p_lot_id uuid,
  p_max_bid numeric,
  p_increment numeric
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_part public.participants;
  v_other public.participants;
  v_lot public.auction_lots;
  v_my_setting public.lot_proxy_settings;
  v_other_setting public.lot_proxy_settings;
  v_winner public.participants;
  v_loser public.participants;
  v_winner_setting public.lot_proxy_settings;
  v_loser_setting public.lot_proxy_settings;
  v_price numeric;
  v_required numeric;
  v_tie boolean := false;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_max_bid is null or p_increment is null
     or p_max_bid <= 0 or p_increment <= 0
     or p_max_bid <> trunc(p_max_bid)
     or p_increment <> trunc(p_increment) then
    raise exception 'Limite máximo e incremento devem ser valores inteiros em reais.';
  end if;

  -- Identifica o participante sem expor ou consultar o teto do adversário.
  select * into v_part
  from public.participants
  where user_id=auth.uid()
    and room_id=(select room_id from public.auction_lots where id=p_lot_id)
  order by created_at desc
  limit 1;
  if not found then raise exception 'Participante não encontrado nesta sala.'; end if;

  -- Serializa as duas configurações para este lote.
  select * into v_lot
  from public.auction_lots
  where id=p_lot_id and room_id=v_part.room_id
  for update;
  if not found or v_lot.status <> 'open' then
    raise exception 'Este lote não está aberto.';
  end if;

  -- Revalida saldo enquanto a linha do participante está bloqueada.
  select * into v_part from public.participants where id=v_part.id for update;
  if p_max_bid < v_lot.starting_bid
     or p_max_bid > (v_part.budget-v_part.spent) then
    raise exception 'O limite deve cobrir o lance inicial e respeitar seu saldo disponível.';
  end if;

  insert into public.lot_proxy_settings(lot_id,participant_id,max_bid,increment)
  values(p_lot_id,v_part.id,p_max_bid,p_increment)
  on conflict (lot_id,participant_id) do update
    set max_bid=excluded.max_bid,
        increment=excluded.increment,
        updated_at=now()
  returning * into v_my_setting;

  select * into v_other
  from public.participants
  where room_id=v_part.room_id and id<>v_part.id
  order by created_at
  limit 1;
  if not found then
    return jsonb_build_object('accepted',true,'resolved',false,'waiting_for_opponent',true);
  end if;

  select * into v_other_setting
  from public.lot_proxy_settings
  where lot_id=p_lot_id and participant_id=v_other.id;
  if not found then
    return jsonb_build_object('accepted',true,'resolved',false,'waiting_for_opponent',true);
  end if;

  -- Verifica novamente o saldo do adversário antes de liquidar.
  select * into v_other from public.participants where id=v_other.id for update;

  if v_my_setting.max_bid > v_other_setting.max_bid then
    v_winner := v_part; v_loser := v_other;
    v_winner_setting := v_my_setting; v_loser_setting := v_other_setting;
  elsif v_my_setting.max_bid < v_other_setting.max_bid then
    v_winner := v_other; v_loser := v_part;
    v_winner_setting := v_other_setting; v_loser_setting := v_my_setting;
  else
    -- Em empate, vence quem registrou o teto primeiro.
    v_tie := true;
    if v_my_setting.created_at <= v_other_setting.created_at then
      v_winner := v_part; v_loser := v_other;
      v_winner_setting := v_my_setting; v_loser_setting := v_other_setting;
    else
      v_winner := v_other; v_loser := v_part;
      v_winner_setting := v_other_setting; v_loser_setting := v_my_setting;
    end if;
  end if;

  if v_tie then
    v_required := greatest(v_lot.starting_bid, v_lot.current_bid);
  else
    v_required := greatest(
      v_lot.starting_bid,
      v_loser_setting.max_bid + v_winner_setting.increment
    );
    if v_lot.current_winner = v_loser.id then
      v_required := greatest(v_required,
        v_lot.current_bid + v_winner_setting.increment);
    end if;
  end if;

  if v_required > v_winner_setting.max_bid
     or v_required > (v_winner.budget-v_winner.spent) then
    update public.auction_lots
      set status='unsold', closed_at=now()
      where id=v_lot.id;
    return jsonb_build_object(
      'accepted',true,'resolved',true,'covered',false,
      'message','Nenhum dos limites consegue cobrir a disputa; lote sem venda.'
    );
  end if;

  v_price := v_required;

  -- Liquidação completa no servidor; o cliente não precisa clicar em novos lances.
  update public.auction_lots
    set current_bid=v_price,
        current_winner=v_winner.id,
        status='sold',
        closed_at=now()
    where id=v_lot.id;

  insert into public.bids(lot_id,participant_id,amount)
    values(v_lot.id,v_winner.id,v_price);

  update public.participants
    set spent=spent+v_price,
        passed_lot_id=null
    where id=v_winner.id;

  insert into public.roster(room_id,participant_id,player_name,position,winning_bid)
    values(v_part.room_id,v_winner.id,v_lot.player_name,v_lot.position,v_price);

  return jsonb_build_object(
    'accepted',true,'resolved',true,'covered',true,
    'current_bid',v_price,
    'you_won',(v_winner.id=v_part.id),
    'winner_name',v_winner.display_name,
    'closed',true
  );
end;
$$;

grant execute on function public.get_my_lot_proxy_setting(uuid) to authenticated;
grant execute on function public.save_lot_proxy(uuid,numeric,numeric) to authenticated;
