/**
 * Bend Bridge — Electron host for the Bend/HVM core.
 *
 * The Bend rebuild (bend/*.bend → HVM) runs the *parallel intelligence core*
 * (metrics, nudges, transcript, MCP, summary). This TypeScript module is the
 * host that:
 *   - loads the compiled HVM program (or falls back to TS impl when Bend is
 *     not built)
 *   - forwards LLM/MCP IO via FFI
 *   - keeps Electron-owned state (DB, keychain, capture) in TS
 *
 * Build:
 *   1) cargo install bend-lang
 *   2) make -C bend hvm          # → bend/call.hvm
 *   3) npm run build             # tsc picks up this file
 *
 * At runtime `loadHvm()` is a no-op in dev; `bend check` covers correctness.
 * In prod, replace the `StubHVM` with the real `hvm` npm package
 * (https://github.com/HigherOrderCO/HVM) and wire FFI below.
 */

import { logger } from '../lib/logger';
import type { TranscriptSegmentData } from './copilot/transcript-buffer.service';

const log = logger.child({ module: 'bend-bridge' });

// ── Types mirrored from bend/Types.bend (kept in sync with Bend ADTs) ──────
export interface BendMetrics {
  talkRatio: { me: number; them: number };
  pace: number;
  questionsAsked: number;
  monologueDetected: boolean;
  longestMonologue: number;
  totalDuration: number;
  callDuration: number;
  wordCount: { me: number; them: number };
  segmentCount: { me: number; them: number };
  averageSegmentLength: { me: number; them: number };
  interruptionCount: number;
}

export interface BendNudge {
  id: string;
  type: 'talk_ratio' | 'next_steps' | 'questions' | 'pace' | 'monologue';
  message: string;
  severity: 'low' | 'medium' | 'high';
  timestamp: number;
}

// ── Fallback: pure-TS implementations (identical formulas to Bend) ───────────
// Used when `bend/call.hvm` is absent (dev without `bend build`).
// These are *not* parallel — just correctness fallbacks.

export function fallbackCalcMetrics(
  segments: TranscriptSegmentData[],
  elapsedS: number,
): BendMetrics {
  const finals = segments.filter((s) => s.isFinal);
  const me = finals.filter((s) => s.channel === 'me');
  const them = finals.filter((s) => s.channel === 'them');

  const meDur = me.reduce((a, s) => a + (s.endTime - s.startTime), 0);
  const themDur = them.reduce((a, s) => a + (s.endTime - s.startTime), 0);
  const total = meDur + themDur;
  const maxEnd = segments.length ? Math.max(...segments.map((s) => s.endTime)) : 0;
  const callDur = Math.max(maxEnd, elapsedS);

  const countWords = (segs: TranscriptSegmentData[]) =>
    segs.reduce((a, s) => a + s.text.trim().split(/\s+/).filter(Boolean).length, 0);

  const meWc = countWords(me);
  const questions = me.filter((s) => s.text.includes('?')).length;

  // pace
  let pace = 0;
  if (me.length) {
    const words = countWords(me);
    const span = me[me.length - 1].endTime - me[0].startTime;
    const base = span > 5 ? span : callDur;
    if (base > 5) pace = Math.min(250, Math.round(words / (base / 60)));
  }

  // longest monologue (gap < 2s)
  let longest = 0;
  let curStart: number | null = null;
  let curEnd = 0;
  for (const s of me) {
    if (curStart === null) {
      curStart = s.startTime;
      curEnd = s.endTime;
    } else if (s.startTime - curEnd < 2) {
      curEnd = s.endTime;
    } else {
      longest = Math.max(longest, curEnd - (curStart as number));
      curStart = s.startTime;
      curEnd = s.endTime;
    }
  }
  if (curStart !== null) longest = Math.max(longest, curEnd - (curStart as number));

  const mono = me.length >= 3 && (() => {
    const recent = me.slice(-5);
    if (recent.length < 3) return false;
    return recent[recent.length - 1].endTime - recent[0].startTime > 45;
  })();

  // interruptions
  const sorted = [...finals].sort((a, b) => a.startTime - b.startTime);
  let interrupts = 0;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].channel !== sorted[i - 1].channel && sorted[i].startTime < sorted[i - 1].endTime) {
      interrupts++;
    }
  }

  return {
    talkRatio: { me: total > 0 ? meDur / total : 0.5, them: total > 0 ? themDur / total : 0.5 },
    pace,
    questionsAsked: questions,
    monologueDetected: mono,
    longestMonologue: longest,
    totalDuration: total,
    callDuration: callDur,
    wordCount: { me: meWc, them: countWords(them) },
    segmentCount: { me: me.length, them: them.length },
    averageSegmentLength: {
      me: me.length ? meDur / me.length : 0,
      them: them.length ? themDur / them.length : 0,
    },
    interruptionCount: interrupts,
  };
}

