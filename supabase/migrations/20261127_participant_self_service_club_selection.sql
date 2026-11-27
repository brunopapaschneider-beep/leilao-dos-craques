-- Permite que cada participante escolha/atualize somente o próprio clube dentro da sala.
create or replace function public.set_my_club_for_participant(
  p_participant_id uuid,
  p_club_name text,
  p_club_wiki_title text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;

  if nullif(trim(p_club_name), '') is null
     or nullif(trim(p_club_wiki_title), '') is null then
    raise exception 'Escolha um clube ou a Seleção Brasileira.';
  end if;

  update public.participants
  set club_name = trim(p_club_name),
      club_wiki_title = trim(p_club_wiki_title)
  where id = p_participant_id
    and user_id = auth.uid();

  if not found then
    raise exception 'Participante não encontrado ou não pertence a este usuário.';
  end if;

  return jsonb_build_object(
    'club_name', trim(p_club_name),
    'club_wiki_title', trim(p_club_wiki_title)
  );
end;
$$;

grant execute on function public.set_my_club_for_participant(uuid, text, text) to authenticated;
