-- Permite que cada participante escolha seu próprio incremento por lance.
create or replace function public.place_auction_bid(p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_part public.participants; v_lot public.auction_lots; v_min numeric;
begin
  select * into v_part from public.participants where user_id=auth.uid() order by created_at desc limit 1 for update;
  if not found then raise exception 'Participante não encontrado.'; end if;
  select * into v_lot from public.auction_lots where room_id=v_part.room_id and status='open' order by created_at desc limit 1 for update;
  if not found then raise exception 'Não há lote aberto.'; end if;
  if v_lot.current_winner=v_part.id then raise exception 'Você já possui o maior lance.'; end if;
  v_min := case when v_lot.current_winner is null then v_lot.starting_bid else v_lot.current_bid + 0.01 end;
  if p_amount < v_min then raise exception 'O lance precisa superar o maior lance atual. Mínimo: %',v_min; end if;
  if p_amount > v_part.max_bid then raise exception 'Seu valor máximo privado foi atingido.'; end if;
  if p_amount > (v_part.budget-v_part.spent) then raise exception 'Saldo insuficiente.'; end if;
  update public.auction_lots set current_bid=p_amount,current_winner=v_part.id where id=v_lot.id;
  insert into public.bids(lot_id,participant_id,amount) values(v_lot.id,v_part.id,p_amount);
  update public.participants set passed_lot_id=null where id=v_part.id;
  return jsonb_build_object('accepted',true,'amount',p_amount);
end; $$;
grant execute on function public.place_auction_bid(numeric) to authenticated;