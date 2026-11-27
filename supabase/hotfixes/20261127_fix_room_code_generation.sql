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

  v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
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

grant execute on function public.create_auction_room(text,numeric,numeric,numeric) to authenticated;
