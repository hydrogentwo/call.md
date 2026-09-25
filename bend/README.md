# Call.md — Bend Rebuild

> **Bend** (Higher-Order Company) rebuild of [call.md](https://github.com/video-db/call.md) — same product, massively parallel semantics.  
> Original: Electron 42 + React 19 + TypeScript. **Bend port:** pure functional Bend compiled to [HVM2](https://github.com/HigherOrderCO/HVM) → runs natively on CPU and CUDA GPUs.

```
Original TS (sequential)          Bend (parallel HVM)
 ─────────────────────            ────────────────────
 reduce(me.map(...))              bend/fork tree reduction
 sequential filter                 parallel_filter (divide-and-conquer)
 for-loop metrics                  4-way fork (dur/words/pace/interrupts)
 rate-limited nudge loop          pure NudgeState/evaluate(now_ms)
 Node IPC + SQLite                 HVM linear types + FFI to host
```

---

## Why Bend?

| Concern | TypeScript | Bend |
|---|---|---|
| **Conversation metrics** | `Array.reduce` over `meSegments` then `themSegments` (sequential) | `fork(calc_duration(me)) ‖ fork(calc_duration(them))` — HVM schedules on threads/GPU |
| **Transcript buffer** | `segments.filter(...)` | `parallel_filter` — binary tree, `O(n/p)` |
| **MCP intent detection** | loop over tools | fan-out: one HVM thread per tool |
| **Summary** | 3 sequential `await openai.chat(...)` | `fork(llm_call(p_overview)) ‖ fork(llm_call(p_keypts)) ‖ fork(llm_call(p_actions))` |
| **Recording limits** | `setInterval` in main process | pure `RecordingState/remaining_ms` — no timers, testable |
| **Safety** | exceptions, `undefined` | ADTs + `Maybe` — total functions, no null |

Bend's `bend`/`fork` compile to **interaction combinators**. On HVM you get the same result on a laptop CPU and on a 4090 — just faster.

---

## Project Layout

```
bend/
  Types.bend       — ADTs mirroring src/shared/types/* + src/main/db/schema.ts
  Recording.bend   — 2-hour cutoff, pause-aware elapsed time, deadline sweep
  Languages.bend   — 17 transcription languages, Maybe(Language) API
  Transcript.bend  — rolling buffer (100-window / 200-cap), parallel filter/map
  Metrics.bend     — conversation intelligence (talk ratio, pace, monologue, interruptions)
  Nudge.bend       — rate-limited (120s), priority-ordered coaching nudges
  Summary.bend     — 3-way parallel LLM extraction → markdown export
  MCP.bend         — intent detector + tool aggregator + parallel tool runner
  Main.bend        — entry point: simulates a full meeting, prints all subsystems
  Makefile         — bend check / run / gen-hvm / run-cuda
  README.md        — this file
```

Each file mirrors the original service:

| Original file | Bend module |
|---|---|
| `src/shared/constants/recording.ts` + `recording-limit.service.ts` | `Recording.bend` |
| `src/shared/constants/languages.ts` | `Languages.bend` |
| `src/main/services/copilot/transcript-buffer.service.ts` | `Transcript.bend` |
| `src/main/services/copilot/conversation-metrics.service.ts` | `Metrics.bend` |
| `src/main/services/copilot/nudge-engine.service.ts` | `Nudge.bend` |
| `src/main/services/copilot/summary-generator.service.ts` + `llm.service.ts` | `Summary.bend` |
| `src/main/services/mcp/*.service.ts` | `MCP.bend` |
| `src/shared/types/*` + `src/shared/schemas/*` + `src/main/db/schema.ts` | `Types.bend` |
| `src/main/services/copilot/sales-copilot.service.ts` (orchestrator) | `Main.bend` (wiring) |

---

## Quick Start

### 1. Install Bend

```bash
cargo install bend-lang          # or: curl -fsSL https://bend-lang.org/install | sh
bend --version                   # 0.2.3x
```

HVM is bundled with `bend`. For CUDA:

```bash
bend --help | grep cuda
```

### 2. Check (typecheck, no execution)

```bash
# from repo root
bend check bend/Main.bend
make -C bend check
```

### 3. Run (interpreted HVM, CPU)

```bash
bend run bend/Main.bend
make -C bend run
```

Expected output (abridged):

```
══════════════════════════════════════════════════
  Call.md — Bend rebuild  (HVM / GPU-parallel)
══════════════════════════════════════════════════

[1] Recording limits
  MAX  = 2 hours
  WARN = 5 minutes before cutoff
  remaining at t=0: 7200000 ms
  ...

[4] Conversation metrics  (parallel bend/fork)
  talk_ratio me/them: 0.52/0.48
  pace: 142 WPM
  questions_asked: 3
  ...

[5] Nudge engine
  (no nudge)
  immediate re-evaluate (should be throttled): (no nudge)
  unbalanced call (0.82 talk ratio, 190 WPM): >> NUDGE [TalkRatio] You've been driving...

[6] MCP agent  (parallel intent sweep)
  intents for: "Do you integrate with CRMs and lookup our account?"
  matches: 1
  MCP results: 1

[7] Post-meeting summary  (3 parallel LLM forks)
  overview (stub): [LLM STUB 312]
  markdown bytes: 2841

══════════════════════════════════════════════════
  ✓ Bend rebuild OK  — all modules typecheck.
```

### 4. Run on GPU

```bash
bend run-cuda bend/Main.bend
make -C bend cuda
```

### 5. Compile to HVM / C / standalone binary

```bash
bend gen-hvm bend/Main.bend -o call.hvm
bend gen-c   bend/Main.bend -o call.c
bend build   bend/Main.bend -o call   # native binary (requires clang)
```

---

## Bend Concepts Used

**`bend` tree + `fork`** — every `List/filter`, `count_words`, `sum_duration` is a binary tree. HVM keeps the tree balanced, so `O(n)` becomes `O(log n)` depth.

```bend
def parallel_filter(lst, pred) -> List:
  n = List/len(lst)
  if n <= 32: return List/filter(lst, pred)
  else:
    left  = fork(parallel_filter(List/take(lst, n/2), pred))
    right = fork(parallel_filter(List/drop(lst, n/2), pred))
    return List/concat(left, right)
```

**Pure state** — no `Map` mutation, no `EventEmitter`. `TranscriptState`, `RecordingState`, `NudgeState` are values threaded through. The Electron host owns IO (FFI).

**ADTs over strings** — `Channel/Me | Them`, `RecordingStatus/Available`, `NudgeType/TalkRatio`. Impossible states unrepresentable; `bend check` catches them.

**`Maybe` over `undefined`** — `Languages/to_api_code` returns `MaybeLanguage/Some | None` instead of `undefined`. Pattern-match forces handling.

**Linear/affine friendly** — `RecordingState/pause` returns a new value; the old one cannot be reused (HVM linearity prevents alias bugs).

---

## Electron Bridge

The Electron main process does not go away — Bend runs as the **compute kernel**. FFI lives in `src/main/services/bend-bridge.ts` (see repo):

```ts
// TypeScript host → Bend HVM (pseudo)
import { hvm } from 'bend-ffi';
const metrics: Metrics = hvm.call('calc_metrics', segments, elapsed_s);
const [newNudgeState, nudge] = hvm.call('NudgeState/evaluate', state, metrics, dur, Date.now());
```

In dev (`bend run`) the LLM/MCP FFI is a stub; in prod the host links `llm_call` / `mcp_call_tool` to `openai` + `MCPClient` (see `Summary.bend` / `MCP.bend` comments).

Build pipeline (proposed, `bend/Makefile`):

```make
cat Types.bend Recording.bend Languages.bend Transcript.bend Metrics.bend Nudge.bend Summary.bend MCP.bend Main.bend > call.bend
bend check call.bend
bend gen-hvm call.bend -o dist/call.hvm
```

---

## Porting Notes

**What is 1:1:**

- Recording limits (including `paused_total_ms`, sleep-excluded semantics)
- 17 transcription languages + `to_api_code` falling back to `None`
- Transcript buffer windowing (`100` active / `200` cap)
- Metrics formulas (identical thresholds: 45s monologue, 0.35-0.55 ideal ratio, 180 WPM pace, 2s gap, interruptions)
- Nudge priorities + 120s cooldown + suppression
- Summary 3-way split (overview / key points / action items) + markdown shape

**What changes:**

- `EventEmitter` → pure values. The host subscribes to HVM results.
- `better-sqlite3` / Drizzle → HVM term storage (for demo, in-memory `List`; prod maps to `Map` builtin → content-addressed)
- `pino` logger → `IO/print` + host logger via FFI
- `setInterval` metric/nudge ticks → host calls `calc_metrics`/`NudgeState/evaluate` on its own timer (pure, testable)
- `safeStorage` / `secure-store` stays in Electron host (Bend never sees secrets)

**Why not 100% Bend:**

UI (React), Electron IPC, capture binary (`videodb` SDK), Calendar OAuth, tRPC/Hono stay in TypeScript — Bend is the **parallel intelligence core**, not a UI framework.

---

## Testing

Bend tests are inline (since Bend lacks a `jest` equivalent) — assert via `bend run`:

```bend
def test_metrics() -> u24:
  segs = demo_segments()
  m = calc_metrics(segs, 60.0)
  # talk ratio ~0.5 on balanced demo
  return if f24/abs(m.talk_ratio.me - 0.5) < 0.2: 1 else: 0

def test_recording() -> u24:
  s = RecordingState/new("s", 1, 0)
  return if RecordingState/should_stop(s, 7200000) == 1: 1 else: 0
```

Run all:

```bash
make -C bend test
```

TypeScript tests are unchanged (`npm test`).

---

## License

MIT — same as [call.md](https://github.com/video-db/call.md).

*Rebuild notes:* Bend 0.2.34, HVM 2.0. Original commit `ba53ebe`. This port is community-maintained and not an official HigherOrderCo release.
