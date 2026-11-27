-- Proxy bidding per lot: private maxima and increments are stored server-side.
create table if not exists public.lot_proxy_settings (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.auction_lots(id) on delete cascade,
  participant_id uuid not null references public.participants(id) on delete cascade,
  max_bid numeric(12,2) not null check (max_bid > 0),
  increment numeric(12,2) not null check (increment > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lot_id, participant_id)
);

alter table public.lot_proxy_settings enable row level security;
revoke all on public.lot_proxy_settings from anon, authenticated;
drop policy if exists "no direct proxy settings access" on public.lot_proxy_settings;

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
  v_price numeric(12,2);
  v_minimum numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;

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

  if p_increment <= 0 or p_max_bid < v_lot.starting_bid
     or p_max_bid > (v_part.budget-v_part.spent) then
    raise exception 'Confira o máximo e o incremento: o máximo deve cobrir o lance inicial e respeitar seu saldo.';
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
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true);
  end if;

  select * into v_other_setting
  from public.lot_proxy_settings
  where lot_id=p_lot_id and participant_id=v_other.id;

  if not found then
    return jsonb_build_object('accepted',true,'waiting_for_opponent',true);
  end if;

  -- Resolve the proxy contest privately. Equal ceilings go to the participant
  -- who registered the ceiling first.
  if v_my_setting.max_bid > v_other_setting.max_bid then
    v_winner := v_part;
    v_loser := v_other;
    v_winner_setting := v_my_setting;
    v_loser_setting := v_other_setting;
  elsif v_my_setting.max_bid < v_other_setting.max_bid then
    v_winner := v_other;
    v_loser := v_part;
    v_winner_setting := v_other_setting;
    v_loser_setting := v_my_setting;
  elsif v_my_setting.created_at <= v_other_setting.created_at then
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

  -- Respect a manual bid already placed by the losing participant.
  v_minimum := greatest(v_lot.starting_bid,
    v_loser_setting.max_bid + v_winner_setting.increment);
  if v_lot.current_winner = v_loser.id then
    v_minimum := greatest(v_minimum,
      v_lot.current_bid + v_winner_setting.increment);
  end if;

  v_price := least(v_winner_setting.max_bid, v_minimum);

  if v_price < v_lot.starting_bid then
    raise exception 'Não há limite suficiente para cobrir o lance inicial.';
  end if;

  update public.auction_lots
  set current_bid=v_price,current_winner=v_winner.id
  where id=v_lot.id;

  insert into public.bids(lot_id,participant_id,amount)
  values(v_lot.id,v_winner.id,v_price);

  update public.participants set passed_lot_id=null
  where id in (v_part.id,v_other.id);

  return jsonb_build_object(
    'accepted',true,
    'resolved',true,
    'current_bid',v_price,
    'you_won',(v_winner.id=v_part.id)
  );
end;
$$;

grant execute on function public.save_lot_proxy(uuid,numeric,numeric) to authenticated;
