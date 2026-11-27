import React, { useEffect, useMemo, useState } from "react";
import { Trophy, Play, Clock3, ArrowLeftRight } from "lucide-react";

const COACHES = [
 {name:"Telê Santana",style:"Jogo ofensivo",attack:1.10,defense:.94,control:1.02},
 {name:"Mário Zagallo",style:"Equilíbrio e competitividade",attack:1.03,defense:1.04,control:1.04},
 {name:"Luiz Felipe Scolari",style:"Força e jogo direto",attack:1.02,defense:1.08,control:1.00},
 {name:"Tite",style:"Organização e pressão",attack:1.02,defense:1.07,control:1.06},
 {name:"Vanderlei Luxemburgo",style:"Técnica e criatividade",attack:1.08,defense:.97,control:1.05},
 {name:"Muricy Ramalho",style:"Compactação defensiva",attack:.97,defense:1.10,control:1.02},
 {name:"Cuca",style:"Intensidade e variação",attack:1.06,defense:1.01,control:1.04},
 {name:"Dorival Júnior",style:"Equilíbrio tático",attack:1.04,defense:1.03,control:1.05},
 {name:"Renato Gaúcho",style:"Liberdade ofensiva",attack:1.09,defense:.95,control:1.00},
 {name:"Abel Braga",style:"Organização e experiência",attack:1.00,defense:1.08,control:1.03}
];
const TACTICS = {
 equilibrado:{label:"Equilibrado",attack:1,defense:1},
 ofensivo:{label:"Ofensivo",attack:1.09,defense:.94},
 defensivo:{label:"Defensivo",attack:.94,defense:1.10},
 contra:{label:"Contra-ataque",attack:1.07,defense:1.04},
 posse:{label:"Posse de bola",attack:1.04,defense:1.02}
};
const FORMATIONS=["4-4-2","4-3-3","3-5-2","4-2-3-1"];
const avg=xs=>xs.length?xs.reduce((n,p)=>n+Number(p.rating||75),0)/xs.length:75;
const teamName=t=>t?.participant?.display_name||"Equipe";

function makeLineup(teamRoster){
 const needs=[["Goleiro",1],["Lateral-direito",1],["Zagueiro",2],["Lateral-esquerdo",1],["Volante",1],["Meio-campo",3],["Atacante",2]];
 const used=new Set(),starters=[];
 needs.forEach(([position,count])=>teamRoster.filter(p=>p.position===position&&!used.has(p.id)).sort((a,b)=>Number(b.rating||75)-Number(a.rating||75)).slice(0,count).forEach(p=>{used.add(p.id);starters.push({...p,fatigue:0});}));
 if(starters.length<11)teamRoster.filter(p=>!used.has(p.id)).sort((a,b)=>Number(b.rating||75)-Number(a.rating||75)).slice(0,11-starters.length).forEach(p=>{used.add(p.id);starters.push({...p,fatigue:0});});
 return {starters,bench:teamRoster.filter(p=>!used.has(p.id)).map(p=>({...p,fatigue:0}))};
}
function newTeam(participant,teamRoster){
 return {participant,...makeLineup(teamRoster),coach:COACHES[Math.floor(Math.random()*COACHES.length)],tactic:"equilibrado",formation:"4-4-2",substitutions:0,subWindows:0,lastSubMinute:null,subLog:[]};
}
function scoreBlock(team,opponent){
 const fatigue=team.starters.reduce((n,p)=>n+Number(p.fatigue||0),0)/11;
 const attack=avg(team.starters)*TACTICS[team.tactic].attack*team.coach.attack*(1-fatigue*.0028);
 const defense=avg(team.starters)*TACTICS[team.tactic].defense*team.coach.defense*(1-fatigue*.0022);
 const formationBonus=team.formation==="4-3-3"?1.015:team.formation==="3-5-2"?1.01:team.formation==="4-2-3-1"?1.012:1;
 const strength=(attack*.68+defense*.20+avg(team.bench)*.12)*formationBonus*team.coach.control;
 const lambda=Math.max(.07,Math.min(.72,.23+(strength-avg(opponent.starters))/115));
 let goals=0;for(let i=0;i<3;i++)if(Math.random()<lambda)goals++;
 return {goals,strength:Math.round(strength),avg:Math.round(avg(team.starters))};
}
function scorers(team,n,start,end){
 const pool=team.starters.filter(p=>["Atacante","Meio-campo","Volante"].includes(p.position));
 return Array.from({length:n},()=>({team:teamName(team),participant_id:team.participant.id,player:pool[Math.floor(Math.random()*pool.length)]?.player_name||"Gol",minute:Math.floor(Math.random()*(end-start+1))+start,type:"goal"}));
}

