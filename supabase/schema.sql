-- LEILÃO DOS CRAQUES — esquema inicial para Supabase
-- Execute no SQL Editor de um projeto Supabase novo.
create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  host_user_id uuid not null,
  status text not null default 'waiting' check (status in ('waiting','active','finished')),
  increment numeric(12,2) not null default 1 check (increment > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null,
  display_name text not null,
  is_host boolean not null default false,
  budget numeric(12,2) not null default 1000 check (budget >= 0),
  spent numeric(12,2) not null default 0 check (spent >= 0),
  max_bid numeric(12,2) not null default 250 check (max_bid >= 0),
  passed_lot_id uuid,
  connected boolean not null default true,
  created_at timestamptz not null default now(),
  unique(room_id,user_id)
);

create table if not exists public.auction_lots (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  player_name text not null,
  position text not null,
  starting_bid numeric(12,2) not null check (starting_bid > 0),
  current_bid numeric(12,2) not null,
  current_winner uuid references public.participants(id),
  status text not null default 'open' check (status in ('open','sold','unsold')),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.bids (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.auction_lots(id) on delete cascade,
  participant_id uuid not null references public.participants(id),
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create table if not exists public.roster (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  participant_id uuid not null references public.participants(id),
  player_name text not null,
  position text not null,
  winning_bid numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_participants_room on public.participants(room_id);
create index if not exists idx_lots_room_status on public.auction_lots(room_id,status);
create index if not exists idx_bids_lot on public.bids(lot_id,created_at);

alter table public.rooms enable row level security;
alter table public.participants enable row level security;
alter table public.auction_lots enable row level security;
alter table public.bids enable row level security;
alter table public.roster enable row level security;

-- Função auxiliar SECURITY DEFINER evita recursão nas políticas de participantes.
create or replace function public.is_room_member(p_room uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.participants p where p.room_id=p_room and p.user_id=auth.uid())
$$;

create policy "room members read rooms" on public.rooms for select to authenticated
using (public.is_room_member(id));
create policy "room members read participants public" on public.participants for select to authenticated
using (public.is_room_member(room_id));
create policy "room members read lots" on public.auction_lots for select to authenticated
using (public.is_room_member(room_id));
create policy "room members read bids" on public.bids for select to authenticated
using (exists(select 1 from public.auction_lots l where l.id=bids.lot_id and public.is_room_member(l.room_id)));
create policy "room members read roster" on public.roster for select to authenticated
using (public.is_room_member(room_id));

-- Bloqueia leitura direta do teto secreto: somente RPC própria devolve o limite do usuário.
revoke all on public.participants from anon, authenticated;
grant select (id,room_id,user_id,display_name,is_host,budget,spent,passed_lot_id,connected,created_at) on public.participants to authenticated;

create or replace function public.create_auction_room(p_name text, p_budget numeric, p_increment numeric, p_player_limit numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_room rooms; v_part participants; v_code text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if length(trim(p_name)) < 2 or p_budget <= 0 or p_increment <= 0 or p_player_limit <= 0 or p_player_limit > p_budget then raise exception 'Dados inválidos: confira nome, orçamento e teto individual.'; end if;
  v_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,6));
  insert into rooms(room_code,host_user_id,increment) values(v_code,auth.uid(),p_increment) returning * into v_room;
  insert into participants(room_id,user_id,display_name,is_host,budget,max_bid)
  values(v_room.id,auth.uid(),trim(p_name),true,p_budget,p_player_limit) returning * into v_part;
  return jsonb_build_object('room_id',v_room.id,'room_code',v_code,'participant_id',v_part.id);
end $$;

create or replace function public.join_auction_room(p_code text, p_name text, p_budget numeric, p_limit numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_room rooms; v_part participants;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_room from rooms where room_code=upper(trim(p_code)) and status='waiting';
  if not found then raise exception 'Sala não encontrada ou já iniciada.'; end if;
  if (select count(*) from participants where room_id=v_room.id) >= 2 then raise exception 'Sala cheia.'; end if;
  if length(trim(p_name)) < 2 or p_budget <= 0 or p_limit <= 0 or p_limit > p_budget then raise exception 'Dados inválidos: confira nome, orçamento e teto individual.'; end if;
  insert into participants(room_id,user_id,display_name,budget,max_bid)
  values(v_room.id,auth.uid(),trim(p_name),p_budget,p_limit) returning * into v_part;
  return jsonb_build_object('room_id',v_room.id,'participant_id',v_part.id);
end $$;

create or replace function public.get_my_private_limit()
returns numeric language sql stable security definer set search_path=public as $$
  select max_bid from public.participants where user_id=auth.uid() order by created_at desc limit 1
$$;

create or replace function public.set_my_private_limit(p_limit numeric)
returns numeric language plpgsql security definer set search_path=public as $$
declare v_part participants;
begin
  select * into v_part from participants where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;
  if p_limit <= 0 or p_limit > (v_part.budget-v_part.spent) then raise exception 'Limite inválido ou acima do saldo disponível.'; end if;
  update participants set max_bid=p_limit where id=v_part.id;
  return p_limit;
end $$;

create or replace function public.open_auction_lot(p_player_name text, p_position text, p_starting_bid numeric)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_part participants; v_lot auction_lots;
begin
  select * into v_part from participants where user_id=auth.uid() and is_host order by created_at desc limit 1;
  if not found then raise exception 'Somente o organizador pode abrir um lote.'; end if;
  if exists(select 1 from auction_lots where room_id=v_part.room_id and status='open') then raise exception 'Já existe um jogador em disputa.'; end if;
  if (select count(*) from participants where room_id=v_part.room_id) < 2 then raise exception 'Aguardando o segundo participante.'; end if;
  insert into auction_lots(room_id,player_name,position,starting_bid,current_bid)
  values(v_part.room_id,trim(p_player_name),p_position,p_starting_bid,p_starting_bid) returning * into v_lot;
  update rooms set status='active' where id=v_part.room_id;
  return v_lot.id;
end $$;

create or replace function public.place_auction_bid(p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_part participants; v_lot auction_lots; v_room rooms; v_min numeric;
begin
  select * into v_part from participants where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;
  select * into v_lot from auction_lots where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found then raise exception 'Não há lote aberto.'; end if;
  select * into v_room from rooms where id=v_part.room_id;
  v_min := case when v_lot.current_winner is null then v_lot.starting_bid else v_lot.current_bid + v_room.increment end;
  if v_lot.current_winner=v_part.id then raise exception 'Você já possui o maior lance.'; end if;
  if p_amount <> v_min then raise exception 'Lance inválido. Próximo lance: %',v_min; end if;
  if p_amount > v_part.max_bid then raise exception 'Seu limite privado foi atingido.'; end if;
  if p_amount > (v_part.budget-v_part.spent) then raise exception 'Saldo insuficiente.'; end if;
  update auction_lots set current_bid=p_amount,current_winner=v_part.id where id=v_lot.id;
  insert into bids(lot_id,participant_id,amount) values(v_lot.id,v_part.id,p_amount);
  update participants set passed_lot_id=null where id=v_part.id;
  return jsonb_build_object('accepted',true,'amount',p_amount);
end $$;

create or replace function public.pass_auction_lot()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_part participants; v_lot auction_lots; v_other participants; v_count int;
begin
  select * into v_part from participants where user_id=auth.uid() order by created_at desc limit 1 for update;
  select * into v_lot from auction_lots where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found then raise exception 'Não há lote aberto.'; end if;
  if v_lot.current_winner is not null then
    if v_lot.current_winner = v_part.id then
      raise exception 'Você está com o maior lance; aguarde o adversário passar ou cobrir.';
    end if;
    update auction_lots set status='sold',closed_at=now() where id=v_lot.id;
    update participants set spent=spent+v_lot.current_bid where id=v_lot.current_winner;
    insert into roster(room_id,participant_id,player_name,position,winning_bid)
    values(v_part.room_id,v_lot.current_winner,v_lot.player_name,v_lot.position,v_lot.current_bid);
    return jsonb_build_object('passed',true,'closed',true,'winner',v_lot.current_winner);
  end if;
  update participants set passed_lot_id=v_lot.id where id=v_part.id;
  select count(*) into v_count from participants where room_id=v_part.room_id and passed_lot_id=v_lot.id;
  if v_count >= 2 then
    update auction_lots set status='unsold',closed_at=now() where id=v_lot.id;
  end if;
  return jsonb_build_object('passed',true,'closed',v_count>=2);
end $$;

grant execute on function public.create_auction_room(text,numeric,numeric,numeric) to authenticated;
grant execute on function public.join_auction_room(text,text,numeric,numeric) to authenticated;
grant execute on function public.get_my_private_limit() to authenticated;
grant execute on function public.set_my_private_limit(numeric) to authenticated;
grant execute on function public.open_auction_lot(text,text,numeric) to authenticated;
grant execute on function public.place_auction_bid(numeric) to authenticated;
grant execute on function public.pass_auction_lot() to authenticated;

-- Realtime para atualizações instantâneas no navegador.
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.participants;
alter publication supabase_realtime add table public.auction_lots;
alter publication supabase_realtime add table public.bids;
alter publication supabase_realtime add table public.roster;
