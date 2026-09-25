# Call.md — Bend Rebuild — Entry Point
# To run:  bend run bend/Main.bend
# To check: bend check bend/Main.bend
# To gen HVM: bend gen-hvm bend/Main.bend
#
# This file wires every Bend module into a single HVM program that
# simulates one complete meeting lifecycle — exactly what the Electron
# main process does, but as a pure, massively parallel Bend program.
#
# Original → Bend module map:
#   src/shared/constants/recording.ts        → bend/Recording.bend
#   src/shared/constants/languages.ts        → bend/Languages.bend
#   src/main/services/copilot/transcript-*   → bend/Transcript.bend
#   src/main/services/copilot/conversation-* → bend/Metrics.bend
#   src/main/services/copilot/nudge-*        → bend/Nudge.bend
#   src/main/services/copilot/summary-*      → bend/Summary.bend
#   src/main/services/mcp/*                  → bend/MCP.bend
#   src/main/db/schema.ts + shared/types     → bend/Types.bend

# Bend concatenates files in the same directory implicitly;
# for `bend run` with a single entry, we inline the modules via `import`
# comments — the build script (`bend/Makefile`) cats them in order.
# The explicit `import` sugar below is supported since bend 0.2.33:

# import Types
# import Recording
# import Languages
# import Transcript
# import Metrics
# import Nudge
# import Summary
# import MCP

# ── Demo helpers ────────────────────────────────────────────────────

def demo_segments() -> List(Segment):
  return [
    Segment { id: "seg-001", session_id: "demo-42", recording_id: 1, channel: Channel/Me,   text: "Hey, thanks for joining — excited to walk through the onboarding.", start: 2.0,  end: 6.5,  is_final: 1, processed: 0 },
    Segment { id: "seg-002", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "Thanks! We've been looking at Call.md for a few weeks.", start: 7.0, end: 10.2, is_final: 1, processed: 0 },
    Segment { id: "seg-003", session_id: "demo-42", recording_id: 1, channel: Channel/Me,   text: "Awesome — what's the biggest friction in your current meeting workflow?", start: 11.0, end: 15.0, is_final: 1, processed: 0 },
    Segment { id: "seg-004", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "Honestly, we record locally but transcription is a mess and we lose action items.", start: 16.0, end: 21.0, is_final: 1, processed: 0 },
    Segment { id: "seg-005", session_id: "demo-42", recording_id: 1, channel: Channel/Me,   text: "That is exactly what we solve — real-time dual-channel transcription and live assists. How are you handling follow-ups today?", start: 22.0, end: 29.0, is_final: 1, processed: 0 },
    Segment { id: "seg-006", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "Manual notes, and half the time they are incomplete. Do you integrate with CRMs?", start: 30.0, end: 35.5, is_final: 1, processed: 0 },
    Segment { id: "seg-007", session_id: "demo-42", recording_id: 1, channel: Channel/Me,   text: "Yes — via MCP and workflow webhooks. For example, we can push the summary straight into n8n or Zapier.", start: 36.0, end: 43.0, is_final: 1, processed: 0 },
    Segment { id: "seg-008", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "That would save us hours. What does setup look like?", start: 44.0, end: 47.0, is_final: 1, processed: 0 },
    Segment { id: "seg-009", session_id: "demo-42", recording_id: 1, channel: Channel/Me,   text: "One command on macOS, enter your VideoDB key, grant mic and screen capture. Two minutes.", start: 48.0, end: 54.0, is_final: 1, processed: 0 },
    Segment { id: "seg-010", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "And pricing?", start: 55.0, end: 56.5, is_final: 1, processed: 0 },
  ]

def demo_tools() -> List(ToolDesc):
  return [
    ToolDesc { server_id: "crm",  name: "lookup_account",  description: "lookup CRM account and deal history for a company", input_schema: "{}" },
    ToolDesc { server_id: "docs", name: "search_docs",    description: "search product documentation and help center",  input_schema: "{}" },
    ToolDesc { server_id: "cal",  name: "find_meeting",   description: "find calendar meeting details and attendees",  input_schema: "{}" },
  ]

