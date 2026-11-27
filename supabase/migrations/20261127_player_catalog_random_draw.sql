-- Leilao dos Craques: catalogo de jogadores e sorteio automatico
-- Execute uma unica vez no SQL Editor do Supabase.

create table if not exists public.player_catalog (
  id text primary key,
  player_name text not null,
  position text not null check (position in ('Goleiro','Lateral-direito','Zagueiro','Lateral-esquerdo','Volante','Meio-campo','Atacante')),
  nationality text not null,
  wiki_title text not null,
  rating integer not null check (rating between 1 and 100),
  is_superstar boolean not null default false,
  active boolean not null default true
);

alter table public.auction_lots
  add column if not exists player_id text references public.player_catalog(id),
  add column if not exists nationality text,
  add column if not exists wiki_title text,
  add column if not exists rating integer,
  add column if not exists is_superstar boolean not null default false;

alter table public.player_catalog enable row level security;
drop policy if exists "authenticated read player catalog" on public.player_catalog;
create policy "authenticated read player catalog" on public.player_catalog for select to authenticated using (true);
grant select on public.player_catalog to authenticated;

insert into public.player_catalog (id,player_name,position,nationality,wiki_title,rating,is_superstar) values
('gk-buffon','Gianluigi Buffon','Goleiro','Itália','Gianluigi Buffon',98,true),
('gk-casillas','Iker Casillas','Goleiro','Espanha','Iker Casillas',97,true),
('gk-neuer','Manuel Neuer','Goleiro','Alemanha','Manuel Neuer',98,true),
('gk-dida','Dida','Goleiro','Brasil','Dida (footballer)',94,false),
('gk-ceni','Rogério Ceni','Goleiro','Brasil','Rogério Ceni',94,false),
('gk-alisson','Alisson Becker','Goleiro','Brasil','Alisson Becker',94,false),
('gk-cech','Petr Čech','Goleiro','República Tcheca','Petr Čech',96,false),
('gk-van-der-sar','Edwin van der Sar','Goleiro','Países Baixos','Edwin van der Sar',95,false),
('rb-cafu','Cafu','Lateral-direito','Brasil','Cafu',99,true),
('rb-dani-alves','Dani Alves','Lateral-direito','Brasil','Dani Alves',96,false),
('rb-lahm','Philipp Lahm','Lateral-direito','Alemanha','Philipp Lahm',97,true),
('rb-zanetti','Javier Zanetti','Lateral-direito','Argentina','Javier Zanetti',96,false),
('rb-maicon','Maicon','Lateral-direito','Brasil','Maicon (footballer, born 1981)',94,false),
('rb-ronaldinho','Carlos Alberto Torres','Lateral-direito','Brasil','Carlos Alberto Torres',94,false),
('rb-reece','Trent Alexander-Arnold','Lateral-direito','Inglaterra','Trent Alexander-Arnold',93,false),
('cb-maldini','Paolo Maldini','Zagueiro','Itália','Paolo Maldini',100,true),
('cb-beckenbauer','Franz Beckenbauer','Zagueiro','Alemanha','Franz Beckenbauer',100,true),
('cb-baresi','Franco Baresi','Zagueiro','Itália','Franco Baresi',98,false),
('cb-ramos','Sergio Ramos','Zagueiro','Espanha','Sergio Ramos',97,false),
('cb-thiago-silva','Thiago Silva','Zagueiro','Brasil','Thiago Silva',95,false),
('cb- nesta','Alessandro Nesta','Zagueiro','Itália','Alessandro Nesta',97,false),
('cb-vidic','Nemanja Vidić','Zagueiro','Sérvia','Nemanja Vidić',94,false),
('cb-van-dijk','Virgil van Dijk','Zagueiro','Países Baixos','Virgil van Dijk',96,false),
('cb-lucio','Lúcio','Zagueiro','Brasil','Lúcio (footballer, born 1978)',94,false),
('lb-roberto-carlos','Roberto Carlos','Lateral-esquerdo','Brasil','Roberto Carlos (footballer, born 1973)',99,true),
('lb-marcelo','Marcelo','Lateral-esquerdo','Brasil','Marcelo (footballer, born 1988)',96,false),
('lb-maldini','Paolo Maldini (LE)','Lateral-esquerdo','Itália','Paolo Maldini',99,false),
('lb-ashley-cole','Ashley Cole','Lateral-esquerdo','Inglaterra','Ashley Cole',95,false),
('lb-facchetti','Giacinto Facchetti','Lateral-esquerdo','Itália','Giacinto Facchetti',96,false),
('lb-alba','Jordi Alba','Lateral-esquerdo','Espanha','Jordi Alba',93,false),
('dm-makelele','Claude Makélélé','Volante','França','Claude Makélélé',96,false),
('dm-vieira','Patrick Vieira','Volante','França','Patrick Vieira',97,false),
('dm-busquets','Sergio Busquets','Volante','Espanha','Sergio Busquets',97,false),
('dm-casemiro','Casemiro','Volante','Brasil','Casemiro',94,false),
('dm-redondo','Fernando Redondo','Volante','Argentina','Fernando Redondo',96,false),
('dm-gattuso','Gennaro Gattuso','Volante','Itália','Gennaro Gattuso',92,false),
('am-zidane','Zinedine Zidane','Meio-campo','França','Zinedine Zidane',100,true),
('am-maradona','Diego Maradona','Meio-campo','Argentina','Diego Maradona',100,true),
('am-pele','Pelé','Meio-campo','Brasil','Pelé',100,true),
('am-ronaldinho','Ronaldinho Gaúcho','Meio-campo','Brasil','Ronaldinho',99,true),
('am-kaka','Kaká','Meio-campo','Brasil','Kaká',96,false),
('am-iniesta','Andrés Iniesta','Meio-campo','Espanha','Andrés Iniesta',99,true),
('am-xavi','Xavi','Meio-campo','Espanha','Xavi',98,false),
('am-modric','Luka Modrić','Meio-campo','Croácia','Luka Modrić',97,false),
('am-rivaldo','Rivaldo','Meio-campo','Brasil','Rivaldo',97,false),
('am-platini','Michel Platini','Meio-campo','França','Michel Platini',99,false),
('am-gerrard','Steven Gerrard','Meio-campo','Inglaterra','Steven Gerrard',95,false),
('am-lampard','Frank Lampard','Meio-campo','Inglaterra','Frank Lampard',94,false),
('fw-ronaldo','Ronaldo Nazário','Atacante','Brasil','Ronaldo (Brazilian footballer)',100,true),
('fw-messi','Lionel Messi','Atacante','Argentina','Lionel Messi',100,true),
('fw-cristiano','Cristiano Ronaldo','Atacante','Portugal','Cristiano Ronaldo',100,true),
('fw-romario','Romário','Atacante','Brasil','Romário',99,true),
('fw-van-basten','Marco van Basten','Atacante','Países Baixos','Marco van Basten',98,false),
('fw-henry','Thierry Henry','Atacante','França','Thierry Henry',98,false),
('fw-ronaldo-cr7','Eusébio','Atacante','Portugal','Eusébio',98,false),
('fw-batistuta','Gabriel Batistuta','Atacante','Argentina','Gabriel Batistuta',96,false),
('fw-neymar','Neymar','Atacante','Brasil','Neymar',98,false),
('fw-suarez','Luis Suárez','Atacante','Uruguai','Luis Suárez',97,false),
('fw-etoo','Samuel Eto’o','Atacante','Camarões','Samuel Eto''o',96,false),
('fw-lewandowski','Robert Lewandowski','Atacante','Polônia','Robert Lewandowski',98,false),
('fw-mbappe','Kylian Mbappé','Atacante','França','Kylian Mbappé',98,false)
on conflict (id) do update set
 player_name=excluded.player_name, position=excluded.position, nationality=excluded.nationality,
 wiki_title=excluded.wiki_title, rating=excluded.rating, is_superstar=excluded.is_superstar;

