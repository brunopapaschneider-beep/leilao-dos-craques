-- Orçamento escolhido na criação da sala e compartilhado pelos dois participantes.
alter table public.rooms
  add column if not exists budget numeric(12,2);

update public.rooms r
set budget = coalesce(
  (select p.budget from public.participants p where p.room_id = r.id and p.is_host order by p.created_at limit 1),
  150
)
where r.budget is null;

alter table public.rooms
  alter column budget set default 150,
  alter column budget set not null;

alter table public.rooms
  add constraint rooms_budget_allowed
  check (budget in (150, 200, 250, 1000));

create or replace function public.create_auction_room(
  p_name text, p_budget numeric, p_increment numeric, p_player_limit numeric
)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_room public.rooms; v_part public.participants; v_code text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if length(trim(p_name)) < 2
     or p_budget not in (150,200,250,1000)
     or p_increment <= 0
     or p_player_limit <= 0
     or p_player_limit > p_budget then
    raise exception 'Dados inválidos: confira nome, orçamento e teto individual.';
  end if;

  v_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,6));
  insert into public.rooms(room_code,host_user_id,increment,budget)
  values(v_code,auth.uid(),p_increment,p_budget)
  returning * into v_room;

  insert into public.participants(room_id,user_id,display_name,is_host,budget,max_bid)
  values(v_room.id,auth.uid(),trim(p_name),true,p_budget,p_player_limit)
  returning * into v_part;

  return jsonb_build_object(
    'room_id',v_room.id,'room_code',v_code,'participant_id',v_part.id,
    'budget',p_budget
  );
end;
$$;

create or replace function public.join_auction_room(
  p_code text, p_name text, p_budget numeric, p_limit numeric
)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_room public.rooms; v_part public.participants;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;

  select * into v_room
  from public.rooms
  where room_code=upper(trim(p_code)) and status='waiting'
  for update;

  if not found then raise exception 'Sala não encontrada ou já iniciada.'; end if;
  if (select count(*) from public.participants where room_id=v_room.id) >= 2 then
    raise exception 'Sala cheia.';
  end if;
  if length(trim(p_name)) < 2 or p_limit <= 0 or p_limit > v_room.budget then
    raise exception 'Dados inválidos: confira nome e teto individual.';
  end if;

  insert into public.participants(room_id,user_id,display_name,budget,max_bid)
  values(v_room.id,auth.uid(),trim(p_name),v_room.budget,p_limit)
  returning * into v_part;

  return jsonb_build_object(
    'room_id',v_room.id,'participant_id',v_part.id,'budget',v_room.budget
  );
end;
$$;

grant execute on function public.create_auction_room(text,numeric,numeric,numeric) to authenticated;
grant execute on function public.join_auction_room(text,text,numeric,numeric) to authenticated;