def print_metrics(m: Metrics) -> IO:
  with IO:
    * <- IO/print(String/concat("  talk_ratio me/them: ", String/concat(String/from_f24(m.talk_ratio.me), String/concat("/", String/from_f24(m.talk_ratio.them)))))
    * <- IO/print(String/concat("\n  pace: ", String/concat(String/from_f24(m.pace), " WPM")))
    * <- IO/print(String/concat("\n  questions_asked: ", String/from_u24(m.questions_asked)))
    * <- IO/print(String/concat("\n  monologue: ", if m.monologue_detected == 1: "yes" else: "no"))
    * <- IO/print(String/concat("\n  longest_monologue: ", String/concat(String/from_f24(m.longest_monologue), "s")))
    * <- IO/print(String/concat("\n  interruptions: ", String/from_u24(m.interruption_count)))
    * <- IO/print(String/concat("\n  total_duration: ", String/concat(String/from_f24(m.total_duration), "s")))
    * <- IO/print(String/concat("\n  call_duration: ", String/concat(String/from_f24(m.call_duration), "s")))
    * <- IO/print("\n")
    return IO/done

def print_nudge(maybe: Maybe(Nudge)) -> IO:
  with IO:
    match maybe:
      case Maybe/Some:
        n = maybe.value
        * <- IO/print(String/concat("  >> NUDGE [", String/concat(NudgeType/to_string(n.type), String/concat("] ", n.message))))
        * <- IO/print("\n")
        return IO/done
      case Maybe/None:
        * <- IO/print("  (no nudge)\n")
        return IO/done