// ── HVM loader (stub) ──────────────────────────────────────────────────────

type HvmExports = {
  calc_metrics: (segs: TranscriptSegmentData[], elapsedS: number) => BendMetrics;
  nudge_evaluate: (state: unknown, m: BendMetrics, durS: number, nowMs: number) => [unknown, BendNudge | null];
};

let hvm: HvmExports | null = null;
let hvmReady = false;

export async function loadHvm(): Promise<boolean> {
  if (hvmReady) return hvm !== null;
  hvmReady = true;
  try {
    // In prod: `import { load } from 'hvm'; hvm = await load('bend/call.hvm');`
    // and bind FFI:
    //   hvm.bind('llm_call', async (prompt: string) => openai.chat(prompt));
    //   hvm.bind('mcp_call_tool', async (sid, tool, input) => mcpClient.call(...));
    log.info('Bend HVM not linked — using TS fallback (run `make -C bend hvm` to build)');
    return false;
  } catch (e) {
    log.warn({ e }, 'Failed to load Bend HVM');
    return false;
  }
}

export function calcMetrics(segments: TranscriptSegmentData[], elapsedS: number): BendMetrics {
  if (hvm) return hvm.calc_metrics(segments, elapsedS);
  return fallbackCalcMetrics(segments, elapsedS);
}

// Nudge state is kept as opaque HVM term; TS fallback keeps a JS object.
export interface NudgeStateJS {
  lastMs: number;
  history: BendNudge[];
  cooldown: number;
}

export function createNudgeState(): NudgeStateJS {
  return { lastMs: 0, history: [], cooldown: 120000 };
}

export function evaluateNudge(
  state: NudgeStateJS,
  m: BendMetrics,
  callDurS: number,
  nowMs: number,
): [NudgeStateJS, BendNudge | null] {
  if (!state) return [state, null];
  // delegate to HVM if available
  // if (hvm) { const [ns, n] = hvm.nudge_evaluate(...); return ... }

  // TS fallback — same priority logic as bend/Nudge.bend
  if (nowMs - state.lastMs < state.cooldown && state.lastMs !== 0) return [state, null];

  let candidate: BendNudge['type'] | null = null;
  let sev: BendNudge['severity'] = 'low';
  let msg = '';

  if (m.totalDuration >= 60 && m.talkRatio.me > 0.75) {
    candidate = 'talk_ratio';
    msg = "You've been driving most of the conversation so far";
    sev = 'medium';
  } else if (m.totalDuration >= 60 && m.talkRatio.me > 0.65) {
    candidate = 'talk_ratio';
    msg = 'Talk ratio is leaning towards you — balance with more listening';
  } else if (callDurS >= 180 && m.questionsAsked < (callDurS / 120) * 0.5) {
    candidate = 'questions';
    msg = 'Few questions asked so far — discovery helps uncover needs';
  } else if (m.pace > 180) {
    candidate = 'pace';
    msg = 'Speaking pace is on the faster side — slowing down can help clarity';
  } else if (callDurS > 1200 && callDurS < 1230) {
    candidate = 'next_steps';
    msg = 'Consider confirming next steps before ending the call';
    sev = 'medium';
  } else if (callDurS > 1800 && callDurS < 1830) {
    candidate = 'next_steps';
    msg = 'Good time to discuss action items and timeline';
  }

  if (!candidate) return [state, null];

  const nudge: BendNudge = {
    id: `nudge-${nowMs}`,
    type: candidate,
    message: msg,
    severity: sev,
    timestamp: nowMs,
  };
  const next: NudgeStateJS = { lastMs: nowMs, history: [...state.history, nudge], cooldown: state.cooldown };
  log.info({ type: nudge.type, msg: nudge.message }, 'Nudge (bend-bridge fallback)');
  return [next, nudge];
}
