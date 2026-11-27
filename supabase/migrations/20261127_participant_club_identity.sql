-- Identidade visual dos participantes: clube brasileiro ou Seleção Brasileira
alter table public.participants
  add column if not exists club_name text,
  add column if not exists club_wiki_title text;

create or replace function public.set_my_club(p_club_name text, p_club_wiki_title text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.participants;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  if nullif(trim(p_club_name), '') is null or nullif(trim(p_club_wiki_title), '') is null then
    raise exception 'Escolha um clube ou a Seleção Brasileira.';
  end if;

  select * into v_part
  from public.participants
  where user_id = auth.uid()
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Participante não encontrado.';
  end if;

  update public.participants
  set club_name = trim(p_club_name),
      club_wiki_title = trim(p_club_wiki_title)
  where id = v_part.id;

  return jsonb_build_object('club_name', trim(p_club_name), 'club_wiki_title', trim(p_club_wiki_title));
end;
$$;

grant execute on function public.set_my_club(text, text) to authenticated;