export default function MatchCenter({supabase,roomId,participant,participants,roster,isHost,setMessage}){
 const [roomMatch,setRoomMatch]=useState({match_state:null,match_history:[],match_series:null,match_result:null});
 const [busy,setBusy]=useState(false),[outgoing,setOutgoing]=useState(null),[subOut,setSubOut]=useState(""),[subIn,setSubIn]=useState("");
 const current=roomMatch.match_state,score=current?.score||{},history=roomMatch.match_history||[];
 const series=roomMatch.match_series||current?.series||null,seriesActive=!!series?.active;
 const myTeam=current?.teams?.[participant?.id],editableTeam=outgoing||myTeam;
 const readyMap=current?.ready||{},myReady=!!readyMap[participant?.id],otherReady=!!readyMap[participants.find(p=>p.id!==participant?.id)?.id];
 const ready=participants.length===2&&participants.every(p=>roster.filter(r=>r.participant_id===p.id).length===23);
 const wins=useMemo(()=>Object.fromEntries(participants.map(p=>[p.id,history.filter(h=>h.winner_id===p.id).length])),[history,participants]);
 const canStartBest=participants.length===2&&participants.every(p=>(wins[p.id]||0)>0);

 async function load(){
  const {data,error}=await supabase.from("rooms").select("match_state,match_history,match_series,match_result").eq("id",roomId).single();
  if(error){setMessage(error.message);return;}
  setRoomMatch({match_state:data.match_state,match_history:data.match_history||[],match_series:data.match_series,match_result:data.match_result});
 }
 useEffect(()=>{load();const channel=supabase.channel("match-engine-"+roomId).on("postgres_changes",{event:"UPDATE",schema:"public",table:"rooms",filter:"id=eq."+roomId},load).subscribe();return()=>{supabase.removeChannel(channel);};},[roomId]);
 async function callRpc(fn,args,success){
  setBusy(true);setMessage("");
  const {data,error}=await supabase.rpc(fn,args);setBusy(false);
  if(error){setMessage(error.message);return null;}
  if(success)success(data);await load();return data;
 }
 async function startMatch(bestOfThree=false){
  if(!isHost)return setMessage("Somente o organizador pode iniciar o confronto.");
  if(!ready)return setMessage("Os dois elencos precisam estar completos.");
  if(current&&current.status!=="finished")return setMessage("Já existe uma partida em andamento.");
  const teams={};participants.forEach(p=>{teams[p.id]=newTeam(p,roster.filter(r=>r.participant_id===p.id));});
  const initial={match_id:crypto.randomUUID(),status:"live",minute:0,paused:true,teams,score:Object.fromEntries(participants.map(p=>[p.id,0])),events:[],result:null};
  await callRpc("start_room_match",{p_state:initial,p_best_of_three:bestOfThree},()=>setOutgoing(null));
 }
 function changeMyTeam(patch){if(myTeam)setOutgoing({...editableTeam,...patch});}
 async function saveTeam(){
  if(!editableTeam||!current?.paused||current?.status!=="live")return;
  await callRpc("update_room_match_team",{p_team_id:participant.id,p_team:editableTeam},()=>setOutgoing(null));
 }
 function makeSub(){
  if(!editableTeam)return;
  const out=editableTeam.starters.find(p=>p.id===subOut),incoming=editableTeam.bench.find(p=>p.id===subIn);
  if(!out||!incoming)return setMessage("Selecione quem sai e quem entra.");
  const newWindows=editableTeam.lastSubMinute===current.minute||current.minute===45?editableTeam.subWindows:editableTeam.subWindows+1;
  if(editableTeam.substitutions>=5)return setMessage("Limite de cinco substituições atingido.");
  if(current.minute!==45&&newWindows>3)return setMessage("Você já utilizou as três oportunidades de substituição.");
  const starters=editableTeam.starters.map(p=>p.id===out.id?{...incoming,fatigue:0}:p);
  const bench=editableTeam.bench.map(p=>p.id===incoming.id?{...out}:p);
  const subLog=[...(editableTeam.subLog||[]),{minute:current.minute,out:out.player_name,in:incoming.player_name}];
  changeMyTeam({...editableTeam,starters,bench,substitutions:editableTeam.substitutions+1,subWindows:newWindows,lastSubMinute:current.minute,subLog});
  setSubOut("");setSubIn("");
 }
 async function toggleReady(){await callRpc('set_room_match_ready',{p_ready:!myReady});}
 async function advance(){
  if(!isHost||!current?.paused||current.status!=="live")return;
  const nextMinute=current.minute+15,ids=participants.map(p=>p.id);
  const left=current.teams[ids[0]],right=current.teams[ids[1]];
  if(!left||!right)return setMessage("Escalações não encontradas.");
  const l=scoreBlock(left,right),r=scoreBlock(right,left);
  const events=[...(current.events||[]),...scorers(left,l.goals,current.minute+1,nextMinute),...scorers(right,r.goals,current.minute+1,nextMinute)].sort((a,b)=>a.minute-b.minute);
  const teams={...current.teams};
  Object.keys(teams).forEach(id=>{teams[id]={...teams[id],starters:teams[id].starters.map(p=>({...p,fatigue:Math.min(100,Number(p.fatigue||0)+9)}))};});
  const nextScore={...score,[ids[0]]:Number(score[ids[0]]||0)+l.goals,[ids[1]]:Number(score[ids[1]]||0)+r.goals};
  let next={...current,minute:nextMinute,paused:true,teams,score:nextScore,events,status:nextMinute===90?"finished":"live"};
  if(nextMinute===90){
   const hg=nextScore[ids[0]],ag=nextScore[ids[1]],winnerId=hg===ag?null:hg>ag?ids[0]:ids[1];
   const result={match_id:current.match_id,played_at:new Date().toISOString(),teams,home:{goals:hg,avg:l.avg,strength:l.strength},away:{goals:ag,avg:r.avg,strength:r.strength},events,winner:winnerId?participants.find(p=>p.id===winnerId)?.display_name:"Empate",winner_id:winnerId,series_id:seriesActive?(series.id||null):null};
   next={...next,result};
  }
  await callRpc("advance_room_match",{p_state:next});
 }

 if(!ready)return <article className="panel draw-panel"><p className="eyebrow">NOVA ETAPA • CAMPO</p><h3>Central de partidas</h3><p>Complete os dois elencos com 23 jogadores para liberar o campo.</p></article>;
 return <article className="panel draw-panel match-center">
  <p className="eyebrow">NOVA ETAPA • CAMPO</p><h3>Central de partidas</h3>
  <p>Partida de 90 minutos, avanço manual em blocos de 15 minutos, ajustes táticos nas pausas e resultado sincronizado.</p>
  {(!current||current.status==="finished")?<div className="match-launch">
   {isHost?<button className="primary" disabled={busy} onClick={()=>startMatch(false)}><Play size={17}/>{history.length?"Iniciar revanche":"Sortear técnicos e iniciar"}</button>:<div className="draw-note"><Clock3 size={17}/>Aguardando o organizador iniciar o confronto.</div>}
   {isHost&&canStartBest&&<button className="secondary" disabled={busy} onClick={()=>startMatch(true)}><Trophy size={17}/>{seriesActive?"Próximo jogo da melhor de 3":"Iniciar melhor de 3"}</button>}
   {current?.status==="finished"&&<div className="match-result"><p className="eyebrow">APITO FINAL</p><h2>{current.result?.home?.goals??0} × {current.result?.away?.goals??0}</h2><h3>{current.result?.winner==="Empate"?"Empate":current.result?.winner?"Vitória de "+current.result.winner:"Partida encerrada"}</h3>{Object.values(current.teams||{}).map(t=><p key={t.participant.id}>{teamName(t)} — Técnico: <b>{t.coach.name}</b></p>)}{series&&<p>Série: {participants.map(p=>p.display_name+" "+(series.wins?.[p.id]||0)).join(" × ")}</p>}</div>}
  </div>:<div className="match-live">
   <div className="match-scoreboard"><div><small>{teamName(current.teams[participants[0]?.id])}</small><strong>{score[participants[0]?.id]||0}</strong></div><div className="match-clock"><span>{current.minute}'</span><small>{current.minute===45?"INTERVALO":"PAUSA TÉCNICA"}</small></div><div><small>{teamName(current.teams[participants[1]?.id])}</small><strong>{score[participants[1]?.id]||0}</strong></div></div>
   <div className="coach-grid">{participants.map(p=>{const t=current.teams[p.id];return <div className="coach-card" key={p.id}><p className="eyebrow">{p.display_name}</p><b>{t?.coach?.name}</b><small>{t?.coach?.style}</small><small>Influência do técnico: até 15%</small></div>;})}</div>
   <div className="draw-note"><Clock3 size={17}/><span>{current.minute===45?"Intervalo: ajuste seu time para o segundo tempo.":"Pausa aos "+current.minute+" minutos. Faça suas alterações e salve antes de avançar."}</span></div>
   {editableTeam&&<div className="team-control panel">
    <p className="eyebrow">SEU COMANDO TÉCNICO</p>
    <label>Esquema tático</label><select value={editableTeam.formation} onChange={e=>changeMyTeam({formation:e.target.value})}>{FORMATIONS.map(f=><option key={f}>{f}</option>)}</select>
    <label>Estratégia</label><select value={editableTeam.tactic} onChange={e=>changeMyTeam({tactic:e.target.value})}>{Object.entries(TACTICS).map(([k,v])=><option key={k} value={k}>{v.label}</option>)}</select>
    <div className="sub-status"><b>Substituições: {editableTeam.substitutions}/5</b><span>Janelas: {editableTeam.subWindows}/3 (intervalo não conta)</span></div>
    <label>Substituição</label><div className="substitution-row">
     <select value={subOut} onChange={e=>setSubOut(e.target.value)}><option value="">Sai — titular</option>{editableTeam.starters.map(p=><option key={p.id} value={p.id}>{p.player_name} ({p.position})</option>)}</select>
     <ArrowLeftRight size={18}/>
     <select value={subIn} onChange={e=>setSubIn(e.target.value)}><option value="">Entra — reserva</option>{editableTeam.bench.map(p=><option key={p.id} value={p.id}>{p.player_name} ({p.position})</option>)}</select>
     <button className="secondary" disabled={busy||editableTeam.substitutions>=5||!subOut||!subIn} onClick={makeSub}>Adicionar</button>
    </div>
    <div className="lineup-mini"><b>Time titular</b>{editableTeam.starters.map(p=><div className="bid-row" key={p.id}><span>{p.player_name}<small>{p.position}</small></span><b>{p.rating||75}</b></div>)}</div>
    <button className="primary" disabled={busy||!outgoing} onClick={saveTeam}>Salvar alterações do meu time</button>
    <small>As mudanças ficam privadas até serem salvas e passam a valer no próximo bloco.</small>
   </div>}
   <div className="match-events"><b>Eventos da partida</b>{current.events?.length?current.events.map((e,i)=><div className="bid-row" key={i}><span>{e.minute}' • {e.player}<small>{e.team}</small></span><b>GOL</b></div>):<small>Nenhum gol até aqui.</small>}</div>
   <div className="match-ready-row"><div className="draw-note"><Clock3 size={17}/><span>Você: <b>{myReady?'PRONTO':'aguardando'}</b> • Adversário: <b>{otherReady?'PRONTO':'aguardando'}</b></span></div><button className={myReady?'secondary':'primary'} disabled={busy||!!outgoing} onClick={toggleReady}>{myReady?'Cancelar PRONTO':'Estou PRONTO'}</button></div>
   {isHost?<button className="primary" disabled={busy||!!outgoing||!myReady||!otherReady} onClick={advance}><Play size={17}/>Avançar para {current.minute+15}'</button>:<div className="draw-note"><Clock3 size={17}/>Aguardando o organizador avançar depois que os dois confirmarem PRONTO.</div>}
  </div>}
  {history.length>0&&<div className="match-history"><p className="eyebrow">HISTÓRICO DO CONFRONTO</p>{history.slice().reverse().map((h,i)=><div className="bid-row" key={h.match_id||i}><span>Partida • {new Date(h.played_at||Date.now()).toLocaleDateString("pt-BR")}</span><b>{h.home?.goals} × {h.away?.goals}</b></div>)}</div>}
 </article>;
}
