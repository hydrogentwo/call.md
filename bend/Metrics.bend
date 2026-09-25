# Call.md — Conversation Metrics (Bend)
# Mirrors: src/main/services/copilot/conversation-metrics.service.ts
#
# This is the flagship parallel module. In TypeScript the metrics are
# computed sequentially (reduce over meSegments, then themSegments).
# In Bend every reduction is a `bend` tree; HVM fuses them and the GPU
# evaluates me/them/pace/interruptions simultaneously.
#
# Pure functions only — no logger, no Map mutation.

# ── Thresholds ──────────────────────────────────────────────────────
def MONOLOGUE_THRESHOLD_S -> f24: return 45.0
def IDEAL_RATIO_MIN -> f24:       return 0.35
def IDEAL_RATIO_MAX -> f24:       return 0.55
def GAP_CONTINUOUS_S -> f24:      return 2.0

# ── Primitive reducers (all fold-parallel) ──────────────────────────

def sum_duration(segs: List(Segment)) -> f24:
  # fold-parallel sum via bend
  bend acc = 0.0 with lst = segs:
    when lst != List/Nil:
      match lst:
        case List/Cons:
          # fork tail to keep tree balanced
          head_dur = fork(Segment/duration(lst.head))
          tail_sum = fork(sum_duration(lst.tail))
          acc = head_dur + tail_sum
        case List/Nil:
          acc = 0.0
    else:
      acc = 0.0
  return acc

def count_words(segs: List(Segment)) -> u24:
  bend acc = 0 with lst = segs:
    when lst != List/Nil:
      match lst:
        case List/Cons:
          head_wc = fork(Segment/word_count(lst.head))
          tail_wc = fork(count_words(lst.tail))
          acc = head_wc + tail_wc
        case List/Nil:
          acc = 0
    else:
      acc = 0
  return acc

def count_questions(segs: List(Segment)) -> u24:
  bend acc = 0 with lst = segs:
    when lst != List/Nil:
      match lst:
        case List/Cons:
          head_q = fork(if Segment/is_question(lst.head) == 1: 1 else: 0)
          tail_q = fork(count_questions(lst.tail))
          acc = head_q + tail_q
        case List/Nil:
          acc = 0
    else:
      acc = 0
  return acc

# ── Pace (WPM for "me") ─────────────────────────────────────────────
def calc_pace(me_segs: List(Segment), call_duration_s: f24) -> f24:
  n = List/len(me_segs)
  if n == 0:
    return 0.0
  else:
    total_words = count_words(me_segs) as f24
    if total_words == 0.0:
      return 0.0
    else:
      first = List/first(me_segs)
      last  = List/last(me_segs)
      span_s = last.end - first.start
      if span_s > 5.0:
        minutes = span_s / 60.0
        raw_wpm = total_words / minutes
        # clamp 0..250 like TS
        return f24/clamp(raw_wpm, 0.0, 250.0)
      else:
        if call_duration_s > 5.0:
          minutes2 = call_duration_s / 60.0
          raw2 = total_words / minutes2
          return f24/clamp(raw2, 0.0, 250.0)
        else:
          return 0.0

# ── Monologue detection ─────────────────────────────────────────────
def detect_monologue(me_segs: List(Segment)) -> u24:
  n = List/len(me_segs)
  if n < 3:
    return 0
  else:
    recent = List/take_last(me_segs, 5)
    if List/len(recent) < 3:
      return 0
    else:
      first = List/first(recent)
      last  = List/last(recent)
      span = last.end - first.start
      return if span > MONOLOGUE_THRESHOLD_S: 1 else: 0

def longest_monologue(me_segs: List(Segment)) -> f24:
  # O(n) scan but written as bend-friendly tail recursion
  def loop(lst: List(Segment), cur_start: f24, cur_end: f24, best: f24) -> f24:
    match lst:
      case List/Nil:
        # close final streak
        cur_len = if cur_start < 0.0: 0.0 else: cur_end - cur_start
        return if cur_len > best: cur_len else: best
      case List/Cons:
        seg = lst.head
        if cur_start < 0.0:
          # first element
          return loop(lst.tail, seg.start, seg.end, best)
        else:
          gap = seg.start - cur_end
          if gap < GAP_CONTINUOUS_S:
            # continue streak
            return loop(lst.tail, cur_start, seg.end, best)
          else:
            # break streak
            cur_len = cur_end - cur_start
            new_best = if cur_len > best: cur_len else: best
            return loop(lst.tail, seg.start, seg.end, new_best)
  return loop(me_segs, -1.0, -1.0, 0.0)

