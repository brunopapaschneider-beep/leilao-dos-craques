-- LEILÃO DOS CRAQUES — partidas em tempo real, técnicos, substituições e séries
alter table public.rooms
  add column if not exists match_result jsonb,
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
     or jsonb_typeof(p_state->'teams') <> 'object'
     or not ((p_state->'teams') ? v_left_id)
     or not ((p_state->'teams') ? v_right_id) then
    raise exception 'Configuração inicial da partida inválida.';
  end if;

  update public.rooms
     set match_state = jsonb_set(
           jsonb_set(p_state, '{series}', coalesce(v_series,'null'::jsonb), true),
           '{ready}', jsonb_build_object(v_left_id,false,v_right_id,false), true
         ),
         match_result = null,
         match_series = v_series
   where id = v_room.id;

  return jsonb_set(
    jsonb_set(p_state, '{series}', coalesce(v_series,'null'::jsonb), true),
    '{ready}', jsonb_build_object(v_left_id,false,v_right_id,false), true
  );
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
  if p_team is null or jsonb_typeof(p_team) <> 'object' then
    raise exception 'Equipe inválida.';
  end if;
  if jsonb_typeof(p_team->'starters') <> 'array' or jsonb_typeof(p_team->'bench') <> 'array' then
    raise exception 'Escalação inválida.';
  end if;
  if jsonb_array_length(p_team->'starters') <> 11
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
  v_state := jsonb_set(v_state, array['ready',p_team_id::text], 'false'::jsonb, true);
  update public.rooms set match_state=v_state where id=v_room.id;
  return v_state;
end;
$$;

create or replace function public.match_team_strength(p_team jsonb)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_avg numeric;
  v_bench numeric;
  v_fatigue numeric;
  v_attack numeric := 1;
  v_defense numeric := 1;
  v_coach_attack numeric;
  v_coach_defense numeric;
  v_coach_control numeric;
  v_formation numeric := 1;
begin
  select coalesce(avg(coalesce((x.player->>'rating')::numeric,75)),75),
         coalesce(avg(coalesce((x.player->>'fatigue')::numeric,0)),0)
    into v_avg,v_fatigue
    from jsonb_array_elements(coalesce(p_team->'starters','[]'::jsonb)) as x(player);
  select coalesce(avg(coalesce((x.player->>'rating')::numeric,75)),75)
    into v_bench
    from jsonb_array_elements(coalesce(p_team->'bench','[]'::jsonb)) as x(player);

  case coalesce(p_team->>'tactic','equilibrado')
    when 'ofensivo' then v_attack:=1.09; v_defense:=0.94;
    when 'defensivo' then v_attack:=0.94; v_defense:=1.10;
    when 'contra' then v_attack:=1.07; v_defense:=1.04;
    when 'posse' then v_attack:=1.04; v_defense:=1.02;
    else v_attack:=1; v_defense:=1;
  end case;

  v_coach_attack:=coalesce((p_team->'coach'->>'attack')::numeric,1);
  v_coach_defense:=coalesce((p_team->'coach'->>'defense')::numeric,1);
  v_coach_control:=coalesce((p_team->'coach'->>'control')::numeric,1);
  case coalesce(p_team->>'formation','4-4-2')
    when '4-3-3' then v_formation:=1.015;
    when '3-5-2' then v_formation:=1.010;
    when '4-2-3-1' then v_formation:=1.012;
    else v_formation:=1;
  end case;

  return (
    v_avg*v_attack*v_coach_attack*(1-v_fatigue*0.0028)*0.68
    + v_avg*v_defense*v_coach_defense*(1-v_fatigue*0.0022)*0.20
    + v_bench*0.12
  ) * v_formation * v_coach_control;
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
  v_left_id text;
  v_right_id text;
  v_left_name text;
  v_right_name text;
  v_left_team jsonb;
  v_right_team jsonb;
  v_teams jsonb;
  v_left_starters jsonb;
  v_right_starters jsonb;
  v_left_strength numeric;
  v_right_strength numeric;
  v_left_avg numeric;
  v_right_avg numeric;
  v_left_lambda numeric;
  v_right_lambda numeric;
  v_left_goals integer := 0;
  v_right_goals integer := 0;
  v_score jsonb;
  v_events jsonb;
  v_names text[];
  v_player text;
  v_event_minute integer;
  v_i integer;
  v_next_state jsonb;
  v_result jsonb;
  v_history jsonb;
  v_series jsonb;
  v_wins jsonb;
  v_winner text;
  v_winner_id text;
  v_game integer;
