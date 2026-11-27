-- LEILÃO DOS CRAQUES — sincronização do resultado da partida
-- Execute no Supabase SQL Editor do projeto da sala.

alter table public.rooms
  add column if not exists match_result jsonb;

create or replace function public.save_room_match_result(p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
  v_room public.rooms;
begin
  if auth.uid() is null then
    raise exception 'Faça login para registrar a partida.';
  end if;

  select *
    into v_part
    from public.participants
   where user_id = auth.uid()
   order by created_at desc
   limit 1;

  if not found then
    raise exception 'Participante não encontrado.';
  end if;

  if not v_part.is_host then
    raise exception 'Somente o organizador pode registrar o resultado.';
  end if;

  if p_result is null
     or jsonb_typeof(p_result) <> 'object'
     or not (p_result ? 'teams')
     or not (p_result ? 'home')
     or not (p_result ? 'away')
     or not (p_result ? 'events')
     or not (p_result ? 'winner') then
    raise exception 'Resultado da partida inválido.';
  end if;

  select *
    into v_room
    from public.rooms
   where id = v_part.room_id
   for update;

  if not found then
    raise exception 'Sala não encontrada.';
  end if;

  -- Idempotência: se já existe resultado, devolve o oficial sem sortear outro.
  if v_room.match_result is not null then
    return v_room.match_result;
  end if;

  update public.rooms
     set match_result = p_result
   where id = v_room.id;

  return p_result;
end;
$$;

revoke all on function public.save_room_match_result(jsonb) from public;
grant execute on function public.save_room_match_result(jsonb) to authenticated;

notify pgrst, 'reload schema';
