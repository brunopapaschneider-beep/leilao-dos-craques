-- Quando o limite automático é superado, pausa o lote e pede decisão ao participante.
alter table public.auction_lots
  add column if not exists awaiting_response_from uuid references public.participants(id),
  add column if not exists awaiting_response_at timestamptz;

create or replace function public.place_auction_bid(p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_part public.participants;
  v_other public.participants;
  v_lot public.auction_lots;
  v_room public.rooms;
  v_my_setting public.lot_proxy_settings;
  v_other_setting public.lot_proxy_settings;
  v_min numeric;
  v_auto_price numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_part from public.participants
  where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot from public.auction_lots
  where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found then raise exception 'Não há lote aberto.'; end if;
  if v_lot.awaiting_response_from is not null then
    raise exception 'A disputa está aguardando a decisão do participante que teve seu limite superado.';
  end if;
  select * into v_room from public.rooms where id=v_part.room_id;
  select * into v_my_setting from public.lot_proxy_settings
  where lot_id=v_lot.id and participant_id=v_part.id;
  if not found or v_my_setting.bid_mode<>'manual' then
    raise exception 'Ative o modo manual neste jogador antes de enviar lances manuais.';
  end if;
  if p_amount is null or p_amount<>trunc(p_amount) then
    raise exception 'Somente lances com valores inteiros são aceitos.';
  end if;
  if v_lot.current_winner=v_part.id then raise exception 'Você já possui o maior lance.'; end if;
  v_min:=case when v_lot.current_winner is null then v_lot.starting_bid
              else v_lot.current_bid+greatest(1,ceil(v_room.increment)) end;
  if p_amount<v_min then raise exception 'Lance inválido. O próximo lance inteiro mínimo é %.',v_min; end if;
  if p_amount>(v_part.budget-v_part.spent) then raise exception 'Saldo insuficiente.'; end if;

  update public.auction_lots set current_bid=p_amount,current_winner=v_part.id where id=v_lot.id;
  insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_part.id,p_amount);
  update public.participants set passed_lot_id=null where id=v_part.id;

  select * into v_other from public.participants
  where room_id=v_part.room_id and id<>v_part.id order by created_at limit 1;
  if found then
    select * into v_other_setting from public.lot_proxy_settings
    where lot_id=v_lot.id and participant_id=v_other.id;
    if found and v_other_setting.bid_mode='automatic' then
      v_auto_price:=p_amount+v_other_setting.increment;
      if v_auto_price<=v_other_setting.max_bid
         and v_auto_price<=(v_other.budget-v_other.spent) then
        update public.auction_lots set current_bid=v_auto_price,current_winner=v_other.id where id=v_lot.id;
        insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_other.id,v_auto_price);
        update public.participants set passed_lot_id=null where id=v_other.id;
        return jsonb_build_object('accepted',true,'automatic_reply',true,'current_bid',v_auto_price);
      else
        update public.auction_lots
        set awaiting_response_from=v_other.id, awaiting_response_at=now()
        where id=v_lot.id;
        return jsonb_build_object('accepted',true,'awaiting_response',true,'current_bid',p_amount);
      end if;
    end if;
  end if;
  return jsonb_build_object('accepted',true,'amount',p_amount,'automatic_reply',false);
end;
$$;

create or replace function public.respond_to_overbid(
  p_action text,
  p_new_max numeric default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_part public.participants;
  v_lot public.auction_lots;
  v_setting public.lot_proxy_settings;
  v_min numeric;
  v_price numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_action not in ('manual','automatic','decline') then raise exception 'Decisão inválida.'; end if;

  select * into v_part from public.participants
  where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot from public.auction_lots
  where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found or v_lot.awaiting_response_from is distinct from v_part.id then
    raise exception 'Não há uma decisão pendente para você.';
  end if;
  select * into v_setting from public.lot_proxy_settings
  where lot_id=v_lot.id and participant_id=v_part.id for update;
  if not found then raise exception 'Configuração de lance não encontrada.'; end if;

  if p_action='decline' then
    update public.auction_lots
    set status='sold', closed_at=now(), awaiting_response_from=null, awaiting_response_at=null
    where id=v_lot.id and current_winner is not null;
    if v_lot.current_winner is null then raise exception 'Não há lance vencedor para confirmar.'; end if;
    update public.participants set spent=spent+v_lot.current_bid where id=v_lot.current_winner;
    insert into public.roster(room_id,participant_id,player_name,position,winning_bid)
    values(v_part.room_id,v_lot.current_winner,v_lot.player_name,v_lot.position,v_lot.current_bid);
    return jsonb_build_object('accepted',true,'declined',true,'closed',true,'winner',v_lot.current_winner);
  elsif p_action='manual' then
    update public.lot_proxy_settings set bid_mode='manual', max_bid=null, updated_at=now()
    where lot_id=v_lot.id and participant_id=v_part.id;
    update public.auction_lots set awaiting_response_from=null, awaiting_response_at=null where id=v_lot.id;
    return jsonb_build_object('accepted',true,'mode','manual','waiting_for_manual_bid',true);
  else
    if p_new_max is null or p_new_max<>trunc(p_new_max)
       or p_new_max<=v_lot.current_bid
       or p_new_max>(v_part.budget-v_part.spent) then
      raise exception 'Novo máximo deve ser inteiro, maior que o lance atual e respeitar seu saldo.';
    end if;
    v_min:=v_lot.current_bid+greatest(1,v_setting.increment);
    if v_min>p_new_max then raise exception 'Novo máximo insuficiente para cobrir o próximo lance mínimo de %.',v_min; end if;
    v_price:=v_min;
    update public.lot_proxy_settings
    set max_bid=p_new_max, bid_mode='automatic', updated_at=now()
    where lot_id=v_lot.id and participant_id=v_part.id;
    update public.auction_lots
    set current_bid=v_price,current_winner=v_part.id,
        awaiting_response_from=null,awaiting_response_at=null
    where id=v_lot.id;
    insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_part.id,v_price);
    return jsonb_build_object('accepted',true,'mode','automatic','current_bid',v_price);
  end if;
end;
$$;

grant execute on function public.respond_to_overbid(text,numeric) to authenticated;
grant execute on function public.place_auction_bid(numeric) to authenticated;