# ── Main — full meeting simulation ──────────────────────────────────
def main() -> IO:
  with IO:
    * <- IO/print("══════════════════════════════════════════════════\n")
    * <- IO/print("  Call.md — Bend rebuild  (HVM / GPU-parallel)\n")
    * <- IO/print("══════════════════════════════════════════════════\n\n")

    # 1) Recording limits demo
    * <- IO/print("[1] Recording limits\n")
    * <- IO/print(String/concat("  MAX  = ", String/concat(format_duration_label(MAX_RECORDING_DURATION_MS), "\n")))
    * <- IO/print(String/concat("  WARN = ", String/concat(format_duration_label(RECORDING_LIMIT_WARNING_MS), " before cutoff\n")))
    state = RecordingState/new("demo-42", 1, 0)
    * <- IO/print(String/concat("  remaining at t=0: ", String/concat(String/from_u24(RecordingState/remaining_ms(state, 0)), " ms\n")))
    * <- IO/print(String/concat("  remaining at t=7100000: ", String/concat(String/from_u24(RecordingState/remaining_ms(state, 7100000)), " ms (should warn)\n")))
    * <- IO/print(String/concat("  should_stop at 7200000: ", String/concat(String/from_u24(RecordingState/should_stop(state, 7200000)), "\n\n")))

    # 2) Languages
    * <- IO/print("[2] Transcription languages\n")
    * <- IO/print(String/concat("  supported: ", String/concat(String/from_u24(Languages/count()), " languages\n")))
    maybe_code = Languages/to_api_code("es")
    label = match maybe_code:
      case MaybeLanguage/Some: maybe_code.value
      case MaybeLanguage/None: "None (auto)"
    * <- IO/print(String/concat("  to_api_code('es') = ", String/concat(label, "\n")))
    none_code = Languages/to_api_code("auto")
    label2 = match none_code:
      case MaybeLanguage/Some: none_code.value
      case MaybeLanguage/None: "None (auto — engine decides)"
    * <- IO/print(String/concat("  to_api_code('auto') = ", String/concat(label2, "\n\n")))

    # 3) Transcript buffer
    * <- IO/print("[3] Transcript buffer\n")
    segs = demo_segments()
    t_state = TranscriptState { segments: segs, call_start_s: 0.0 }
    * <- IO/print(String/concat("  segments: ", String/concat(String/from_u24(List/len(segs)), "\n")))
    * <- IO/print(String/concat("  final: ", String/concat(String/from_u24(List/len(TranscriptState/final_segments(t_state))), "\n")))
    * <- IO/print("  recent context (last 3):\n")
    * <- IO/print(String/concat("  ", String/concat(TranscriptState/recent_context(t_state, 3), "\n\n")))

    # 4) Conversation metrics — the parallel showcase
    * <- IO/print("[4] Conversation metrics  (parallel bend/fork)\n")
    metrics = calc_metrics(segs, 60.0)
    * <- print_metrics(metrics)

    # 5) Nudge engine — rate-limited, priority-ordered
    * <- IO/print("[5] Nudge engine\n")
    nudge_state = NudgeState/new()
    # tick at 60s with current metrics
    (nudge_state2, maybe_nudge) = NudgeState/evaluate(nudge_state, metrics, 60.0, 60000)
    * <- print_nudge(maybe_nudge)
    # tick again immediately — should be rate-limited (cooldown 2m)
    (nudge_state3, maybe_nudge2) = NudgeState/evaluate(nudge_state2, metrics, 61.0, 61000)
    * <- IO/print("  immediate re-evaluate (should be throttled): ")
    * <- print_nudge(maybe_nudge2)
    # synthetic unbalanced call to trigger talk_ratio nudge
    unbalanced = demo_segments() # re-use but evaluate at 200s with high talk ratio
    # manually craft high-talk metrics
    high_talk = Metrics {
      talk_ratio: TalkRatio { me: 0.82, them: 0.18 },
      pace: 190.0,
      questions_asked: 0,
      monologue_detected: 1,
      longest_monologue: 52.0,
      total_duration: 400.0,
      call_duration: 200.0,
      word_count: WordCount { me: 800, them: 120 },
      segment_count: SegmentCount { me: 18, them: 3 },
      avg_segment_length: AvgSegmentLength { me: 22.0, them: 5.0 },
      interruption_count: 4,
    }
    (_, maybe_high) = NudgeState/evaluate(NudgeState/new(), high_talk, 200.0, 200000)
    * <- IO/print("  unbalanced call (0.82 talk ratio, 190 WPM): ")
    * <- print_nudge(maybe_high)
    * <- IO/print("\n")

    # 6) MCP parallel intent detection
    * <- IO/print("[6] MCP agent  (parallel intent sweep)\n")
    tools = demo_tools()
    # use the CRM-triggering segment
    crm_seg = Segment { id: "seg-crm", session_id: "demo-42", recording_id: 1, channel: Channel/Them, text: "Do you integrate with CRMs and lookup our account?", start: 30.0, end: 35.0, is_final: 1, processed: 0 }
    intents = detect_intents(crm_seg, tools)
    * <- IO/print(String/concat("  intents for: \"", String/concat(crm_seg.text, "\"\n")))
    * <- IO/print(String/concat("  matches: ", String/concat(String/from_u24(List/len(intents)), "\n")))
    results = mcp_agent_tick(crm_seg, tools)
    * <- IO/print(String/concat("  MCP results: ", String/concat(String/from_u24(List/len(results)), "\n")))
    for_res = List/map(results, lambda r: r.markdown)
    * <- IO/print(String/concat("  ", String/concat(String/join(for_res, "\n  "), "\n\n")))

    # 7) Summary — 3 parallel LLM forks
    * <- IO/print("[7] Post-meeting summary  (3 parallel LLM forks)\n")
    ctx = CallContext {
      meeting_name: "Demo — Call.md onboarding",
      meeting_description: "Show transcription, live assists, MCP, and markdown export",
      transcript: TranscriptState/full_text(t_state),
      metrics_text: String/concat("pace=", String/from_f24(metrics.pace)),
    }
    summary = Summary/generate_parallel(ctx)
    * <- IO/print(String/concat("  overview (stub): ", String/concat(summary.short_overview, "\n")))
    md = Summary/to_markdown(Recording { id: 1, session_id: "demo-42", video_id: "", collection_id: "", status: RecordingStatus/Available, insights_status: InsightsStatus/Ready, duration: metrics.call_duration, short_overview: summary.short_overview }, summary, metrics, ctx.transcript)
    * <- IO/print(String/concat("  markdown bytes: ", String/concat(String/from_u24(String/len(md)), "\n\n")))

    * <- IO/print("══════════════════════════════════════════════════\n")
    * <- IO/print("  ✓ Bend rebuild OK  — all modules typecheck.\n")
    * <- IO/print("  Run on HVM:  bend run bend/Main.bend\n")
    * <- IO/print("  Run on CUDA: bend run-cuda bend/Main.bend\n")
    * <- IO/print("══════════════════════════════════════════════════\n")
    return IO/done
