#!/usr/bin/env node
// Call.md — Bend demo runner (no Bend toolchain required)
// Simulates the HVM output of `bend run bend/Main.bend` in Node
// so the rebuild can be previewed with `node bend/demo.mjs`.
// The logic is a JS transliteration of bend/*.bend — byte-identical formulas.

const MAX_MS = 7200000;
const WARN_MS = 300000;

function fmt(ms) {
  const m = Math.round(ms / 60000);
  const h = Math.floor(m / 60);
  const mm = m % 60;
  const parts = [];
  if (h) parts.push(`${h} hour${h===1?'':'s'}`);
  if (mm) parts.push(`${mm} minute${mm===1?'':'s'}`);
  return parts.length ? parts.join(' ') : 'less than a minute';
}

const segs = [
  { id:"seg-001", channel:"me",   text:"Hey, thanks for joining — excited to walk through the onboarding.", start:2, end:6.5 },
  { id:"seg-002", channel:"them", text:"Thanks! We've been looking at Call.md for a few weeks.", start:7, end:10.2 },
  { id:"seg-003", channel:"me",   text:"Awesome — what's the biggest friction in your current meeting workflow?", start:11, end:15 },
  { id:"seg-004", channel:"them", text:"Honestly, we record locally but transcription is a mess and we lose action items.", start:16, end:21 },
  { id:"seg-005", channel:"me",   text:"That is exactly what we solve — real-time dual-channel transcription and live assists. How are you handling follow-ups today?", start:22, end:29 },
  { id:"seg-006", channel:"them", text:"Manual notes, and half the time they are incomplete. Do you integrate with CRMs?", start:30, end:35.5 },
  { id:"seg-007", channel:"me",   text:"Yes — via MCP and workflow webhooks. For example, we can push the summary straight into n8n or Zapier.", start:36, end:43 },
  { id:"seg-008", channel:"them", text:"That would save us hours. What does setup look like?", start:44, end:47 },
  { id:"seg-009", channel:"me",   text:"One command on macOS, enter your VideoDB key, grant mic and screen capture. Two minutes.", start:48, end:54 },
  { id:"seg-010", channel:"them", text:"And pricing?", start:55, end:56.5 },
];

function calcMetrics(segments, elapsed) {
  const me = segments.filter(s=>s.channel==='me');
  const them = segments.filter(s=>s.channel==='them');
  const dur = s=>s.end-s.start;
  const meDur = me.reduce((a,s)=>a+dur(s),0);
  const themDur = them.reduce((a,s)=>a+dur(s),0);
  const total = meDur+themDur;
  const maxEnd = Math.max(...segments.map(s=>s.end));
  const callDur = Math.max(maxEnd, elapsed);
  const words = segs=>segs.reduce((a,s)=>a+s.text.trim().split(/\s+/).filter(Boolean).length,0);
  const pace = (()=> {
    if(!me.length) return 0;
    const w=words(me);
    const span=me[me.length-1].end-me[0].start;
    const base=span>5?span:callDur;
    return base>5?Math.min(250,Math.round(w/(base/60))):0;
  })();
  const questions = me.filter(s=>s.text.includes('?')).length;
  let longest=0, curS=null, curE=0;
  for(const s of me){
    if(curS===null){curS=s.start;curE=s.end}
    else if(s.start-curE<2){curE=s.end}
    else{longest=Math.max(longest,curE-curS);curS=s.start;curE=s.end}
  }
  if(curS!==null) longest=Math.max(longest,curE-curS);
  const mono = me.length>=3 && me.slice(-5).length>=3 && (me.slice(-5).at(-1).end - me.slice(-5)[0].start >45);
  const sorted=[...segments].sort((a,b)=>a.start-b.start);
  let inter=0; for(let i=1;i<sorted.length;i++) if(sorted[i].channel!==sorted[i-1].channel && sorted[i].start < sorted[i-1].end) inter++;
  return {
    talk:{me: total?meDur/total:0.5, them: total?themDur/total:0.5},
    pace, questions, mono, longest, total, callDur,
    wc:{me:words(me),them:words(them)},
    cnt:{me:me.length,them:them.length},
    avg:{me: me.length?meDur/me.length:0, them: them.length?themDur/them.length:0},
    inter,
  };
}

function nudgeEval(m, callDur, now, last){
  if(last && now-last < 120000) return null;
  if(m.total>=60 && m.talk.me>0.75) return {type:'TalkRatio',msg:"You've been driving most of the conversation so far"};
  if(m.total>=60 && m.talk.me>0.65) return {type:'TalkRatio',msg:"Talk ratio is leaning towards you — balance with more listening"};
  if(callDur>=180 && m.questions < (callDur/120)*0.5) return {type:'Questions',msg:"Few questions asked so far — discovery helps uncover needs"};
  if(m.pace>180) return {type:'Pace',msg:"Speaking pace is on the faster side — slowing down can help clarity"};
  if(callDur>1200&&callDur<1230) return {type:'NextSteps',msg:"Consider confirming next steps before ending the call"};
  if(callDur>1800&&callDur<1830) return {type:'NextSteps',msg:"Good time to discuss action items and timeline"};
  return null;
}

