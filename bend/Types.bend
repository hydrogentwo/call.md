# Call.md — Core Types (Bend)
# Mirrors: src/shared/types/*, src/shared/schemas/*, src/main/db/schema.ts
# In Bend every ADT is a first-class HVM constructor → massive parallelism for free.

# ── Channels (dual-channel transcription: you vs them) ──────────────
type Channel:
  Me
  Them

def Channel/to_string(ch: Channel) -> String:
  match ch:
    case Channel/Me:
      return "me"
    case Channel/Them:
      return "them"

def Channel/from_string(s: String) -> Channel:
  if s == "me":
    return Channel/Me
  else:
    return Channel/Them

# ── Segment (mirrors TranscriptSegmentData) ─────────────────────────
object Segment {
  id: String
  session_id: String
  recording_id: u24
  channel: Channel
  text: String
  start: f24    # seconds from call start
  end: f24
  is_final: u24 # 0/1  (Bend Bool is explicit; use u24 for storage compat)
  processed: u24
}

def Segment/duration(seg: Segment) -> f24:
  return seg.end - seg.start

def Segment/word_count(seg: Segment) -> u24:
  # Bend strings: word count via split approximation
  # For HVM efficiency we count spaces + 1 if non-empty
  trimmed = String/trim(seg.text)
  if String/len(trimmed) == 0:
    return 0
  else:
    spaces = String/count_char(trimmed, ' ')
    return spaces + 1

def Segment/is_question(seg: Segment) -> u24:
  return String/contains(seg.text, "?")

# ── Recording status (mirrors recording.schema.ts) ──────────────────
type RecordingStatus:
  Recording
  Processing
  Available
  Failed

type InsightsStatus:
  Pending
  Processing
  Ready
  Failed

object Recording {
  id: u24
  session_id: String
  video_id: String
  collection_id: String
  status: RecordingStatus
  insights_status: InsightsStatus
  duration: f24
  short_overview: String
}

# ── Metrics snapshot (mirrors MetricsSnapshotSchema) ────────────────
object TalkRatio {
  me: f24
  them: f24
}

object WordCount {
  me: u24
  them: u24
}

object SegmentCount {
  me: u24
  them: u24
}

object AvgSegmentLength {
  me: f24
  them: f24
}

object Metrics {
  talk_ratio: TalkRatio
  pace: f24              # WPM for "me"
  questions_asked: u24
  monologue_detected: u24
  longest_monologue: f24
  total_duration: f24
  call_duration: f24
  word_count: WordCount
  segment_count: SegmentCount
  avg_segment_length: AvgSegmentLength
  interruption_count: u24
}

# ── Nudge (mirrors nudge-engine.service.ts) ─────────────────────────
type NudgeType:
  TalkRatio
  NextSteps
  Questions
  Pace
  Monologue

type NudgeSeverity:
  Low
  Medium
  High

object Nudge {
  id: String
  type: NudgeType
  message: String
  severity: NudgeSeverity
  dismissible: u24
  timestamp: u24
}

# ── Bookmark ────────────────────────────────────────────────────────
type BookmarkCategory:
  Important
  FollowUp
  Pricing
  Competitor
  Risk
  Decision
  ActionItem

object Bookmark {
  id: String
  recording_id: u24
  timestamp: f24
  category: BookmarkCategory
  note: String
}

# ── Key points / summary (mirrors summary-generator) ────────────────
object KeyPoint {
  topic: String
  points: List(String)
}

object Summary {
  short_overview: String
  key_points: List(KeyPoint)
  action_items: List(String)
}

# ── MCP ─────────────────────────────────────────────────────────────
type MCPTransport:
  Stdio
  Http

type MCPStatus:
  Disconnected
  Connecting
  Connected
  Error

object MCPServer {
  id: String
  name: String
  transport: MCPTransport
  status: MCPStatus
  url: String
}

object MCPToolCall {
  id: String
  server_id: String
  tool_name: String
  status: String
  duration_ms: u24
}

# ── Utility constructors ────────────────────────────────────────────
def Metrics/empty() -> Metrics:
  return Metrics {
    talk_ratio: TalkRatio { me: 0.5, them: 0.5 },
    pace: 0.0,
    questions_asked: 0,
    monologue_detected: 0,
    longest_monologue: 0.0,
    total_duration: 0.0,
    call_duration: 0.0,
    word_count: WordCount { me: 0, them: 0 },
    segment_count: SegmentCount { me: 0, them: 0 },
    avg_segment_length: AvgSegmentLength { me: 0.0, them: 0.0 },
    interruption_count: 0,
  }