# ── Interruptions ───────────────────────────────────────────────────
def count_interruptions(all_segs: List(Segment)) -> u24:
  n = List/len(all_segs)
  if n < 2:
    return 0
  else:
    sorted = List/sort_by(all_segs, lambda s: s.start)
    def scan(lst: List(Segment), prev: Segment, acc: u24) -> u24:
      match lst:
        case List/Nil:
          return acc
        case List/Cons:
          cur = lst.head
          overlap = if cur.start < prev.end and cur.channel != prev.channel: 1 else: 0
          return scan(lst.tail, cur, acc + overlap)
    first = List/first(sorted)
    rest  = List/drop(sorted, 1)
    return scan(rest, first, 0)

# ── Main metrics (parallel) ─────────────────────────────────────────
def calc_metrics(segments: List(Segment), elapsed_s: f24) -> Metrics:
  # 1) split in parallel
  me_segs   = fork(parallel_filter(segments, lambda s: s.is_final == 1 and is_me(s) == 1))
  them_segs = fork(parallel_filter(segments, lambda s: s.is_final == 1 and is_them(s) == 1))

  # 2) durations + word counts in parallel (4 forks)
  me_dur   = fork(sum_duration(me_segs))
  them_dur = fork(sum_duration(them_segs))
  me_wc    = fork(count_words(me_segs))
  them_wc  = fork(count_words(them_segs))

  # 3) derived scalars
  total_dur = me_dur + them_dur
  # call duration = max segment end vs elapsed_s
  max_end = if List/len(segments) == 0: 0.0 else: List/fold(segments, 0.0, lambda acc s: if s.end > acc: s.end else: acc)
  call_dur = if max_end > elapsed_s: max_end else: elapsed_s

  talk_me   = if total_dur > 0.0: me_dur / total_dur else: 0.5
  talk_them = if total_dur > 0.0: them_dur / total_dur else: 0.5

  pace          = fork(calc_pace(me_segs, call_dur))
  questions     = fork(count_questions(me_segs))
  mono_flag     = fork(detect_monologue(me_segs))
  longest_mono  = fork(longest_monologue(me_segs))
  interrupts    = fork(count_interruptions(segments))

  me_cnt   = List/len(me_segs)
  them_cnt = List/len(them_segs)

  avg_me   = if me_cnt > 0: me_dur / (me_cnt as f24) else: 0.0
  avg_them = if them_cnt > 0: them_dur / (them_cnt as f24) else: 0.0

  return Metrics {
    talk_ratio: TalkRatio { me: talk_me, them: talk_them },
    pace: pace,
    questions_asked: questions,
    monologue_detected: mono_flag,
    longest_monologue: longest_mono,
    total_duration: total_dur,
    call_duration: call_dur,
    word_count: WordCount { me: me_wc, them: them_wc },
    segment_count: SegmentCount { me: me_cnt, them: them_cnt },
    avg_segment_length: AvgSegmentLength { me: avg_me, them: avg_them },
    interruption_count: interrupts,
  }

# ── Trend (compares two snapshots) ──────────────────────────────────
type TrendDir:
  Improving
  Stable
  Declining

type PaceTrend:
  Faster
  Stable
  Slower

object MetricsTrend {
  current: Metrics
  previous: Maybe(Metrics)
  talk_trend: TrendDir
  pace_trend: PaceTrend
}

def talk_trend(cur: Metrics, prev: Metrics) -> TrendDir:
  cur_bal  = f24/abs(cur.talk_ratio.me - 0.5)
  prev_bal = f24/abs(prev.talk_ratio.me - 0.5)
  if cur_bal < prev_bal - 0.05:
    return TrendDir/Improving
  else:
    if cur_bal > prev_bal + 0.05:
      return TrendDir/Declining
    else:
      return TrendDir/Stable

def pace_trend(cur: Metrics, prev: Metrics) -> PaceTrend:
  if cur.pace > prev.pace + 10.0:
    return PaceTrend/Faster
  else:
    if cur.pace < prev.pace - 10.0:
      return PaceTrend/Slower
    else:
      return PaceTrend/Stable
