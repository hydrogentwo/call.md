# Call.md — MCP Orchestration (Bend)
# Mirrors: src/main/services/mcp/*
#   connection-orchestrator, connection-registry, health-monitor,
#   intent-detector, tool-aggregator, result-handler, mcp-agent
#
# Bend's `bend` + `fork` shines for MCP: intent detection fans out
# over every tool description in parallel; tool calls fan out over
# every candidate server.

object ToolDesc {
  server_id: String
  name: String
  description: String
  input_schema: String
}

object IntentMatch {
  tool: ToolDesc
  confidence: f24
  reason: String
}

# ── Intent detection (parallel over all tools) ──────────────────────
def keyword_score(text: String, desc: String) -> f24:
  # naive Jaccard on whitespace tokens — runs on HVM in parallel per tool
  t_tokens = String/split(String/lowercase(text), " ")
  d_tokens = String/split(String/lowercase(desc), " ")
  overlap  = List/count_if(t_tokens, lambda tok: List/contains(d_tokens, tok))
  denom    = List/len(t_tokens) + List/len(d_tokens)
  if denom == 0:
    return 0.0
  else:
    return (overlap as f24) * 2.0 / (denom as f24)

def score_one_tool(segment: Segment, tool: ToolDesc) -> Maybe(IntentMatch):
  s = keyword_score(segment.text, tool.description)
  if s > 0.25:
    return Maybe/Some { value: IntentMatch { tool: tool, confidence: s, reason: "keyword overlap" } }
  else:
    return Maybe/None

# Parallel intent sweep: every tool scored concurrently (HVM tree)
def detect_intents(segment: Segment, tools: List(ToolDesc)) -> List(IntentMatch):
  n = List/len(tools)
  if n == 0:
    return List/Nil
  else:
    if n <= 16:
      # leaf: sequential scan
      return List/filter_map(tools, lambda t: score_one_tool(segment, t))
    else:
      half = n / 2
      left  = fork(detect_intents(segment, List/take(tools, half)))
      right = fork(detect_intents(segment, List/drop(tools, half)))
      combined = List/concat(left, right)
      # sort by confidence descending, keep top 3
      sorted = List/sort_by(combined, lambda m: -m.confidence)
      return List/take(sorted, 3)

# ── Tool aggregator ─────────────────────────────────────────────────
# Mirrors tool-aggregator.service.ts: collect all available tools across servers

def ToolAggregator/collect(servers_tools: List((String, List(ToolDesc)))) -> List(ToolDesc):
  # flatten: each (server_id, tools) pair contatenated in parallel
  bend acc = List/Nil with lst = servers_tools:
    when lst != List/Nil:
      match lst:
        case List/Cons:
          head_tools = fork(lst.head.1)  # snd
          tail_all   = fork(ToolAggregator/collect(lst.tail))
          acc = List/concat(head_tools, tail_all)
        case List/Nil:
          acc = List/Nil
    else:
      acc = List/Nil
  return acc

# ── Parallel tool execution stub ────────────────────────────────────
# In prod this is FFI to the MCP SDK (stdio/http). Modelled as forked pure calls.

def mcp_call_tool(server_id: String, tool_name: String, input_json: String) -> (u24, String):
  # returns (success 0/1, output_json)
  # FFI placeholder — real HVM links to Rust MCP client
  return (1, String/concat("{\"tool\":\"", String/concat(tool_name, "\"}")))

def execute_matches_parallel(matches: List(IntentMatch), segment: Segment) -> List((IntentMatch, String)):
  # Fan-out: each IntentMatch triggers its tool concurrently
  n = List/len(matches)
  if n == 0:
    return List/Nil
  else:
    if n == 1:
      m = List/first(matches)
      (_, out) = mcp_call_tool(m.tool.server_id, m.tool.name, String/concat("{\"query\":\"", String/concat(segment.text, "\"}")))
      return List/Cons { head: (m, out), tail: List/Nil }
    else:
      half = n / 2
      left  = fork(execute_matches_parallel(List/take(matches, half), segment))
      right = fork(execute_matches_parallel(List/drop(matches, half), segment))
      return List/concat(left, right)

# ── Result handler (mirrors result-handler.service.ts) ──────────────
object MCPResult {
  server_id: String
  tool: String
  output: String
  markdown: String
}

def render_result(match_and_output: (IntentMatch, String)) -> MCPResult:
  m = match_and_output.0
  out = match_and_output.1
  md = String/concat(String/concat("**", String/concat(m.tool.name, "**")), String/concat(": ", out))
  return MCPResult { server_id: m.tool.server_id, tool: m.tool.name, output: out, markdown: md }

# ── Full MCP agent tick — called per final transcript segment ───────
def mcp_agent_tick(segment: Segment, all_tools: List(ToolDesc)) -> List(MCPResult):
  if segment.is_final == 0:
    return List/Nil
  else:
    matches = detect_intents(segment, all_tools)
    if List/len(matches) == 0:
      return List/Nil
    else:
      outputs = execute_matches_parallel(matches, segment)
      return List/map(outputs, render_result)