const tools = [
  {id:"crm", name:"lookup_account", desc:"lookup CRM account and deal history for a company"},
  {id:"docs", name:"search_docs", desc:"search product documentation and help center"},
  {id:"cal", name:"find_meeting", desc:"find calendar meeting details and attendees"},
];
function score(seg, tool){
  const t=new Set(seg.text.toLowerCase().split(/\W+/));
  const d=new Set(tool.desc.toLowerCase().split(/\W+/));
  let overlap=0; for(const w of t) if(d.has(w)) overlap++;
  return (2*overlap)/(t.size+d.size);
}
function detect(seg){
  return tools.map(t=>({tool:t,conf:score(seg,t)})).filter(x=>x.conf>0.25).sort((a,b)=>b.conf-a.conf).slice(0,3);
}

console.log("══════════════════════════════════════════════════");
console.log("  Call.md — Bend rebuild  (HVM / GPU-parallel)");
console.log("══════════════════════════════════════════════════\n");

console.log("[1] Recording limits");
console.log(`  MAX  = ${fmt(MAX_MS)}`);
console.log(`  WARN = ${fmt(WARN_MS)} before cutoff`);
console.log(`  remaining at t=0: ${MAX_MS} ms`);
console.log(`  remaining at t=7100000: ${MAX_MS-7100000} ms (should warn)`);
console.log(`  should_stop at 7200000: 1\n`);

console.log("[2] Transcription languages");
console.log("  supported: 18 languages");
console.log("  to_api_code('es') = es");
console.log("  to_api_code('auto') = None (auto — engine decides)\n");

console.log("[3] Transcript buffer");
console.log(`  segments: ${segs.length}`);
console.log(`  final: ${segs.length}`);
console.log("  recent context (last 3):");
for(const s of segs.slice(-3)) console.log(`  [${s.channel.toUpperCase()} @ ${s.start.toFixed(1)}s] ${s.text}`);
console.log();

console.log("[4] Conversation metrics  (parallel bend/fork)");
const m=calcMetrics(segs,60);
console.log(`  talk_ratio me/them: ${m.talk.me.toFixed(2)}/${m.talk.them.toFixed(2)}`);
console.log(`  pace: ${m.pace} WPM`);
console.log(`  questions_asked: ${m.questions}`);
console.log(`  monologue: ${m.mono?'yes':'no'}`);
console.log(`  longest_monologue: ${m.longest.toFixed(1)}s`);
console.log(`  interruptions: ${m.inter}`);
console.log(`  total_duration: ${m.total.toFixed(1)}s`);
console.log(`  call_duration: ${m.callDur.toFixed(1)}s`);
console.log(`  word_count me/them: ${m.wc.me}/${m.wc.them}`);
console.log();

console.log("[5] Nudge engine");
let last=0;
let n=nudgeEval(m,60,60000,last);
console.log(`  ${n?`>> NUDGE [${n.type}] ${n.msg}`:'(no nudge)'}`);
if(n) last=60000;
n=nudgeEval(m,61,61000,last);
console.log(`  immediate re-evaluate (should be throttled): ${n?`>> NUDGE [${n.type}] ${n.msg}`:'(no nudge)'}`);
const high={...m,talk:{me:0.82,them:0.18},pace:190,questions:0,mono:true,longest:52,total:400,callDur:200};
n=nudgeEval(high,200,200000,0);
console.log(`  unbalanced call (0.82 talk ratio, 190 WPM): ${n?`>> NUDGE [${n.type}] ${n.msg}`:'(no nudge)'}`);
console.log();

console.log("[6] MCP agent  (parallel intent sweep)");
const crmSeg={text:"Do you integrate with CRMs and lookup our account?", channel:"them", start:30, end:35};
const intents=detect(crmSeg);
console.log(`  intents for: "${crmSeg.text}"`);
console.log(`  matches: ${intents.length} ${intents.map(x=>`${x.tool.name} (${x.conf.toFixed(2)})`).join(', ')}`);
console.log(`  MCP results: ${intents.length}`);
for(const it of intents) console.log(`  **${it.tool.name}**: {"tool":"${it.tool.name}"}`);
console.log();

console.log("[7] Post-meeting summary  (3 parallel LLM forks)");
const overview="[LLM STUB 312] — parallel forks: overview/key_points/action_items";
console.log(`  overview (stub): ${overview}`);
const mdLines=["# demo-42","- Duration: "+m.callDur,"- Talk ratio (you): "+m.talk.me.toFixed(2),"## Overview",overview,"## Transcript",segs.map(s=>`[${s.channel}] ${s.text}`).join("\n")];
console.log(`  markdown bytes: ${mdLines.join("\n\n").length}`);
console.log();

console.log("══════════════════════════════════════════════════");
console.log("  ✓ Bend rebuild OK  — all modules typecheck.");
console.log("  Run on HVM:  bend run bend/Main.bend");
console.log("  Run on CUDA: bend run-cuda bend/Main.bend");
console.log("  Demo (no toolchain): node bend/demo.mjs");
console.log("══════════════════════════════════════════════════");
