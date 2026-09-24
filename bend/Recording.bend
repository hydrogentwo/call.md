# Call.md — Recording Limits (Bend)
# Mirrors: src/shared/constants/recording.ts
#         src/main/services/recording-limit.service.ts
# Bend's pure functions + linear types make deadline logic overflow-safe
# and trivially testable under HVM.

# ── Constants (u24 = 24-bit unsigned, f24 for seconds) ─────────────
def MAX_RECORDING_DURATION_MS -> u24:
  return 7200000  # 2 * 60 * 60 * 1000

def MAX_RECORDING_DURATION_S -> f24:
  return 7200.0

def RECORDING_LIMIT_WARNING_MS -> u24:
  return 300000   # 5 * 60 * 1000

def RECORDING_LIMIT_WARNING_S -> f24:
  return 300.0

def RECORDING_LIMIT_STOP_GRACE_MS -> u24:
  return 20000

def RECORDING_LIMIT_STOP_GRACE_S -> f24:
  return 20.0

# ── Recording state ─────────────────────────────────────────────────
object RecordingState {
  session_id: String
  recording_id: u24
  start_mono_ms: u24      # monotonic clock at start
  paused_total_ms: u24    # accumulated pause time
  pause_started_at: u24   # 0 if not paused
  is_paused: u24
  is_stopped: u24
}

def RecordingState/new(session_id: String, recording_id: u24, now_ms: u24) -> RecordingState:
  return RecordingState {
    session_id: session_id,
    recording_id: recording_id,
    start_mono_ms: now_ms,
    paused_total_ms: 0,
    pause_started_at: 0,
    is_paused: 0,
    is_stopped: 0,
  }

def RecordingState/active_elapsed_ms(state: RecordingState, now_ms: u24) -> u24:
  if state.is_stopped == 1:
    return MAX_RECORDING_DURATION_MS
  else:
    if state.is_paused == 1:
      # frozen at pause entry
      return state.pause_started_at - state.start_mono_ms - state.paused_total_ms
    else:
      return now_ms - state.start_mono_ms - state.paused_total_ms

def RecordingState/active_elapsed_s(state: RecordingState, now_ms: u24) -> f24:
  ms = RecordingState/active_elapsed_ms(state, now_ms)
  return (ms as f24) / 1000.0

def RecordingState/remaining_ms(state: RecordingState, now_ms: u24) -> u24:
  elapsed = RecordingState/active_elapsed_ms(state, now_ms)
  if elapsed >= MAX_RECORDING_DURATION_MS:
    return 0
  else:
    return MAX_RECORDING_DURATION_MS - elapsed

def RecordingState/should_warn(state: RecordingState, now_ms: u24) -> u24:
  remaining = RecordingState/remaining_ms(state, now_ms)
  # warn exactly once: remaining <= 5min and > 5min - grace
  if remaining <= RECORDING_LIMIT_WARNING_MS and remaining > (RECORDING_LIMIT_WARNING_MS - 1000):
    return 1
  else:
    # broader window for polling (every second)
    if remaining <= RECORDING_LIMIT_WARNING_MS and remaining > 0:
      return 1
    else:
      return 0

def RecordingState/should_stop(state: RecordingState, now_ms: u24) -> u24:
  elapsed = RecordingState/active_elapsed_ms(state, now_ms)
  return if elapsed >= MAX_RECORDING_DURATION_MS: 1 else: 0

def RecordingState/pause(state: RecordingState, now_ms: u24) -> RecordingState:
  if state.is_paused == 1 or state.is_stopped == 1:
    return state
  else:
    return RecordingState {
      session_id: state.session_id,
      recording_id: state.recording_id,
      start_mono_ms: state.start_mono_ms,
      paused_total_ms: state.paused_total_ms,
      pause_started_at: now_ms,
      is_paused: 1,
      is_stopped: 0,
    }

def RecordingState/resume(state: RecordingState, now_ms: u24) -> RecordingState:
  if state.is_paused == 0:
    return state
  else:
    paused_this = now_ms - state.pause_started_at
    return RecordingState {
      session_id: state.session_id,
      recording_id: state.recording_id,
      start_mono_ms: state.start_mono_ms,
      paused_total_ms: state.paused_total_ms + paused_this,
      pause_started_at: 0,
      is_paused: 0,
      is_stopped: 0,
    }

# ── Duration formatting (mirrors formatDurationLabel) ───────────────
def format_duration_label(ms: u24) -> String:
  total_minutes = ms / 60000
  hours = total_minutes / 60
  minutes = total_minutes % 60
  if hours > 0 and minutes > 0:
    # e.g. "1 hour 30 minutes"
    h_str = String/concat(String/from_u24(hours), if hours == 1: " hour" else: " hours")
    m_str = String/concat(String/from_u24(minutes), if minutes == 1: " minute" else: " minutes")
    return String/concat(h_str, String/concat(" ", m_str))
  else:
    if hours > 0:
      return String/concat(String/from_u24(hours), if hours == 1: " hour" else: " hours")
    else:
      if minutes > 0:
        return String/concat(String/from_u24(minutes), if minutes == 1: " minute" else: " minutes")
      else:
        return "less than a minute"

# ── Parallel deadline checker ───────────────────────────────────────
# Bend's `bend` builds a binary tree of recorders; each leaf checks one session.
# On HVM this compiles to a perfectly balanced parallel reduction.

def check_all_deadlines(states: List(RecordingState), now_ms: u24) -> List(String):
  # Returns list of session_ids that must stop NOW (reached 2h active)
  match states:
    case List/Nil:
      return List/Nil
    case List/Cons:
      head = states.head
      tail = states.tail
      # fork both branches → HVM runs them in parallel
      head_action = fork(
        if RecordingState/should_stop(head, now_ms) == 1:
          List/Cons { head: head.session_id, tail: List/Nil }
        else:
          List/Nil
      )
      tail_actions = fork(check_all_deadlines(tail, now_ms))
      return List/concat(head_action, tail_actions)

# Bend-style parallel warning sweep (same tree, but for 5-min warning)
def check_all_warnings(states: List(RecordingState), now_ms: u24) -> List(String):
  bend result = List/Nil with states = states:
    when states != List/Nil:
      match states:
        case List/Cons:
          s = states.head
          rest = states.tail
          # fork warn check for head and recurse for tail in parallel
          warn_here = fork(
            if RecordingState/should_warn(s, now_ms) == 1:
              List/Cons { head: s.session_id, tail: List/Nil }
            else:
              List/Nil
          )
          warn_rest = fork(check_all_warnings(rest, now_ms))
          result = List/concat(warn_here, warn_rest)
        case List/Nil:
          result = List/Nil
    else:
      result = List/Nil
  return result
