import React, { useEffect, useMemo, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { Gavel, Users, Wallet, ShieldCheck, Plus, Minus, Radio, Trophy, LogOut } from "lucide-react";

const url = import.meta.env.VITE_SUPABASE_URL;
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase = url && anon ? createClient(url, anon) : null;

const money = (n) => new Intl.NumberFormat("pt-BR", {style:"currency", currency:"BRL"}).format(Number(n || 0));
const errText = (e) => e?.message || "Não foi possível concluir a operação.";

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [room, setRoom] = useState(null);
  const [participants, setParticipants] = useState([]);
  const [lot, setLot] = useState(null);
  const [bids, setBids] = useState([]);
  const [roster, setRoster] = useState([]);
  const [name, setName] = useState("");
  const [roomCode, setRoomCode] = useState("");
  const [budget, setBudget] = useState("1000");
  const [limit, setLimit] = useState("250");
  const [increment, setIncrement] = useState("1");
  const [playerPhoto, setPlayerPhoto] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [myPrivate, setMyPrivate] = useState(null);

  const participant = useMemo(() => participants.find(p => p.id === profile?.participant_id), [participants, profile]);
  const isHost = participant?.is_host === true;
  const highest = bids.length ? bids[bids.length - 1] : null;
  const nextBid = lot ? (lot.current_winner ? Number(lot.current_bid) + Number(room?.increment || increment || 1) : Number(lot.starting_bid)) : 0;
  const myTop = highest?.participant_id === participant?.id;
  const mySpent = Number(participant?.spent || 0);
  const myBalance = Math.max(0, Number(participant?.budget || 0) - mySpent);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({data}) => setSession(data.session));
    const {data: sub} = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!supabase || !session) return;
    const saved = localStorage.getItem("ldc_profile");
    if (saved) {
      try {
        const p = JSON.parse(saved);
        setProfile(p);
        loadRoom(p.room_id, p.participant_id);
      } catch {}
    }
  }, [session]);

  async function signIn() {
    if (!supabase) return setMessage("Configure primeiro as variáveis do Supabase no arquivo .env.");
    setBusy(true); setMessage("");
    const {data, error} = await supabase.auth.signInAnonymously();
    setBusy(false);
    if (error) setMessage(errText(error)); else setSession(data.session);
  }

  async function loadRoom(roomId, participantId) {
    if (!supabase) return;
    const [r, ps, l, rs] = await Promise.all([
      supabase.from("rooms").select("*").eq("id", roomId).single(),
      supabase.from("participants").select("id,display_name,is_host,budget,spent,connected,created_at").eq("room_id", roomId).order("created_at"),
      supabase.from("auction_lots").select("*").eq("room_id", roomId).eq("status","open").maybeSingle(),
      supabase.from("roster").select("id,player_name,position,winning_bid,participant_id").eq("room_id", roomId)
    ]);
    if (r.error) { setMessage("Sala não encontrada ou sessão expirada."); return; }
    setRoom(r.data); setParticipants(ps.data || []); setLot(l.data || null); setRoster(rs.data || []);
    if (l.data) {
      const {data: bs} = await supabase.from("bids").select("id,lot_id,participant_id,amount,created_at").eq("lot_id", l.data.id).order("amount");
      setBids(bs || []);
    } else setBids([]);
    const {data: priv} = await supabase.rpc("get_my_private_limit");
    setMyPrivate(priv == null ? null : {max_bid:Number(priv)});
    if (priv != null) setLimit(String(priv));
  }

  useEffect(() => {
    if (!supabase || !profile?.room_id) return;
    const channel = supabase.channel(`room-${profile.room_id}`)
      .on("postgres_changes", {event:"*", schema:"public", table:"rooms", filter:`id=eq.${profile.room_id}`}, () => loadRoom(profile.room_id, profile.participant_id))
      .on("postgres_changes", {event:"*", schema:"public", table:"participants", filter:`room_id=eq.${profile.room_id}`}, () => loadRoom(profile.room_id, profile.participant_id))
      .on("postgres_changes", {event:"*", schema:"public", table:"auction_lots", filter:`room_id=eq.${profile.room_id}`}, () => loadRoom(profile.room_id, profile.participant_id))
      .on("postgres_changes", {event:"*", schema:"public", table:"roster", filter:`room_id=eq.${profile.room_id}`}, () => loadRoom(profile.room_id, profile.participant_id))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [profile?.room_id, profile?.participant_id]);

  useEffect(() => {
    if (!lot?.id) { setPlayerPhoto(""); return; }
    let cancelled = false;
    const title = lot.wiki_title || lot.player_name;
    fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`)
      .then(r => r.ok ? r.json() : Promise.reject(new Error("Imagem indisponível")))
      .then(data => { if (!cancelled) setPlayerPhoto(data?.thumbnail?.source || data?.originalimage?.source || ""); })
      .catch(() => { if (!cancelled) setPlayerPhoto(""); });
    return () => { cancelled = true; };
  }, [lot?.id, lot?.wiki_title, lot?.player_name]);

  useEffect(() => {
    if (!supabase || !lot?.id) return;
    const channel = supabase.channel(`lot-${lot.id}`)
      .on("postgres_changes", {event:"*", schema:"public", table:"bids", filter:`lot_id=eq.${lot.id}`}, () => loadRoom(profile.room_id, profile.participant_id))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [lot?.id]);

  async function runRpc(fn, args, onDone) {
    setBusy(true); setMessage("");
    const {data, error} = await supabase.rpc(fn, args);
    setBusy(false);
    if (error) setMessage(errText(error));
    else { if (onDone) onDone(data); if (profile) loadRoom(profile.room_id, profile.participant_id); }
    return {data, error};
  }

  async function createRoom() {
    if (!name.trim()) return setMessage("Informe seu nome.");
    const {data: auth} = await supabase.auth.getUser();
    const result = await runRpc("create_auction_room", {
      p_name: name.trim(), p_budget: Number(budget), p_increment: Number(increment),
      p_player_limit: Number(limit)
    }, (d) => {
      const p = {room_id:d.room_id, participant_id:d.participant_id, display_name:name.trim()};
      localStorage.setItem("ldc_profile", JSON.stringify(p)); setProfile(p);
      setRoomCode(d.room_code); loadRoom(d.room_id, d.participant_id);
    });
  }

  async function joinRoom() {
    if (!name.trim() || !roomCode.trim()) return setMessage("Informe seu nome e o código da sala.");
    const {data, error} = await runRpc("join_auction_room", {p_code:roomCode.trim().toUpperCase(), p_name:name.trim(), p_budget:Number(budget), p_limit:Number(limit)});
    if (!error) {
      const p = {room_id:data.room_id, participant_id:data.participant_id, display_name:name.trim()};
      localStorage.setItem("ldc_profile", JSON.stringify(p)); setProfile(p);
      await loadRoom(data.room_id, data.participant_id);
    }
  }

  async function setMyLimit() {
    const {data, error} = await runRpc("set_my_private_limit", {p_limit:Number(limit)});
    if (!error) { setMyPrivate({max_bid:Number(limit)}); setMessage("Seu limite privado foi atualizado."); }
  }

  async function openLot() {
    await runRpc("open_random_auction_lot", {});
  }

  async function bid() {
    await runRpc("place_auction_bid", {p_amount:nextBid});
  }

  async function pass() {
    await runRpc("pass_auction_lot", {});
  }

  async function logout() {
    localStorage.removeItem("ldc_profile");
    setProfile(null); setRoom(null); setParticipants([]); setLot(null); setBids([]); setRoster([]); setMyPrivate(null);
  }

  if (!supabase) return <main className="shell"><section className="hero"><div className="logo"><Gavel/></div><p className="eyebrow">JOGO MULTIPLAYER • TESTE PRIVADO</p><h1>LEILÃO DOS <em>CRAQUES</em></h1><p>O projeto está preparado. Falta conectar o banco de dados Supabase para ativar salas, autenticação e lances em tempo real.</p><div className="notice">Configure <code>VITE_SUPABASE_URL</code> e <code>VITE_SUPABASE_ANON_KEY</code> no arquivo <code>.env</code> e execute o SQL de <code>supabase/schema.sql</code>.</div></section></main>;

  if (!session) return <main className="shell"><section className="hero"><div className="logo"><Gavel/></div><p className="eyebrow">JOGO MULTIPLAYER • SALAS PRIVADAS</p><h1>LEILÃO DOS <em>CRAQUES</em></h1><p>Crie uma sala para jogar com Miguel ou entre usando o código recebido.</p><button className="primary" disabled={busy} onClick={signIn}>Entrar no jogo</button></section></main>;

  if (!profile || !room) return <main className="shell"><header className="top"><div className="brand"><Gavel/> LEILÃO DOS CRAQUES</div><span className="pill"><Radio size={14}/> Conexão segura</span></header><section className="join-grid"><article className="panel"><p className="eyebrow">IDENTIFICAÇÃO</p><h2>Quem vai jogar?</h2><label>Seu nome</label><input value={name} onChange={e=>setName(e.target.value)} placeholder="Ex.: Bruno ou Miguel"/><label>Orçamento inicial (R$)</label><input type="number" min="1" value={budget} onChange={e=>setBudget(e.target.value)}/><label>Seu limite máximo por jogador (R$)</label><input type="number" min="1" value={limit} onChange={e=>setLimit(e.target.value)}/><small>Esse limite é privado. O outro participante não consegue consultá-lo.</small></article><article className="panel"><p className="eyebrow">NOVA DISPUTA</p><h2>Criar sala</h2><p>Você será o administrador da sala e poderá abrir os jogadores para leilão.</p><button className="primary" disabled={busy} onClick={createRoom}><Plus size={17}/> Criar sala privada</button><div className="separator">OU ENTRE EM UMA SALA</div><label>Código de acesso</label><input value={roomCode} onChange={e=>setRoomCode(e.target.value.toUpperCase())} placeholder="Ex.: A7K9P2"/><button className="secondary" disabled={busy} onClick={joinRoom}>Entrar na sala</button></article></section>{message && <p className="message">{message}</p>}</main>;

  return <main className="shell">
    <header className="top"><div className="brand"><Gavel/> LEILÃO DOS CRAQUES</div><div className="top-right"><span className="pill"><Radio size={14}/> Ao vivo</span><button className="icon-button" onClick={logout} title="Sair"><LogOut size={17}/></button></div></header>
    <section className="room-banner"><div><p className="eyebrow">SALA PRIVADA</p><h2>Código: <strong>{room.room_code}</strong></h2><p>Compartilhe este código com o outro computador.</p></div><div className="room-stat"><Users/><b>{participants.length}/2</b><small>participantes</small></div></section>
    <section className="layout">
      <div className="main-col">
        <article className="auction panel">
          <div className="auction-head"><div className="player-heading"><p className="eyebrow">DISPUTA ATUAL</p><h2>{lot?.player_name || "Aguardando jogador"}</h2><p>{lot ? `${lot.position} • ${lot.nationality || "Craque internacional"} • ${lot.status === "open" ? "Leilão aberto" : lot.status}` : "O administrador pode sortear o próximo craque."}{lot?.rating ? ` • Nota ${lot.rating}/100` : ""}</p></div>{lot ? <div className="player-photo">{playerPhoto ? <img src={playerPhoto} alt={lot.player_name} /> : <div className="player-placeholder"><Trophy size={30}/><span>{lot.player_name.slice(0,1)}</span></div>}</div> : <div className="hammer"><Gavel/></div>}</div>
          {lot ? <>
            <div className="price">{money(lot.current_bid || lot.starting_bid)}</div>
            <div className="muted">Maior lance público</div>
            <div className="bid-actions"><button className="primary bid-button" disabled={busy || lot.status!=="open" || myTop || nextBid > Number(myPrivate?.max_bid ?? 0)} onClick={bid}>Dar lance de {money(nextBid)}</button><button className="secondary" disabled={busy || lot.status!=="open"} onClick={pass}>Passar</button></div>
            <div className="notice small"><ShieldCheck size={16}/> Seu teto é secreto e validado no banco de dados. O adversário vê apenas o maior lance.</div>
            <h3>Histórico de lances</h3><div className="bid-list">{bids.slice().reverse().map((b,i)=><div className="bid-row" key={b.id}><span>{participants.find(p=>p.id===b.participant_id)?.display_name || "Participante"}</span><b>{money(b.amount)}</b></div>)}{!bids.length && <small>Nenhum lance registrado.</small>}</div>
          </> : <div className="empty"><Trophy size={28}/><p>Quando o primeiro jogador for colocado em disputa, ele aparecerá aqui.</p></div>}
        </article>
        {isHost && <article className="panel draw-panel"><p className="eyebrow">CONTROLE DO LEILOEIRO</p><h3>Próximo lote automático</h3><p>O sistema sorteia um craque ainda não utilizado, priorizando as posições que faltam para completar a formação 4-4-2.</p><div className="draw-note"><Trophy size={18}/><span>Jogador, posição, nacionalidade e avaliação serão exibidos para os dois participantes.</span></div><button className="primary" disabled={busy || participants.length < 2 || !!lot} onClick={openLot}><Gavel size={17}/> Sortear próximo jogador</button></article>}
      </div>
      <aside className="side-col">
        <article className="panel"><p className="eyebrow">PARTICIPANTES</p>{participants.map(p=><div className="person" key={p.id}><div className="avatar">{p.display_name.slice(0,1).toUpperCase()}</div><div className="person-info"><b>{p.display_name}</b><small>{p.is_host?"Organizador":"Participante"}</small><small>Saldo: {money(Number(p.budget)-Number(p.spent))}</small></div><span className={`dot ${p.connected?"on":""}`}/></div>)}</article>
        <article className="panel"><p className="eyebrow">SEU CAIXA</p><div className="cash"><Wallet/><div><small>Orçamento inicial</small><b>{money(participant?.budget)}</b></div></div><div className="finance-grid"><div><small>Total investido</small><b>{money(mySpent)}</b></div><div><small>Saldo disponível</small><b className="balance">{money(myBalance)}</b></div></div><label>Seu teto secreto por jogador (R$)</label><input type="number" min="1" max={myBalance} value={limit} onChange={e=>setLimit(e.target.value)}/><button className="secondary full" disabled={busy} onClick={setMyLimit}>Atualizar meu limite privado</button><small>Limite atual: {money(myPrivate?.max_bid)} — visível somente nesta tela.</small></article>
        <article className="panel"><p className="eyebrow">ELENCO ARREMATADO</p>{roster.length ? roster.map(r=><div className="bid-row" key={r.id}><span>{r.player_name}<small>{r.position} • {participants.find(p=>p.id===r.participant_id)?.display_name || "Participante"}</small></span><b>{money(r.winning_bid)}</b></div>) : <small>Nenhum jogador arrematado ainda.</small>}</article>
      </aside>
    </section>
    {message && <p className="message">{message}</p>}
    <footer>Leilão dos Craques • Sala privada • Limites individuais e secretos</footer>
  </main>;
}