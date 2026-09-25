# Call.md — Nudge Engine (Bend)
# Mirrors: src/main/services/copilot/nudge-engine.service.ts
# Rate-limited, priority-ordered, pure. Time is explicit `now_ms`.

object NudgeConfig {
  enabled: u24
  cooldown_ms: u24
  suppressed_talk_ratio: u24
  suppressed_next_steps: u24
  suppressed_questions: u24
  suppressed_pace: u24
}

def NudgeConfig/default() -> NudgeConfig:
  return NudgeConfig {
    enabled: 1,
    cooldown_ms: 120000,
    suppressed_talk_ratio: 0,
    suppressed_next_steps: 0,
    suppressed_questions: 0,
    suppressed_pace: 0,
  }

object NudgeState {
  last_nudge_ms: u24
  history: List(Nudge)
  config: NudgeConfig
}

def NudgeState/new() -> NudgeState:
  return NudgeState { last_nudge_ms: 0, history: List/Nil, config: NudgeConfig/default() }

# ── Templates (mirrors NUDGE_TEMPLATES) ─────────────────────────────
def nudge_template_talk_ratio(idx: u24) -> (String, NudgeSeverity):
  if idx == 1:
    return ("You've been driving most of the conversation so far", NudgeSeverity/Medium)
  else:
    return ("Talk ratio is leaning towards you — balance with more listening", NudgeSeverity/Low)

def nudge_template_questions() -> (String, NudgeSeverity):
  return ("Few questions asked so far — discovery helps uncover needs", NudgeSeverity/Low)

def nudge_template_pace() -> (String, NudgeSeverity):
  return ("Speaking pace is on the faster side — slowing down can help clarity", NudgeSeverity/Low)

def nudge_template_next_steps(idx: u24) -> (String, NudgeSeverity):
  if idx == 1:
    return ("Good time to discuss action items and timeline", NudgeSeverity/Low)
  else:
    return ("Consider confirming next steps before ending the call", NudgeSeverity/Medium)

# Build Nudge from type + variant
def make_nudge(ty: NudgeType, idx: u24, now_ms: u24) -> Nudge:
  (msg, sev) = match ty:
    case NudgeType/TalkRatio: nudge_template_talk_ratio(idx)
    case NudgeType/Questions: nudge_template_questions()
    case NudgeType/Pace:      nudge_template_pace()
    case NudgeType/NextSteps: nudge_template_next_steps(idx)
    case NudgeType/Monologue: ("You've been speaking for a while — try pausing for input", NudgeSeverity/Medium)
  return Nudge {
    id: String/concat("nudge-", String/from_u24(now_ms)),
    type: ty,
    message: msg,
    severity: sev,
    dismissible: 1,
    timestamp: now_ms,
  }

# ── Priority checks (pure, in order) ────────────────────────────────
def check_talk_ratio(m: Metrics) -> Maybe(NudgeType):
  if m.total_duration < 60.0:
    return Maybe/None
  else:
    if m.talk_ratio.me > 0.75:
      return Maybe/Some { value: NudgeType/TalkRatio }
    else:
      if m.talk_ratio.me > 0.65:
        return Maybe/Some { value: NudgeType/TalkRatio }
      else:
        return Maybe/None

def check_questions(m: Metrics, call_dur_s: f24) -> Maybe(NudgeType):
  if call_dur_s < 180.0:
    return Maybe/None
  else:
    expected = call_dur_s / 120.0
    if (m.questions_asked as f24) < expected * 0.5:
      return Maybe/Some { value: NudgeType/Questions }
    else:
      return Maybe/None

def check_pace(m: Metrics) -> Maybe(NudgeType):
  if m.pace > 180.0:
    return Maybe/Some { value: NudgeType/Pace }
  else:
    return Maybe/None

def check_next_steps(call_dur_s: f24) -> Maybe(NudgeType):
  # mirrors TS: 20min window (1200..1230) and 30min window
  if call_dur_s > 1200.0 and call_dur_s < 1230.0:
    return Maybe/Some { value: NudgeType/NextSteps }
  else:
    if call_dur_s > 1800.0 and call_dur_s < 1830.0:
      return Maybe/Some { value: NudgeType/NextSteps }
    else:
      return Maybe/None

def is_suppressed(cfg: NudgeConfig, ty: NudgeType) -> u24:
  match ty:
    case NudgeType/TalkRatio: return cfg.suppressed_talk_ratio
    case NudgeType/NextSteps: return cfg.suppressed_next_steps
    case NudgeType/Questions: return cfg.suppressed_questions
    case NudgeType/Pace:      return cfg.suppressed_pace
    case NudgeType/Monologue: return 0

# ── Public: evaluate (pure, returns updated state + Maybe Nudge) ────
def NudgeState/evaluate(state: NudgeState, m: Metrics, call_dur_s: f24, now_ms: u24) -> (NudgeState, Maybe(Nudge)):
  if state.config.enabled == 0:
    return (state, Maybe/None)
  else:
    if now_ms - state.last_nudge_ms < state.config.cooldown_ms and state.last_nudge_ms != 0:
      return (state, Maybe/None)
    else:
      # priority order: talk_ratio > questions > pace > next_steps
      # parallel pre-compute all checks (HVM will speculatively evaluate)
      cand_talk  = fork(check_talk_ratio(m))
      cand_q     = fork(check_questions(m, call_dur_s))
      cand_pace  = fork(check_pace(m))
      cand_next  = fork(check_next_steps(call_dur_s))

      chosen = match cand_talk:
        case Maybe/Some: cand_talk
        case Maybe/None:
          match cand_q:
            case Maybe/Some: cand_q
            case Maybe/None:
              match cand_pace:
                case Maybe/Some: cand_pace
                case Maybe/None: cand_next

      match chosen:
        case Maybe/None:
          return (state, Maybe/None)
        case Maybe/Some:
          ty = chosen.value
          if is_suppressed(state.config, ty) == 1:
            return (state, Maybe/None)
          else:
            # talk_ratio severity depends on threshold
            idx = if ty == NudgeType/TalkRatio and m.talk_ratio.me > 0.75: 1 else: 0
            nudge = make_nudge(ty, idx, now_ms)
            new_state = NudgeState {
              last_nudge_ms: now_ms,
              history: List/append(state.history, List/Cons { head: nudge, tail: List/Nil }),
              config: state.config,
            }
            return (new_state, Maybe/Some { value: nudge })
