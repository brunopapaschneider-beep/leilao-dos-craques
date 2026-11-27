-- Modo manual e automático por participante/lote, com resposta automática do proxy.
alter table public.lot_proxy_settings
  add column if not exists bid_mode text not null default 'automatic';

do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.lot_proxy_settings'::regclass
      and contype='c' and pg_get_constraintdef(oid) ilike '%max_bid%'
  loop
    execute format('alter table public.lot_proxy_settings drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.lot_proxy_settings alter column max_bid drop not null;
alter table public.lot_proxy_settings
  add constraint lot_proxy_settings_max_bid_valid check (max_bid is null or max_bid > 0);
alter table public.lot_proxy_settings
  add constraint lot_proxy_settings_bid_mode_valid check (bid_mode in ('automatic','manual'));

create or replace function public.get_my_lot_proxy_setting(p_lot_id uuid)
returns jsonb
language sql stable security definer set search_path=public
as $$
  select jsonb_build_object(
    'configured', true,
    'mode', bid_mode,
    'max_bid', max_bid,
    'increment', increment
  )
  from public.lot_proxy_settings s
  join public.participants p on p.id=s.participant_id
  where s.lot_id=p_lot_id and p.user_id=auth.uid()
  limit 1
$$;

drop function if exists public.save_lot_proxy(uuid,numeric,numeric);
create or replace function public.save_lot_proxy(
  p_lot_id uuid,
  p_max_bid numeric,
  p_increment numeric,
  p_mode text default 'automatic'
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_part public.participants;
  v_other public.participants;
  v_lot public.auction_lots;
  v_my public.lot_proxy_settings;
  v_other_setting public.lot_proxy_settings;
  v_winner public.participants;
  v_loser public.participants;
  v_winner_setting public.lot_proxy_settings;
  v_loser_setting public.lot_proxy_settings;
  v_price numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_mode not in ('automatic','manual') then raise exception 'Modo de lance inválido.'; end if;

  select * into v_part from public.participants
  where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot from public.auction_lots
  where id=p_lot_id and room_id=v_part.room_id for update;
  if not found or v_lot.status <> 'open' then raise exception 'Este lote não está aberto.'; end if;

  if p_increment is null or p_increment < 1 or p_increment <> trunc(p_increment) then
    raise exception 'O incremento deve ser um número inteiro maior ou igual a 1.';
  end if;

  if p_mode='automatic' then
    if p_max_bid is null or p_max_bid < v_lot.starting_bid
       or p_max_bid <> trunc(p_max_bid)
       or p_max_bid > (v_part.budget-v_part.spent) then
      raise exception 'O máximo automático deve ser inteiro, cobrir o lance inicial e respeitar seu saldo.';
    end if;
  else
    p_max_bid := null;
  end if;

  insert into public.lot_proxy_settings(lot_id,participant_id,max_bid,increment,bid_mode)
  values(p_lot_id,v_part.id,p_max_bid,p_increment,p_mode)
  on conflict (lot_id,participant_id) do update
    set max_bid=excluded.max_bid, increment=excluded.increment,
        bid_mode=excluded.bid_mode, updated_at=now()
  returning * into v_my;

  select * into v_other from public.participants
  where room_id=v_part.room_id and id<>v_part.id
  order by created_at limit 1;
  if not found then
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true,'mode',p_mode);
  end if;

  select * into v_other_setting from public.lot_proxy_settings
  where lot_id=p_lot_id and participant_id=v_other.id;

  if not found then
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true,'mode',p_mode);
  end if;

  -- Dois automáticos: liquida a disputa imediatamente pelo menor preço necessário.
  if v_my.bid_mode='automatic' and v_other_setting.bid_mode='automatic' then
    if v_my.max_bid > v_other_setting.max_bid
       or (v_my.max_bid=v_other_setting.max_bid and v_my.created_at<=v_other_setting.created_at) then
      v_winner:=v_part; v_loser:=v_other;
      v_winner_setting:=v_my; v_loser_setting:=v_other_setting;
    else
      v_winner:=v_other; v_loser:=v_part;
      v_winner_setting:=v_other_setting; v_loser_setting:=v_my;
    end if;

    v_price:=greatest(v_lot.starting_bid,v_loser_setting.max_bid+v_winner_setting.increment);
    if v_lot.current_winner=v_loser.id then
      v_price:=greatest(v_price,v_lot.current_bid+v_winner_setting.increment);
    end if;

    if v_price<=v_winner_setting.max_bid
       and v_price<=(v_winner.budget-v_winner.spent) then
      update public.auction_lots set current_bid=v_price,current_winner=v_winner.id where id=v_lot.id;
      insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_winner.id,v_price);
      update public.participants set passed_lot_id=null where id in (v_part.id,v_other.id);
      return jsonb_build_object('accepted',true,'resolved',true,'covered',true,
        'current_bid',v_price,'you_won',(v_winner.id=v_part.id));
    else
      return jsonb_build_object('accepted',true,'resolved',false,'covered',false,
        'waiting_for_manual',true);
    end if;
  end if;

  -- Se um modo automático for configurado depois de um lance manual,
  -- ele responde imediatamente se ainda tiver teto e saldo.
  if v_my.bid_mode='automatic' and v_lot.current_winner=v_other.id then
    v_price:=v_lot.current_bid+v_my.increment;
    if v_price<=v_my.max_bid and v_price<=(v_part.budget-v_part.spent) then
      update public.auction_lots set current_bid=v_price,current_winner=v_part.id where id=v_lot.id;
      insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_part.id,v_price);
      return jsonb_build_object('accepted',true,'automatic_reply',true,'current_bid',v_price);
    end if;
  elsif v_other_setting.bid_mode='automatic' and v_lot.current_winner=v_part.id then
    v_price:=v_lot.current_bid+v_other_setting.increment;
    if v_price<=v_other_setting.max_bid and v_price<=(v_other.budget-v_other.spent) then
      update public.auction_lots set current_bid=v_price,current_winner=v_other.id where id=v_lot.id;
      insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_other.id,v_price);
      return jsonb_build_object('accepted',true,'automatic_reply',true,'current_bid',v_price);
    end if;
  end if;

  return jsonb_build_object('accepted',true,'resolved',false,'mixed_modes',true);
end;
$$;

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
  v_auto_balance numeric;
  v_auto_id uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_part from public.participants
  where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;

  select * into v_lot from public.auction_lots
  where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found then raise exception 'Não há lote aberto.'; end if;
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
      v_auto_balance:=v_other.budget-v_other.spent;
      if v_auto_price<=v_other_setting.max_bid and v_auto_price<=v_auto_balance then
        update public.auction_lots set current_bid=v_auto_price,current_winner=v_other.id where id=v_lot.id;
        insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_other.id,v_auto_price);
        update public.participants set passed_lot_id=null where id=v_other.id;
        return jsonb_build_object('accepted',true,'amount',p_amount,
          'automatic_reply',true,'current_bid',v_auto_price);
      end if;
    end if;
  end if;

  return jsonb_build_object('accepted',true,'amount',p_amount,'automatic_reply',false);
end;
$$;

grant execute on function public.get_my_lot_proxy_setting(uuid) to authenticated;
grant execute on function public.save_lot_proxy(uuid,numeric,numeric,text) to authenticated;
grant execute on function public.place_auction_bid(numeric) to authenticated;