create or replace function public.open_random_auction_lot()
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_part public.participants;
  v_player public.player_catalog;
  v_lot public.auction_lots;
  v_required integer;
  v_owned integer;
begin
  select * into v_part from public.participants
  where user_id=auth.uid() and is_host order by created_at desc limit 1;
  if not found then raise exception 'Somente o organizador pode sortear o próximo jogador.'; end if;
  if (select count(*) from public.participants where room_id=v_part.room_id) < 2 then
    raise exception 'Aguardando o segundo participante.';
  end if;
  if exists(select 1 from public.auction_lots where room_id=v_part.room_id and status='open') then
    raise exception 'Já existe um jogador em disputa.';
  end if;

  select p.* into v_player
  from public.player_catalog p
  where p.active
    and not exists (
      select 1 from public.auction_lots l
      where l.room_id=v_part.room_id
        and (l.player_id=p.id or lower(l.player_name)=lower(p.player_name))
    )
    and (
      case p.position
        when 'Goleiro' then 2
        when 'Lateral-direito' then 2
        when 'Zagueiro' then 4
        when 'Lateral-esquerdo' then 2
        when 'Volante' then 2
        when 'Meio-campo' then 3
        when 'Atacante' then 3
      end
    ) > (
      select count(*) from public.roster r
      where r.room_id=v_part.room_id and r.position=p.position
    )
  order by random()
  limit 1;

  if not found then raise exception 'Não há mais jogadores disponíveis para as vagas restantes do elenco.'; end if;

  insert into public.auction_lots
    (room_id,player_id,player_name,position,nationality,wiki_title,rating,is_superstar,starting_bid,current_bid)
  values
    (v_part.room_id,v_player.id,v_player.player_name,v_player.position,v_player.nationality,
     v_player.wiki_title,v_player.rating,v_player.is_superstar,1,1)
  returning * into v_lot;

  update public.rooms set status='active' where id=v_part.room_id;
  return v_lot.id;
end;
$$;

grant execute on function public.open_random_auction_lot() to authenticated;
