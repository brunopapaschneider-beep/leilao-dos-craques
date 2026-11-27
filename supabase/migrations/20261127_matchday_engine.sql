-- LEILÃO DOS CRAQUES — partidas em tempo real, técnicos, substituições e séries
alter table public.rooms
  add column if not exists match_state jsonb,
  add column if not exists match_history jsonb not null default '[]'::jsonb,
  add column if not exists match_series jsonb;

create or replace function public.start_room_match(p_state jsonb, p_best_of_three boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
  v_room public.rooms;
  v_count integer;
  v_left_id text;
  v_right_id text;
  v_series jsonb;
  v_history jsonb;
  v_left_wins integer;
  v_right_wins integer;
begin
  if auth.uid() is null then raise exception 'Faça login para iniciar a partida.'; end if;
  select * into v_part from public.participants
   where user_id = auth.uid() order by created_at desc limit 1;
  if not found or not v_part.is_host then raise exception 'Somente o organizador pode iniciar a partida.'; end if;

  select * into v_room from public.rooms where id = v_part.room_id for update;
  if not found then raise exception 'Sala não encontrada.'; end if;
  if v_room.match_state is not null and coalesce(v_room.match_state->>'status','') <> 'finished'
     then raise exception 'Já existe uma partida em andamento.'; end if;

  select count(*) into v_count from public.participants where room_id = v_room.id;
  if v_count <> 2 then raise exception 'São necessários dois participantes.'; end if;
  if exists (
    select 1 from public.participants p
    where p.room_id = v_room.id
      and (select count(*) from public.roster r where r.participant_id = p.id) <> 23
  ) then raise exception 'Os dois elencos precisam estar completos com 23 jogadores.'; end if;

  v_history := coalesce(v_room.match_history, '[]'::jsonb);
  select id::text into v_left_id from public.participants where room_id=v_room.id order by created_at limit 1;
  select id::text into v_right_id from public.participants where room_id=v_room.id order by created_at desc limit 1;

  if p_best_of_three then
    if coalesce((v_room.match_series->>'active')::boolean,false) then
      v_series := v_room.match_series;
    else
      select count(*) into v_left_wins from jsonb_array_elements(v_history) as h(item)
       where h.item->>'winner_id'=v_left_id;
      select count(*) into v_right_wins from jsonb_array_elements(v_history) as h(item)
       where h.item->>'winner_id'=v_right_id;
      if v_left_wins < 1 or v_right_wins < 1 then
        raise exception 'A melhor de 3 só é liberada depois de uma vitória de cada participante.';
      end if;
      v_series := jsonb_build_object(
        'id', gen_random_uuid()::text, 'active', true, 'game', 1, 'wins', jsonb_build_object(v_left_id,0,v_right_id,0),
        'participants', jsonb_build_array(v_left_id,v_right_id)
      );
    end if;
  else
    v_series := null;
  end if;

  if p_state is null or jsonb_typeof(p_state) <> 'object'
     or coalesce(p_state->>'minute','') <> '0'
     or jsonb_typeof(p_state->'teams') <> 'object' then
    raise exception 'Configuração inicial da partida inválida.';
  end if;

  update public.rooms
     set match_state = jsonb_set(p_state, '{series}', coalesce(v_series,'null'::jsonb), true),
         match_result = null,
         match_series = v_series
   where id = v_room.id;

  return jsonb_set(p_state, '{series}', coalesce(v_series,'null'::jsonb), true);
end;
$$;

create or replace function public.update_room_match_team(p_team_id uuid, p_team jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
  v_room public.rooms;
  v_state jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login para alterar sua equipe.'; end if;
  select * into v_part from public.participants
   where user_id=auth.uid() order by created_at desc limit 1;
  if not found then raise exception 'Participante não encontrado.'; end if;
  if v_part.id <> p_team_id then raise exception 'Você só pode alterar o próprio time.'; end if;
  if jsonb_typeof(p_team) <> 'object'
     or jsonb_typeof(p_team->'starters') <> 'array'
     or jsonb_typeof(p_team->'bench') <> 'array'
     or jsonb_array_length(p_team->'starters') <> 11
     or coalesce((p_team->>'substitutions')::integer,0) > 5
     or coalesce((p_team->>'subWindows')::integer,0) > 3 then
    raise exception 'Escalação ou limite de substituições inválido.';
  end if;

  select * into v_room from public.rooms where id=v_part.room_id for update;
  v_state := v_room.match_state;
  if v_state is null or coalesce((v_state->>'paused')::boolean,false) is not true
     or coalesce(v_state->>'status','') <> 'live' then
    raise exception 'As alterações só podem ser feitas nas pausas da partida.';
  end if;

  v_state := jsonb_set(v_state, array['teams',p_team_id::text], p_team, true);
  update public.rooms set match_state=v_state where id=v_room.id;
  return v_state;
end;
$$;

create or replace function public.advance_room_match(p_state jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
  v_room public.rooms;
  v_old jsonb;
  v_new_minute integer;
  v_result jsonb;
  v_history jsonb;
  v_series jsonb;
  v_wins jsonb;
  v_winner text;
  v_game integer;
  v_left text;
  v_right text;
begin
  if auth.uid() is null then raise exception 'Faça login para avançar a partida.'; end if;
  select * into v_part from public.participants
   where user_id=auth.uid() order by created_at desc limit 1;
  if not found or not v_part.is_host then raise exception 'Somente o organizador pode avançar a partida.'; end if;
  select * into v_room from public.rooms where id=v_part.room_id for update;
  v_old := v_room.match_state;
  if v_old is null or coalesce(v_old->>'status','') <> 'live'
     or coalesce((v_old->>'paused')::boolean,false) is not true then
    raise exception 'A partida não está em uma pausa válida.';
  end if;
  v_new_minute := coalesce((v_old->>'minute')::integer,0) + 15;
  if coalesce((p_state->>'minute')::integer,-1) <> v_new_minute then
    raise exception 'A partida deve avançar exatamente 15 minutos.';
  end if;
  if v_new_minute > 90 then raise exception 'A partida já chegou ao fim.'; end if;

  if v_new_minute < 90 then
    update public.rooms set match_state=p_state where id=v_room.id;
    return p_state;
  end if;

  v_result := p_state->'result';
  if v_result is null or jsonb_typeof(v_result) <> 'object'
     or not (v_result ? 'home') or not (v_result ? 'away') or not (v_result ? 'winner_id') then
    raise exception 'Resultado final inválido.';
  end if;
  v_history := coalesce(v_room.match_history,'[]'::jsonb) || jsonb_build_array(v_result);
  v_series := v_room.match_series;
  if coalesce((v_series->>'active')::boolean,false) then
    v_wins := coalesce(v_series->'wins','{}'::jsonb);
    v_winner := nullif(v_result->>'winner_id','');
    if v_winner is not null then
      v_wins := jsonb_set(v_wins,array[v_winner],to_jsonb(coalesce((v_wins->>v_winner)::integer,0)+1),true);
    end if;
    v_game := coalesce((v_series->>'game')::integer,1)+1;
    v_series := jsonb_set(jsonb_set(v_series,'{wins}',v_wins,true),'{game}',to_jsonb(v_game),true);
    if coalesce((v_wins->> (v_series->'participants'->>0))::integer,0) >= 2
       or coalesce((v_wins->> (v_series->'participants'->>1))::integer,0) >= 2
       or v_game > 3 then
      v_series := jsonb_set(v_series,'{active}','false'::jsonb,true);
    end if;
  end if;

  update public.rooms
     set match_state=p_state,
         match_result=v_result,
         match_history=v_history,
         match_series=v_series
   where id=v_room.id;
  return p_state;
end;
$$;

revoke all on function public.start_room_match(jsonb,boolean) from public;
revoke all on function public.update_room_match_team(uuid,jsonb) from public;
revoke all on function public.advance_room_match(jsonb) from public;
grant execute on function public.start_room_match(jsonb,boolean) to authenticated;
grant execute on function public.update_room_match_team(uuid,jsonb) to authenticated;
grant execute on function public.advance_room_match(jsonb) to authenticated;
notify pgrst, 'reload schema';
