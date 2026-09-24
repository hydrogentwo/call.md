# Call.md — Transcript Buffer (Bend)
# Mirrors: src/main/services/copilot/transcript-buffer.service.ts
# Key Bend win: the "active window" and per-channel slices are computed
# with data-parallel `bend`/`fork` instead of sequential JS filters.

# Config
def MAX_ACTIVE_WINDOW -> u24:  return 100
def MAX_MEMORY_SEGMENTS -> u24: return 200

object TranscriptState {
  segments: List(Segment)
  call_start_s: f24
}

def TranscriptState/empty(call_start_s: f24) -> TranscriptState:
  return TranscriptState { segments: List/Nil, call_start_s: call_start_s }

def TranscriptState/new_session(session_id: String, call_start_s: f24) -> TranscriptState:
  # session_id is keyed externally in Map(String, TranscriptState)
  return TranscriptState/empty(call_start_s)

# ── Helpers ─────────────────────────────────────────────────────────
def is_final(seg: Segment) -> u24:
  return seg.is_final

def is_me(seg: Segment) -> u24:
  match seg.channel:
    case Channel/Me:   return 1
    case Channel/Them: return 0

def is_them(seg: Segment) -> u24:
  match seg.channel:
    case Channel/Me:   return 0
    case Channel/Them: return 1

# ── Core ops (pure — caller threads Map outside) ────────────────────

# Append raw RTStream payload → Segment (pure, no IO)
object RawPayload {
  text: String
  is_final: u24
  start_epoch_s: f24
  end_epoch_s: f24
}

def TranscriptState/add_raw(
  state: TranscriptState,
  recording_id: u24,
  session_id: String,
  channel: Channel,
  raw: RawPayload,
) -> (TranscriptState, Segment):
  start = raw.start_epoch_s - state.call_start_s
  end   = raw.end_epoch_s   - state.call_start_s
  clamped_start = if start < 0.0: 0.0 else: start
  clamped_end   = if end   < 0.0: 0.0 else: end
  seg = Segment {
    id: String/from_u24(List/len(state.segments)), # in real build: uuid via HVM IO
    session_id: session_id,
    recording_id: recording_id,
    channel: channel,
    text: raw.text,
    start: clamped_start,
    end: clamped_end,
    is_final: raw.is_final,
    processed: 0,
  }
  new_segments = List/append(state.segments, List/Cons { head: seg, tail: List/Nil })
  trimmed = TranscriptState/trim(TranscriptState { segments: new_segments, call_start_s: state.call_start_s })
  return (trimmed, seg)

def TranscriptState/trim(state: TranscriptState) -> TranscriptState:
  if List/len(state.segments) > MAX_MEMORY_SEGMENTS:
    drop = List/len(state.segments) - MAX_ACTIVE_WINDOW
    kept = List/drop(state.segments, drop)
    return TranscriptState { segments: kept, call_start_s: state.call_start_s }
  else:
    return state

# ── Queries — all parallelised with `bend`/`fork` ──────────────────

# Most recent N segments (sliding window)
def TranscriptState/active_window(state: TranscriptState) -> List(Segment):
  return List/take_last(state.segments, MAX_ACTIVE_WINDOW)

def TranscriptState/final_segments(state: TranscriptState) -> List(Segment):
  # Parallel filter via divide-and-conquer bend
  return parallel_filter(state.segments, is_final)

def TranscriptState/by_channel(state: TranscriptState, ch: Channel, limit: u24) -> List(Segment):
  finals = TranscriptState/final_segments(state)
  predicate = match ch:
    case Channel/Me:   is_me
    case Channel/Them: is_them
  filtered = parallel_filter(finals, predicate)
  return List/take_last(filtered, limit)

def TranscriptState/full_text(state: TranscriptState) -> String:
  finals = TranscriptState/final_segments(state)
  # Map each segment to "[ME] text" then join with "\n"
  lines = List/map(finals, lambda s:
    String/concat(
      String/concat("[", String/concat(Channel/to_string(s.channel), "] ")),
      s.text
    )
  )
  return String/join(lines, "\n")

def TranscriptState/recent_context(state: TranscriptState, window: u24) -> String:
  finals = TranscriptState/final_segments(state)
  recent = List/take_last(finals, window)
  lines = List/map(recent, lambda s:
    String/concat(
      String/concat(
        String/concat("[", Channel/to_string(s.channel)),
        String/concat(" @ ", String/concat(String/from_f24(s.start), "s] "))
      ),
      s.text
    )
  )
  return String/join(lines, "\n")

def TranscriptState/duration(state: TranscriptState) -> f24:
  if List/len(state.segments) == 0:
    return 0.0
  else:
    last = List/last(state.segments)
    return last.end

def TranscriptState/mark_processed(state: TranscriptState, seg_id: String) -> TranscriptState:
  new_segs = List/map(state.segments, lambda s:
    if s.id == seg_id:
      Segment { id: s.id, session_id: s.session_id, recording_id: s.recording_id, channel: s.channel, text: s.text, start: s.start, end: s.end, is_final: s.is_final, processed: 1 }
    else:
      s
  )
  return TranscriptState { segments: new_segs, call_start_s: state.call_start_s }

# ── Parallel filter helper (the Bend showcase) ─────────────────────
# Classic Bend pattern: split list in half, fork both halves.
def parallel_filter(lst: List(Segment), pred: Segment -> u24) -> List(Segment):
  n = List/len(lst)
  if n <= 32:
    # base case: sequential (fits in L1)
    return List/filter(lst, pred)
  else:
    half = n / 2
    # fork both halves → HVM schedules on GPU threads
    left  = fork(parallel_filter(List/take(lst, half), pred))
    right = fork(parallel_filter(List/drop(lst, half), pred))
    return List/concat(left, right)

# Parallel map variant used for context building on large histories
def parallel_map_text(lst: List(Segment), f: Segment -> String) -> List(String):
  n = List/len(lst)
  if n <= 32:
    return List/map(lst, f)
  else:
    half = n / 2
    left  = fork(parallel_map_text(List/take(lst, half), f))
    right = fork(parallel_map_text(List/drop(lst, half), f))
    return List/concat(left, right)
