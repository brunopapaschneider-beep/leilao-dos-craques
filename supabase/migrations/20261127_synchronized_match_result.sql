-- Resultado unico e sincronizado da partida por sala.
alter table public.rooms
  add column if not exists match_result jsonb;

create or replace function public.save_room_match_result(p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_part public.participants;
  v_result jsonb;
begin
  select * into v_part
  from public.participants
  where user_id = auth.uid()
    and is_host = true
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Somente o organizador pode iniciar a partida.';
  end if;

  if (select count(*) from public.participants where room_id = v_part.room_id) <> 2 then
    raise exception 'A sala precisa ter exatamente dois participantes.';
  end if;

  if exists (
    select 1 from public.participants p
    where p.room_id = v_part.room_id
      and (select count(*) from public.roster r where r.participant_id = p.id) <> 23
  ) then
    raise exception 'Os dois elencos precisam estar completos com 23 jogadores.';
  end if;

  select match_result into v_result
  from public.rooms
  where id = v_part.room_id
  for update;

  if v_result is not null then
    return v_result;
  end if;

  if p_result is null or jsonb_typeof(p_result) <> 'object' then
    raise exception 'Resultado de partida inválido.';
  end if;

  update public.rooms
  set match_result = p_result
  where id = v_part.room_id
  returning match_result into v_result;

  return v_result;
end;
$$;

grant execute on function public.save_room_match_result(jsonb) to authenticated;