begin
  if auth.uid() is null then raise exception 'Faça login para avançar a partida.'; end if;
  select * into v_part from public.participants
   where user_id=auth.uid() order by created_at desc limit 1;
  if not found or not v_part.is_host then raise exception 'Somente o organizador pode avançar a partida.'; end if;

  select * into v_room from public.rooms where id=v_part.room_id for update;
  v_old:=v_room.match_state;
  if v_old is null or coalesce(v_old->>'status','')<>'live'
     or coalesce((v_old->>'paused')::boolean,false) is not true then
    raise exception 'A partida não está em uma pausa válida.';
  end if;

  select id::text,display_name into v_left_id,v_left_name
    from public.participants where room_id=v_part.room_id order by created_at limit 1;
  select id::text,display_name into v_right_id,v_right_name
    from public.participants where room_id=v_part.room_id order by created_at desc limit 1;

  if coalesce((v_old->'ready'->>v_left_id)::boolean,false) is not true
     or coalesce((v_old->'ready'->>v_right_id)::boolean,false) is not true then
    raise exception 'Os dois participantes precisam confirmar PRONTO antes de avançar.';
  end if;

  v_new_minute:=coalesce((v_old->>'minute')::integer,0)+15;
  if coalesce((p_state->>'minute')::integer,-1)<>v_new_minute then
    raise exception 'A partida deve avançar exatamente 15 minutos.';
  end if;
  if v_new_minute>90 then raise exception 'A partida já chegou ao fim.'; end if;

  v_left_team:=v_old->'teams'->v_left_id;
  v_right_team:=v_old->'teams'->v_right_id;
  if v_left_team is null or v_right_team is null then raise exception 'Escalações não encontradas.'; end if;

  -- O servidor calcula o desempenho e sorteia os gols uma única vez por bloco.
  v_left_strength:=public.match_team_strength(v_left_team);
  v_right_strength:=public.match_team_strength(v_right_team);
  select coalesce(avg(coalesce((x.player->>'rating')::numeric,75)),75)
    into v_left_avg from jsonb_array_elements(v_left_team->'starters') as x(player);
  select coalesce(avg(coalesce((x.player->>'rating')::numeric,75)),75)
    into v_right_avg from jsonb_array_elements(v_right_team->'starters') as x(player);
  v_left_lambda:=greatest(0.07,least(0.72,0.23+(v_left_strength-v_right_avg)/115));
  v_right_lambda:=greatest(0.07,least(0.72,0.23+(v_right_strength-v_left_avg)/115);

  for v_i in 1..3 loop
    if random()<v_left_lambda then v_left_goals:=v_left_goals+1; end if;
    if random()<v_right_lambda then v_right_goals:=v_right_goals+1; end if;
  end loop;

  v_events:=coalesce(v_old->'events','[]'::jsonb);
  select array_agg(coalesce(x.player->>'player_name','Gol'))
    into v_names from jsonb_array_elements(v_left_team->'starters') as x(player)
   where x.player->>'position' in ('Atacante','Meio-campo','Volante');
  if coalesce(array_length(v_names,1),0)=0 then v_names:=array['Gol']; end if;
  for v_i in 1..v_left_goals loop
    v_player:=v_names[1+floor(random()*array_length(v_names,1))::integer];
    v_event_minute:=coalesce((v_old->>'minute')::integer,0)+1+floor(random()*15)::integer;
    v_events:=v_events||jsonb_build_array(jsonb_build_object('team',v_left_name,'participant_id',v_left_id,'player',v_player,'minute',v_event_minute,'type','goal'));
  end loop;

  select array_agg(coalesce(x.player->>'player_name','Gol'))
    into v_names from jsonb_array_elements(v_right_team->'starters') as x(player)
   where x.player->>'position' in ('Atacante','Meio-campo','Volante');
  if coalesce(array_length(v_names,1),0)=0 then v_names:=array['Gol']; end if;
  for v_i in 1..v_right_goals loop
    v_player:=v_names[1+floor(random()*array_length(v_names,1))::integer];
    v_event_minute:=coalesce((v_old->>'minute')::integer,0)+1+floor(random()*15)::integer;
    v_events:=v_events||jsonb_build_array(jsonb_build_object('team',v_right_name,'participant_id',v_right_id,'player',v_player,'minute',v_event_minute,'type','goal'));
  end loop;

  select coalesce(jsonb_agg(jsonb_set(x.player,'{fatigue}',to_jsonb(least(100,coalesce((x.player->>'fatigue')::numeric,0)+9)),true)),'[]'::jsonb)
    into v_left_starters from jsonb_array_elements(v_left_team->'starters') as x(player);
  select coalesce(jsonb_agg(jsonb_set(x.player,'{fatigue}',to_jsonb(least(100,coalesce((x.player->>'fatigue')::numeric,0)+9)),true)),'[]'::jsonb)
    into v_right_starters from jsonb_array_elements(v_right_team->'starters') as x(player);
  v_left_team:=jsonb_set(v_left_team,'{starters}',v_left_starters,true);
  v_right_team:=jsonb_set(v_right_team,'{starters}',v_right_starters,true);
  v_teams:=jsonb_set(jsonb_set(v_old->'teams',array[v_left_id],v_left_team,true),array[v_right_id],v_right_team,true);

  v_score:=coalesce(v_old->'score','{}'::jsonb);
  v_score:=jsonb_set(v_score,array[v_left_id],to_jsonb(coalesce((v_score->>v_left_id)::integer,0)+v_left_goals),true);
  v_score:=jsonb_set(v_score,array[v_right_id],to_jsonb(coalesce((v_score->>v_right_id)::integer,0)+v_right_goals),true);
  v_next_state:=jsonb_set(v_old,'{teams}',v_teams,true);
  v_next_state:=jsonb_set(v_next_state,'{score}',v_score,true);
  v_next_state:=jsonb_set(v_next_state,'{events}',v_events,true);
  v_next_state:=jsonb_set(v_next_state,'{minute}',to_jsonb(v_new_minute),true);
  v_next_state:=jsonb_set(v_next_state,'{status}',to_jsonb(case when v_new_minute=90 then 'finished' else 'live' end),true);
  v_next_state:=jsonb_set(v_next_state,'{ready}',jsonb_build_object(v_left_id,false,v_right_id,false),true);

  if v_new_minute=90 then
    v_winner_id:=case when coalesce((v_score->>v_left_id)::integer,0)=coalesce((v_score->>v_right_id)::integer,0) then null
      when (v_score->>v_left_id)::integer>(v_score->>v_right_id)::integer then v_left_id else v_right_id end;
    v_winner:=case when v_winner_id is null then 'Empate' when v_winner_id=v_left_id then v_left_name else v_right_name end;
    v_series:=v_room.match_series;
    v_result:=jsonb_build_object(
      'match_id',v_old->>'match_id','played_at',now(),'teams',v_teams,
      'home',jsonb_build_object('goals',(v_score->>v_left_id)::integer,'avg',round(v_left_avg),'strength',round(v_left_strength)),
      'away',jsonb_build_object('goals',(v_score->>v_right_id)::integer,'avg',round(v_right_avg),'strength',round(v_right_strength)),
      'events',v_events,'winner',v_winner,'winner_id',v_winner_id,
      'series_id',case when coalesce((v_series->>'active')::boolean,false) then v_series->>'id' else null end
    );
    v_next_state:=jsonb_set(v_next_state,'{result}',v_result,true);
    v_next_state:=jsonb_set(v_next_state,'{series}',coalesce(v_series,'null'::jsonb),true);
    v_history:=coalesce(v_room.match_history,'[]'::jsonb)||jsonb_build_array(v_result);

    if coalesce((v_series->>'active')::boolean,false) then
      v_wins:=coalesce(v_series->'wins','{}'::jsonb);
      if v_winner_id is not null then
        v_wins:=jsonb_set(v_wins,array[v_winner_id],to_jsonb(coalesce((v_wins->>v_winner_id)::integer,0)+1),true);
      end if;
      v_game:=coalesce((v_series->>'game')::integer,1)+1;
      v_series:=jsonb_set(jsonb_set(v_series,'{wins}',v_wins,true),'{game}',to_jsonb(v_game),true);
      if coalesce((v_wins->>(v_series->'participants'->>0))::integer,0)>=2
         or coalesce((v_wins->>(v_series->'participants'->>1))::integer,0)>=2
         or v_game>3 then
        v_series:=jsonb_set(v_series,'{active}','false'::jsonb,true);
      end if;
    end if;
    v_next_state:=jsonb_set(v_next_state,'{series}',coalesce(v_series,'null'::jsonb),true);
    update public.rooms set match_state=v_next_state,match_result=v_result,match_history=v_history,match_series=v_series where id=v_room.id;
    return v_next_state;
  end if;

  update public.rooms set match_state=v_next_state where id=v_room.id;
  return v_next_state;
end;
$$;

create or replace function public.set_room_match_ready(p_ready boolean)
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
  if auth.uid() is null then raise exception 'Faça login para confirmar presença.'; end if;
  select * into v_part from public.participants where user_id=auth.uid() order by created_at desc limit 1;
  if not found then raise exception 'Participante não encontrado.'; end if;
  select * into v_room from public.rooms where id=v_part.room_id for update;
  v_state := v_room.match_state;
  if v_state is null or coalesce(v_state->>'status','') <> 'live'
     or coalesce((v_state->>'paused')::boolean,false) is not true then
    raise exception 'A confirmação só pode ser feita durante uma pausa.';
  end if;
  v_state := jsonb_set(v_state,array['ready',v_part.id::text],to_jsonb(p_ready),true);
  update public.rooms set match_state=v_state where id=v_room.id;
  return v_state;
end;
$$;

revoke all on function public.start_room_match(jsonb,boolean) from public;
revoke all on function public.update_room_match_team(uuid,jsonb) from public;
revoke all on function public.advance_room_match(jsonb) from public;
revoke all on function public.set_room_match_ready(boolean) from public;
grant execute on function public.start_room_match(jsonb,boolean) to authenticated;
grant execute on function public.update_room_match_team(uuid,jsonb) to authenticated;
grant execute on function public.advance_room_match(jsonb) to authenticated;
grant execute on function public.set_room_match_ready(boolean) to authenticated;
notify pgrst, 'reload schema';
