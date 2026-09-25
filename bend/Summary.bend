# Call.md — Summary Generator (Bend)
# Mirrors: src/main/services/copilot/summary-generator.service.ts
#          src/main/services/llm.service.ts (OpenAI via VideoDB)
# In Bend the 3 parallel extractions become 3 HVM forks; prompt assembly
# is a pure bend over the transcript window.

object CallContext {
  meeting_name: String
  meeting_description: String
  transcript: String
  metrics_text: String
}

# Prompt builders (mirrors SYSTEM_PROMPT assembly in TS)
def Summary/prompt_overview(ctx: CallContext) -> String:
  return String/join([
    "You are a meeting summarizer. Generate a concise narrative overview.",
    String/concat("MEETING: ", ctx.meeting_name),
    String/concat("GOAL: ", ctx.meeting_description),
    "TRANSCRIPT:",
    ctx.transcript,
    "Produce 3-5 sentences, neutral tone, no preamble."
  ], "\n\n")

def Summary/prompt_key_points(ctx: CallContext) -> String:
  return String/join([
    "Extract key points by topic, attributed to participants.",
    String/concat("MEETING: ", ctx.meeting_name),
    "TRANSCRIPT:",
    ctx.transcript,
    "Return JSON: [{topic, points: string[]}]"
  ], "\n\n")

def Summary/prompt_action_items(ctx: CallContext) -> String:
  return String/join([
    "Extract concrete next steps / action items with owners if mentioned.",
    "TRANSCRIPT:",
    ctx.transcript,
    "Return JSON: [string]"
  ], "\n\n")

# In a real HVM build these would be FFI calls to the VideoDB LLM endpoint.
# Here we model them as pure forked tasks so Bend parallelises correctly;
# the Electron bridge (src/bend-bridge.ts) replaces `llm_call` with the
# OpenAI-compatible HTTP call at link time.

# Stub that the HVM runtime replaces via FFI — keep pure for `bend check`
def llm_call(prompt: String) -> String:
  # Placeholder: in `bend run --ffi` this is linked to Rust/JS HTTP.
  # For `bend check` it just echoes length so types stay total.
  return String/concat("[LLM STUB ", String/concat(String/from_u24(String/len(prompt)), "]"))

# Parallel 3-way generation (the Bend showcase for post-meeting intelligence)
def Summary/generate_parallel(ctx: CallContext) -> Summary:
  p_overview = fork(Summary/prompt_overview(ctx))
  p_keypts   = fork(Summary/prompt_key_points(ctx))
  p_actions  = fork(Summary/prompt_action_items(ctx))

  # Three LLM forks execute concurrently on HVM (GPU threads)
  raw_overview = fork(llm_call(p_overview))
  raw_keypts   = fork(llm_call(p_keypts))
  raw_actions  = fork(llm_call(p_actions))

  # In prod: JSON parse raw_keypts / raw_actions; here stub wraps
  return Summary {
    short_overview: raw_overview,
    key_points: List/Nil,   # parsed from raw_keypts in real build
    action_items: List/Nil, # parsed from raw_actions in real build
  }

# Sequential fallback (for comparison in tests)
def Summary/generate_sequential(ctx: CallContext) -> Summary:
  overview = llm_call(Summary/prompt_overview(ctx))
  keypts_s = llm_call(Summary/prompt_key_points(ctx))
  actions_s= llm_call(Summary/prompt_action_items(ctx))
  return Summary { short_overview: overview, key_points: List/Nil, action_items: List/Nil }

# ── Markdown export (mirrors markdown-export.service.ts) ────────────
def Summary/to_markdown(rec: Recording, summary: Summary, metrics: Metrics, transcript_text: String) -> String:
  header = String/concat("# ", rec.session_id)
  meta   = String/join([
    String/concat("- Duration: ", String/from_f24(metrics.call_duration)),
    String/concat("- Talk ratio (you): ", String/from_f24(metrics.talk_ratio.me)),
    String/concat("- Pace: ", String/concat(String/from_f24(metrics.pace), " WPM")),
    String/concat("- Questions: ", String/from_u24(metrics.questions_asked)),
  ], "\n")
  body = String/join([
    header,
    meta,
    "## Overview",
    summary.short_overview,
    "## Key Points",
    String/join(List/map(summary.key_points, lambda kp: String/concat(String/concat("### ", kp.topic), String/concat("\n", String/join(kp.points, "\n- ")))), "\n\n"),
    "## Action Items",
    String/join(summary.action_items, "\n- "),
    "## Transcript",
    transcript_text,
  ], "\n\n")
  return body
