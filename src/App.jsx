import React, { useEffect, useMemo, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { Gavel, Users, Wallet, ShieldCheck, Plus, Minus, Radio, Trophy, LogOut } from "lucide-react";

const url = import.meta.env.VITE_SUPABASE_URL;
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase = url && anon ? createClient(url, anon) : null;

const money = (n) => new Intl.NumberFormat("pt-BR", {style:"currency", currency:"BRL"}).format(Number(n || 0));
const errText = (e) => e?.message || "Não foi possível concluir a operação.";

const CLUBS = [
{name:"Seleção Brasileira",wiki:"Seleção Brasileira de Futebol",group:"Seleção"},
{name:"Flamengo",wiki:"Clube de Regatas do Flamengo",group:"Série A"},
{name:"Palmeiras",wiki:"Sociedade Esportiva Palmeiras",group:"Série A"},
{name:"Corinthians",wiki:"Sport Club Corinthians Paulista",group:"Série A"},
{name:"São Paulo",wiki:"São Paulo Futebol Clube",group:"Série A"},
{name:"Santos",wiki:"Santos Futebol Clube",group:"Série A"},
{name:"Grêmio",wiki:"Grêmio Foot-Ball Porto Alegrense",group:"Série A"},
{name:"Internacional",wiki:"Sport Club Internacional",group:"Série A"},
{name:"Atlético-MG",wiki:"Clube Atlético Mineiro",group:"Série A"},
{name:"Cruzeiro",wiki:"Cruzeiro Esporte Clube",group:"Série A"},
{name:"Botafogo",wiki:"Botafogo de Futebol e Regatas",group:"Série A"},
{name:"Fluminense",wiki:"Fluminense Football Club",group:"Série A"},
{name:"Vasco",wiki:"Club de Regatas Vasco da Gama",group:"Série A"},
{name:"Bahia",wiki:"Esporte Clube Bahia",group:"Série A"},
{name:"Vitória",wiki:"Esporte Clube Vitória",group:"Série A"},
{name:"Athletico-PR",wiki:"Club Athletico Paranaense",group:"Série A/B"},
{name:"Fortaleza",wiki:"Fortaleza Esporte Clube",group:"Série A/B"},
{name:"Ceará",wiki:"Ceará Sporting Club",group:"Série A/B"},
{name:"Sport",wiki:"Sport Club do Recife",group:"Série A/B"},
{name:"Coritiba",wiki:"Coritiba Foot Ball Club",group:"Série A/B"},
{name:"Goiás",wiki:"Goiás Esporte Clube",group:"Tradicional"},
{name:"América-MG",wiki:"América Futebol Clube (Belo Horizonte)",group:"Tradicional"},
{name:"Chapecoense",wiki:"Associação Chapecoense de Futebol",group:"Tradicional"},
{name:"Criciúma",wiki:"Criciúma Esporte Clube",group:"Tradicional"},
{name:"Ponte Preta",wiki:"Associação Atlética Ponte Preta",group:"Tradicional"},
{name:"Guarani",wiki:"Guarani Futebol Clube",group:"Tradicional"},
{name:"Santa Cruz",wiki:"Santa Cruz Futebol Clube",group:"Tradicional"},
{name:"Náutico",wiki:"Clube Náutico Capibaribe",group:"Tradicional"},
{name:"Remo",wiki:"Clube do Remo",group:"Tradicional"},
{name:"Paysandu",wiki:"Paysandu Sport Club",group:"Tradicional"},
{name:"Vila Nova",wiki:"Vila Nova Futebol Clube",group:"Tradicional"},
{name:"ABC",wiki:"ABC Futebol Clube",group:"Tradicional"},
{name:"Figueirense",wiki:"Figueirense Futebol Clube",group:"Tradicional"}
];

const SORTED_CLUBS = [...CLUBS].sort((a,b) => a.name.localeCompare(b.name, "pt-BR", { sensitivity: "base" }));

function ClubBadge({wiki,name,large=false}) {
 const [src,setSrc]=useState("");
 useEffect(()=>{if(!wiki){setSrc("");return;}let cancelled=false;fetch(`https://pt.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(wiki)}`).then(r=>r.ok?r.json():Promise.reject()).then(d=>{if(!cancelled)setSrc(d?.thumbnail?.source||d?.originalimage?.source||"");}).catch(()=>{if(!cancelled)setSrc("");});return()=>{cancelled=true;};},[wiki]);
 return <span className={large?"club-badge club-badge-large":"club-badge"}>{src?<img src={src} alt={`Escudo de ${name}`}/>:<span>{name?.slice(0,2)?.toUpperCase()||"BR"}</span>}</span>;
}

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [room, setRoom] = useState(null);
  const [participants, setParticipants] = useState([]);
  const [lot, setLot] = useState(null);
  const [bids, setBids] = useState([]);
  const [roster, setRoster] = useState([]);
  const [name, setName] = useState("");
  const [clubName, setClubName] = useState("Seleção Brasileira");
  const [clubDraft, setClubDraft] = useState("Seleção Brasileira");
  const [roomCode, setRoomCode] = useState("");
  const [budget, setBudget] = useState("150");
  const [limit, setLimit] = useState("150");
  const [increment, setIncrement] = useState("1");
  const [manualBid, setManualBid] = useState("");
  const [playerPhoto, setPlayerPhoto] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [myPrivate, setMyPrivate] = useState(null);
  const [myProxy, setMyProxy] = useState(null);
  const [bidMode, setBidMode] = useState("automatic");

  const participant = useMemo(() => participants.find(p => p.id === profile?.participant_id), [participants, profile]);
  const isHost = participant?.is_host === true;
  const highest = bids.length ? bids[bids.length - 1] : null;
  const personalIncrement = Math.max(1, Math.trunc(Number(increment) || 1));
  const nextBid = lot ? (lot.current_winner ? Number(lot.current_bid) + (myProxy?.mode === "manual" ? 1 : personalIncrement) : Number(lot.starting_bid)) : 0;
  const chosenBid = manualBid === "" ? nextBid : Number(manualBid);
  const myTop = highest?.participant_id === participant?.id;
  const mySpent = Number(participant?.spent || 0);
  const myBalance = Math.max(0, Number(participant?.budget || 0) - mySpent);
  const rosterCounts = useMemo(() => participants.map(p => ({...p, rosterCount: roster.filter(r => r.participant_id === p.id).length, balance: Math.max(0, Number(p.budget || 0) - Number(p.spent || 0))})), [participants, roster]);
  const allBudgetsExhausted = participants.length === 2 && rosterCounts.every(p => p.balance <= 0);
  const oneRosterComplete = rosterCounts.some(p => p.rosterCount >= 23);
  const completionReady = !lot && rosterCounts.some(p => p.rosterCount < 23) && (allBudgetsExhausted || oneRosterComplete);

  useEffect(() => { if (participant?.club_name) setClubDraft(participant.club_name); }, [participant?.club_name]);

  // Sugere sempre o saldo disponível como teto inicial de cada novo lote.
  useEffect(() => {
    if (lot?.id && participant) setLimit(String(Math.max(0, Number(participant.budget || 0) - Number(participant.spent || 0))));
  }, [lot?.id, participant?.id, participant?.budget, participant?.spent]);

  useEffect(() => { setManualBid(lot ? String(lot.current_winner ? Number(lot.current_bid) + Math.max(1, Math.trunc(Number(increment) || 1)) : Number(lot.starting_bid)) : ""); }, [lot?.id, lot?.current_bid, lot?.current_winner, lot?.starting_bid, increment]);

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
      supabase.from("participants").select("id,display_name,is_host,budget,spent,connected,created_at,club_name,club_wiki_title").eq("room_id", roomId).order("created_at"),
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
    if (l.data) {
      const {data: proxy} = await supabase.rpc("get_my_lot_proxy_setting", {p_lot_id:l.data.id});
      setMyProxy(proxy?.configured ? {lot_id:l.data.id, mode:proxy.mode || "automatic", max_bid:proxy.max_bid == null ? null : Number(proxy.max_bid), increment:Number(proxy.increment)} : null);
      setBidMode(proxy?.mode || "automatic");
    } else { setMyProxy(null); setBidMode("automatic"); }
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
    let title = lot.wiki_title || lot.player_name;
    // Desambiguação explícita para o goleiro brasileiro Dida (Nélson de Jesus Silva).
    if (lot.player_name === "Dida") title = "Dida (footballer, born 1973)";
    // Imagem conferida manualmente: Roberto Carlos, ex-lateral da Seleção Brasileira.
    if (lot.player_name === "Roberto Carlos") {
      setPlayerPhoto("https://thumb.wikimedia.org/wikipedia/commons/thumb/8/82/Roberto_Carlos.JPG/500px-Roberto_Carlos.JPG");
      return () => {};
    }
    const lookup = async () => {
      const wikis = ["https://pt.wikipedia.org/w/api.php", "https://en.wikipedia.org/w/api.php"];
      const searchTitles = [title];
      for (const searchTitle of searchTitles) {
        for (const api of wikis) {
          try {
            const params = new URLSearchParams({
              action: "query", format: "json", formatversion: "2",
              prop: "pageimages", piprop: "thumbnail", pithumbsize: "600",
              redirects: "1", origin: "*", titles: searchTitle
            });
            const response = await fetch(`${api}?${params.toString()}`);
            if (!response.ok) continue;
            const data = await response.json();
            const image = data?.query?.pages?.[0]?.thumbnail?.source;
            if (image) { if (!cancelled) setPlayerPhoto(image); return; }
          } catch {}
        }
      }
      if (!cancelled) setPlayerPhoto("");
    };
    lookup();
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
    const selected = CLUBS.find(c=>c.name===clubName);
    if (!selected) return setMessage("Escolha seu clube ou a Seleção Brasileira.");
    setBusy(true); setMessage("");
    const {data,error} = await supabase.rpc("create_auction_room",{p_name:name.trim(),p_budget:Number(budget),p_increment:1,p_player_limit:Number(limit)});
    if(error){setBusy(false);return setMessage(errText(error));}
    const {error:clubError}=await supabase.rpc("set_my_club",{p_club_name:selected.name,p_club_wiki_title:selected.wiki});
    setBusy(false);
    if(clubError)return setMessage("Sala criada, mas não foi possível salvar o clube: "+errText(clubError));
    const p={room_id:data.room_id,participant_id:data.participant_id,display_name:name.trim()};
    localStorage.setItem("ldc_profile",JSON.stringify(p));setProfile(p);setRoomCode(data.room_code);
    await loadRoom(data.room_id,data.participant_id);
  }

  async function joinRoom() {
    if (!name.trim() || !roomCode.trim()) return setMessage("Informe seu nome e o código da sala.");
    const selected=CLUBS.find(c=>c.name===clubName);
    if(!selected)return setMessage("Escolha seu clube ou a Seleção Brasileira.");
    setBusy(true);setMessage("");
    const {data,error}=await supabase.rpc("join_auction_room",{p_code:roomCode.trim().toUpperCase(),p_name:name.trim(),p_budget:Number(budget),p_limit:Number(limit)});
    if(error){setBusy(false);return setMessage(errText(error));}
    const {error:clubError}=await supabase.rpc("set_my_club",{p_club_name:selected.name,p_club_wiki_title:selected.wiki});
    setBusy(false);
    if(clubError)return setMessage("Entrada realizada, mas não foi possível salvar o clube: "+errText(clubError));
    const p={room_id:data.room_id,participant_id:data.participant_id,display_name:name.trim()};
    localStorage.setItem("ldc_profile",JSON.stringify(p));setProfile(p);
    await loadRoom(data.room_id,data.participant_id);
  }

  async function saveMyClub() {
    const selected = CLUBS.find(c => c.name === clubDraft);
    if (!selected || !participant?.id) return setMessage("Escolha um clube válido.");
    const {error} = await supabase.rpc("set_my_club_for_participant", {p_participant_id: participant.id, p_club_name: selected.name, p_club_wiki_title: selected.wiki});
    if (error) return setMessage(errText(error));
    setMessage("Seu clube foi atualizado.");
    await loadRoom(profile.room_id, profile.participant_id);
  }

  async function setMyLimit() {
    if (myBalance <= 0) return setMessage("Seu saldo está zerado. Você não pode configurar lances.");
    if (!lot?.id) return setMessage("Não há jogador em disputa.");
    setBusy(true); setMessage("");
    const {data,error} = await supabase.rpc("save_lot_proxy", {
      p_lot_id: lot.id,
      p_max_bid: bidMode === "automatic" ? Number(limit) : null,
      p_increment: Number(increment),
      p_mode: bidMode
    });
    setBusy(false);
    if (error) return setMessage(errText(error));
    setMyPrivate(bidMode === "automatic" ? {max_bid:Number(limit)} : null);
    setMyProxy({lot_id:lot.id, mode:bidMode, max_bid:bidMode === "automatic" ? Number(limit) : null, increment:Number(increment)});
    if (data?.resolved && data?.covered) {
      setMessage(data.you_won ? "Disputa automática concluída: você venceu pelo menor valor necessário." : "O adversário venceu automaticamente pelo menor valor necessário.");
    } else if (data?.automatic_reply) {
      setMessage("Configuração salva. O lance automático respondeu à oferta manual.");
    } else if (bidMode === "manual") {
      setMessage("Modo manual ativado. Agora você decide quando e quanto ofertar.");
    } else {
      setMessage(data?.waiting_for_opponent ? "Modo automático salvo em sigilo. Aguardando a configuração do adversário." : "Configuração automática salva. O sistema responderá aos lances manuais dentro do seu limite.");
    }
    if (profile) await loadRoom(profile.room_id, profile.participant_id);
  }

  async function openLot() {
    if (allBudgetsExhausted) return setMessage("Os dois orçamentos foram encerrados. Use o preenchimento aleatório dos elencos.");
    await runRpc("open_random_auction_lot", {});
  }

  async function completeRostersRandomly() {
    if (!isHost || !completionReady || lot) return;
    await runRpc("fill_remaining_rosters_randomly", {});
  }

  async function bid() {
    if (myBalance <= 0) return setMessage("Seu saldo está zerado. Você não pode ofertar.");
    if (myProxy?.mode !== "manual" || myProxy?.lot_id !== lot?.id) return setMessage("Ative o modo manual neste jogador antes de ofertar.");
    if (!Number.isInteger(chosenBid) || chosenBid < nextBid) return setMessage(`Informe um lance inteiro a partir de ${money(nextBid)}.`);
    if (chosenBid > myBalance) return setMessage("Saldo insuficiente para esse lance.");
    await runRpc("place_auction_bid", {p_amount:chosenBid});
  }

  async function pass() {
    await runRpc("pass_auction_lot", {});
  }

  async function respondOverbid(action) {
    if (!lot?.id) return;
    const newMax = Number(limit);
    if (action === "automatic" && (!Number.isInteger(newMax) || newMax <= Number(lot.current_bid) || newMax > myBalance)) {
      return setMessage(`Informe um novo máximo inteiro, acima de ${money(lot.current_bid)} e dentro do seu saldo.`);
    }
    setBusy(true); setMessage("");
    const {data,error} = await supabase.rpc("respond_to_overbid", {
      p_action: action,
      p_new_max: action === "automatic" ? newMax : null
    });
    setBusy(false);
    if (error) return setMessage(errText(error));
    if (action === "decline") setMessage("Você declinou da disputa. O jogador foi arrematado pelo maior lance atual.");
    else if (action === "manual") {
      setBidMode("manual");
      setMyProxy({lot_id:lot.id,mode:"manual",max_bid:null,increment:Number(increment)});
      setMessage("Você decidiu continuar manualmente. Faça sua próxima oferta.");
    } else {
      setBidMode("automatic");
      setMyProxy({lot_id:lot.id,mode:"automatic",max_bid:newMax,increment:Number(increment)});
      setMessage("Novo limite automático salvo. Você voltou à disputa.");
    }
    if (profile) await loadRoom(profile.room_id,profile.participant_id);
  }

  async function logout() {
    localStorage.removeItem("ldc_profile");
    setProfile(null); setRoom(null); setParticipants([]); setLot(null); setBids([]); setRoster([]); setMyPrivate(null);
  }

  if (!supabase) return <main className="shell"><section className="hero"><div className="logo"><Gavel/></div><p className="eyebrow">JOGO MULTIPLAYER • TESTE PRIVADO</p><h1>LEILÃO DOS <em>CRAQUES</em></h1><p>O projeto está preparado. Falta conectar o banco de dados Supabase para ativar salas, autenticação e lances em tempo real.</p><div className="notice">Configure <code>VITE_SUPABASE_URL</code> e <code>VITE_SUPABASE_ANON_KEY</code> no arquivo <code>.env</code> e execute o SQL de <code>supabase/schema.sql</code>.</div></section></main>;

  if (!session) return <main className="shell"><section className="hero"><div className="logo"><Gavel/></div><p className="eyebrow">JOGO MULTIPLAYER • SALAS PRIVADAS</p><h1>LEILÃO DOS <em>CRAQUES</em></h1><p>Crie uma sala para jogar com Miguel ou entre usando o código recebido.</p><button className="primary" disabled={busy} onClick={signIn}>Entrar no jogo</button></section></main>;

  if (!profile || !room) return <main className="shell"><header className="top"><div className="brand"><Gavel/> LEILÃO DOS CRAQUES</div><span className="pill"><Radio size={14}/> Conexão segura</span></header><section className="join-grid"><article className="panel"><p className="eyebrow">IDENTIFICAÇÃO</p><h2>Quem vai jogar?</h2><label>Seu nome</label><input value={name} onChange={e=>setName(e.target.value)} placeholder="Ex.: Bruno ou Miguel"/><label>Clube que você vai representar</label><select value={clubName} onChange={e=>setClubName(e.target.value)}>{SORTED_CLUBS.map(c=><option key={c.name} value={c.name}>{c.name}</option>)}</select><div className="club-preview"><ClubBadge wiki={CLUBS.find(c=>c.name===clubName)?.wiki} name={clubName} large/><span>{clubName}</span></div><label>Orçamento da sala (R$)</label><select value={budget} onChange={e=>setBudget(e.target.value)}><option value="150">R$ 150</option><option value="200">R$ 200</option><option value="250">R$ 250</option><option value="1000">R$ 1.000</option></select><small>O orçamento escolhido pelo organizador será aplicado aos dois participantes.</small><label>Seu limite máximo por jogador (R$)</label><input type="number" min="1" value={limit} onChange={e=>setLimit(e.target.value)}/><small>Esse limite é privado. O outro participante não consegue consultá-lo.</small></article><article className="panel"><p className="eyebrow">NOVA DISPUTA</p><h2>Criar sala</h2><p>Você será o administrador da sala e poderá abrir os jogadores para leilão.</p><button className="primary" disabled={busy} onClick={createRoom}><Plus size={17}/> Criar sala privada</button><div className="separator">OU ENTRE EM UMA SALA</div><label>Código de acesso</label><input value={roomCode} onChange={e=>setRoomCode(e.target.value.toUpperCase())} placeholder="Ex.: A7K9P2"/><button className="secondary" disabled={busy} onClick={joinRoom}>Entrar na sala</button></article></section>{message && <p className="message">{message}</p>}</main>;

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
            {myBalance > 0 ? <>
              <div className="bid-settings bid-settings-mode">
                <div className="mode-picker"><label>Como deseja disputar este jogador?</label><select value={bidMode} onChange={e=>setBidMode(e.target.value)}><option value="automatic">Automático — o sistema oferece por mim</option><option value="manual">Manual — eu escolho cada lance</option></select></div>
                {bidMode === "automatic" ? <>
                  <div><label>Meu valor máximo (R$)</label><input type="number" min="1" max={myBalance} step="1" value={limit} onChange={e=>setLimit(e.target.value)}/></div>
                  <div><label>Incremento automático (R$)</label><input type="number" min="1" step="1" value={increment} onChange={e=>setIncrement(e.target.value)}/></div>
                </> : <div className="manual-mode-hint">Você enviará cada oferta manualmente. Se o adversário estiver no automático, o sistema poderá responder dentro do limite privado dele.</div>}
                <button className="secondary" disabled={busy || (bidMode === "automatic" && (!limit || Number(limit) < Number(lot.starting_bid) || !Number.isInteger(Number(limit)) || Number(limit) > myBalance)) || Number(increment) < 1 || !Number.isInteger(Number(increment))} onClick={setMyLimit}>{bidMode === "automatic" ? "Salvar automático" : "Ativar modo manual"}</button>
              </div>
              <div className="notice small"><ShieldCheck size={16}/> Cada participante escolhe seu modo. Automático responde dentro do teto privado; manual permite escolher cada oferta. Os limites automáticos não são revelados ao adversário.</div>
            </> : <div className="notice small"><ShieldCheck size={16}/> Seu saldo acabou. Você não pode mais ofertar; pode desistir deste jogador para que o adversário conclua o arremate.</div>}
            {lot.awaiting_response_from === participant?.id ? <div className="panel overbid-decision">
              <p className="eyebrow">DECISÃO NECESSÁRIA</p>
              <h3>Seu limite automático foi superado!</h3>
              <p>O adversário cobriu seu máximo. Você pode continuar aumentando seu limite, seguir manualmente ou declinar da disputa.</p>
              <label>Novo máximo automático (R$)</label>
              <input type="number" min={Number(lot.current_bid)+1} step="1" value={limit} onChange={e=>setLimit(e.target.value)}/>
              <div className="decision-actions">
                <button className="primary" disabled={busy || !Number.isInteger(Number(limit)) || Number(limit)<=Number(lot.current_bid) || Number(limit)>myBalance} onClick={()=>respondOverbid("automatic")}>Aumentar máximo e continuar</button>
                <button className="secondary" disabled={busy} onClick={()=>respondOverbid("manual")}>Continuar manualmente</button>
                <button className="danger" disabled={busy} onClick={()=>respondOverbid("decline")}>Declinar da disputa</button>
              </div>
            </div> : lot.awaiting_response_from ? <div className="draw-note"><Gavel size={18}/><span>Aguardando o adversário decidir se continuará na disputa.</span></div> : null}
            {myProxy?.lot_id === lot.id ? <div className="draw-note"><ShieldCheck size={18}/><span>{myProxy.mode === "manual" ? "Modo manual ativo. Você controla seus lances." : "Modo automático ativo. Seu teto e incremento estão protegidos."}</span></div> : <div className="draw-note"><Gavel size={18}/><span>Escolha e ative seu modo de disputa para este jogador.</span></div>}
            {myBalance > 0 && myProxy?.lot_id === lot.id && myProxy.mode === "manual" && <div className="manual-bid-entry"><label>Seu lance manual (somente valor inteiro em R$)</label><input type="number" min={nextBid} step="1" value={manualBid} onChange={e=>setManualBid(e.target.value)}/><button className="primary" disabled={busy || !Number.isInteger(chosenBid) || chosenBid < nextBid || chosenBid > myBalance} onClick={bid}>Dar lance de {money(chosenBid)}</button><small>Próximo lance mínimo: {money(nextBid)}. Você pode ofertar um valor maior diretamente.</small>{lot.current_winner && !myTop && <button className="danger" disabled={busy} onClick={pass}>Desistir da disputa e confirmar o arremate</button>}</div>}
            {myBalance <= 0 && <div className="manual-bid-entry"><button className="danger" disabled={busy || lot.current_winner === participant?.id} onClick={pass}>{lot.current_winner ? "Desistir da disputa e confirmar o arremate" : "Desistir deste jogador"}</button>{lot.current_winner === participant?.id && <small>Você está com o maior lance. Aguarde o adversário desistir ou cobrir a oferta.</small>}</div>}
            <h3>Histórico de lances</h3><div className="bid-list">{bids.slice().reverse().map((b,i)=><div className="bid-row" key={b.id}><span>{participants.find(p=>p.id===b.participant_id)?.display_name || "Participante"}</span><b>{money(b.amount)}</b></div>)}{!bids.length && <small>Nenhum lance registrado.</small>}</div>
          </> : <div className="empty"><Trophy size={28}/><p>Quando o primeiro jogador for colocado em disputa, ele aparecerá aqui.</p></div>}
        </article>
        {isHost && <article className="panel draw-panel"><p className="eyebrow">CONTROLE DO LEILOEIRO</p><h3>{completionReady ? "Completar elenco pendente" : "Próximo lote automático"}</h3><p>{completionReady ? "Como um participante já completou 23 jogadores ou os dois saldos acabaram, os jogadores brasileiros restantes serão atribuídos aleatoriamente, sem custo, somente a quem ainda tiver vagas." : "O sistema sorteia um craque ainda não utilizado. Quem estiver sem saldo só poderá desistir do lote; quem ainda tiver saldo poderá disputar normalmente."}</p><div className="draw-note"><Trophy size={18}/><span>{rosterCounts.map(p => p.display_name + ": " + p.rosterCount + "/23").join(" • ")}</span></div>{completionReady ? <button className="primary" disabled={busy} onClick={completeRostersRandomly}><Gavel size={17}/> Completar elencos aleatoriamente</button> : <button className="primary" disabled={busy || participants.length < 2 || !!lot || allBudgetsExhausted || oneRosterComplete} onClick={openLot}><Gavel size={17}/> Sortear próximo jogador</button>}</article>}
      </div>
      <aside className="side-col">
        <article className="panel"><p className="eyebrow">PARTICIPANTES</p>{participants.map(p=><div className="person" key={p.id}><ClubBadge wiki={p.club_wiki_title} name={p.club_name}/><div className="avatar">{p.display_name.slice(0,1).toUpperCase()}</div><div className="person-info"><b>{p.display_name}</b><small>{p.club_name||"Clube não selecionado"}</small><small>{p.is_host?"Organizador":"Participante"}</small><small>Saldo: {money(Math.max(0,Number(p.budget)-Number(p.spent)))}</small><small>Elenco: {rosterCounts.find(x=>x.id===p.id)?.rosterCount || 0}/23</small>{p.id===participant?.id && <div className="my-club-editor"><select value={clubDraft} onChange={e=>setClubDraft(e.target.value)}>{SORTED_CLUBS.map(c=><option key={c.name} value={c.name}>{c.name}</option>)}</select><button className="secondary club-save" disabled={busy} onClick={saveMyClub}>Escolher meu clube</button></div>}</div><span className={`dot ${p.connected?"on":""}`}/></div>)}</article>
        <article className="panel"><p className="eyebrow">SEU CAIXA</p><div className="cash"><Wallet/><div><small>Orçamento inicial</small><b>{money(participant?.budget)}</b></div></div><div className="finance-grid"><div><small>Total investido</small><b>{money(mySpent)}</b></div><div><small>Saldo disponível</small><b className="balance">{money(myBalance)}</b></div></div><small>Máximo privado atual: {money(myPrivate?.max_bid)}. Defina um valor diferente para cada jogador em disputa.</small></article>
        <article className="panel"><p className="eyebrow">ELENCO ARREMATADO</p>{roster.length ? roster.map(r=><div className="bid-row" key={r.id}><span>{r.player_name}<small>{r.position} • {participants.find(p=>p.id===r.participant_id)?.display_name || "Participante"}</small></span><b>{money(r.winning_bid)}</b></div>) : <small>Nenhum jogador arrematado ainda.</small>}</article>
      </aside>
    </section>
    {message && <p className="message">{message}</p>}
    <footer>Leilão dos Craques • Sala privada • Limites individuais e secretos</footer>
  </main>;
}