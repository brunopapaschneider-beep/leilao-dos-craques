-- Leilao dos Craques: lances, limites e incrementos somente em reais inteiros.
-- A validacao ocorre no servidor; a interface nao e a barreira de seguranca.

alter table public.lot_proxy_settings
  drop constraint if exists lot_proxy_settings_max_bid_integer,
  drop constraint if exists lot_proxy_settings_increment_integer;

alter table public.lot_proxy_settings
  add constraint lot_proxy_settings_max_bid_integer
    check (max_bid = trunc(max_bid)),
  add constraint lot_proxy_settings_increment_integer
    check (increment = trunc(increment));

create or replace function public.place_auction_bid(p_amount numeric)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_part public.participants;
  v_lot public.auction_lots;
  v_room public.rooms;
  v_min numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> trunc(p_amount) then
    raise exception 'Lances aceitam somente valores inteiros em reais.';
  end if;

  select * into v_part
  from public.participants
  where user_id=auth.uid()
  order by created_at desc
  limit 1
  for update;

  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot
  from public.auction_lots
  where room_id=v_part.room_id and status='open'
  order by created_at desc
  limit 1
  for update;

  if not found then raise exception 'Não há lote aberto.'; end if;
  if v_lot.current_winner=v_part.id then raise exception 'Você já possui o maior lance.'; end if;

  select * into v_room from public.rooms where id=v_part.room_id;
  v_min := case
    when v_lot.current_winner is null then v_lot.starting_bid
    else v_lot.current_bid + coalesce(v_room.increment,1)
  end;

  if p_amount <> v_min then
    raise exception 'Lance inválido. O próximo lance inteiro é R$ %.',v_min;
  end if;
  if p_amount > v_part.max_bid then raise exception 'Seu valor máximo privado foi atingido.'; end if;
  if p_amount > (v_part.budget-v_part.spent) then raise exception 'Saldo insuficiente.'; end if;

  update public.auction_lots
  set current_bid=p_amount,current_winner=v_part.id
  where id=v_lot.id;
  insert into public.bids(lot_id,participant_id,amount)
  values(v_lot.id,v_part.id,p_amount);
  update public.participants set passed_lot_id=null where id=v_part.id;

  return jsonb_build_object('accepted',true,'amount',p_amount);
end;
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
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_max_bid is null or p_increment is null
     or p_max_bid <= 0 or p_increment <= 0
     or p_max_bid <> trunc(p_max_bid)
     or p_increment <> trunc(p_increment) then
    raise exception 'Limite máximo e incremento devem ser valores inteiros em reais.';
  end if;

  select * into v_part
  from public.participants
  where user_id=auth.uid()
  order by created_at desc
  limit 1
  for update;

  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot
  from public.auction_lots
  where id=p_lot_id and room_id=v_part.room_id
  for update;

  if not found or v_lot.status <> 'open' then
    raise exception 'Este lote não está aberto.';
  end if;

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

  -- Keep the legacy private-limit RPC/UI in sync with the per-lot proxy ceiling.
  update public.participants
  set max_bid = p_max_bid
  where id = v_part.id;

  select * into v_other
  from public.participants
  where room_id=v_part.room_id and id<>v_part.id
  order by created_at
  limit 1;

  if not found then
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true);
  end if;

  select * into v_other_setting
  from public.lot_proxy_settings
  where lot_id=p_lot_id and participant_id=v_other.id;

  if not found then
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true);
  end if;

  -- Determine the winner by ceiling; ties go to the earliest registered setting.
  if v_my_setting.max_bid > v_other_setting.max_bid
     or (v_my_setting.max_bid = v_other_setting.max_bid
         and v_my_setting.created_at <= v_other_setting.created_at) then
    v_winner := v_part;
    v_loser := v_other;
    v_winner_setting := v_my_setting;
    v_loser_setting := v_other_setting;
  else
    v_winner := v_other;
    v_loser := v_part;
    v_winner_setting := v_other_setting;
    v_loser_setting := v_my_setting;
  end if;

  -- Winner only pays the smallest whole-real amount needed to beat the rival's ceiling.
  v_required := greatest(
    v_lot.starting_bid,
    v_loser_setting.max_bid + v_winner_setting.increment
  );

  -- If a public manual bid is already higher, the proxy winner must beat it too.
  if v_lot.current_winner = v_loser.id then
    v_required := greatest(v_required,
      v_lot.current_bid + v_winner_setting.increment);
  end if;

  if v_required > v_winner_setting.max_bid
     or v_required > (v_winner.budget-v_winner.spent) then
    -- No valid automatic cover: keep the current public state and report no cover.
    return jsonb_build_object(
      'accepted',true,'resolved',true,'covered',false,
      'current_bid',v_lot.current_bid,
      'message','Nenhum limite consegue cobrir a disputa.'
    );
  end if;

  v_price := v_required;

  update public.auction_lots
  set current_bid=v_price,current_winner=v_winner.id
  where id=v_lot.id;

  insert into public.bids(lot_id,participant_id,amount)
  values(v_lot.id,v_winner.id,v_price);

  update public.participants set passed_lot_id=null
  where id in (v_part.id,v_other.id);

  return jsonb_build_object(
    'accepted',true,'resolved',true,'covered',true,
    'current_bid',v_price,
    'you_won',(v_winner.id=v_part.id),
    'winner_name',v_winner.display_name
  );
end;
$$;

grant execute on function public.place_auction_bid(numeric) to authenticated;
grant execute on function public.save_lot_proxy(uuid,numeric,numeric) to authenticated;
