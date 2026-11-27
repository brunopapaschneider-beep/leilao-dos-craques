-- Permite que participantes da sala leiam os dados públicos do escudo escolhido.
-- O teto max_bid continua sem SELECT direto.
grant select (
  id, room_id, user_id, display_name, is_host,
  budget, spent, passed_lot_id, connected, created_at,
  club_name, club_wiki_title
) on public.participants to authenticated;
