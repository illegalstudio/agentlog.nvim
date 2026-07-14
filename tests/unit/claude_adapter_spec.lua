local h = require("tests.helpers")
local adapter = require("agentlog.adapters.claude")
local codex_adapter = require("agentlog.adapters.codex")
local detect = require("agentlog.detect")

local fixture = vim.fn.readfile("tests/fixtures/claude/session.dump")

local function region_at(parsed, row)
  for _, region in ipairs(parsed.regions) do
    if region.start_row == row then
      return region
    end
  end
end

local function fixture_row(expected)
  for index, line in ipairs(fixture) do
    if line == expected then
      return index - 1
    end
  end
  error(("fixture line not found: %s"):format(expected))
end

local function fixture_region(parsed, line)
  return region_at(parsed, fixture_row(line))
end

return {
  h.test("Claude detector recognizes a representative session", function()
    local result = adapter.detect(fixture, {
      path = "/tmp/zellij/claude-session.dump",
      readonly = true,
    })

    h.eq("claude", result.source)
    h.eq("zellij_scrollback", result.transport)
    h.truthy(result.confidence >= 0.75)
    h.truthy(vim.tbl_contains(result.evidence, "claude_header"))
    h.truthy(vim.tbl_contains(result.evidence, "claude_tool_output"))
    h.truthy(vim.tbl_contains(result.evidence, "agent_signature"))
  end),

  h.test("source detection prefers Claude for Claude scrollback", function()
    local result = detect.from_lines(fixture, {
      path = "/tmp/claude-session.dump",
    })
    local codex_result = codex_adapter.detect(fixture, {
      path = "/tmp/claude-session.dump",
    })

    h.eq("claude", result.source)
    h.truthy(result.confidence >= 0.75)
    h.truthy(result.confidence > codex_result.confidence)
  end),

  h.test("Claude detector remains conservative for ordinary numbered logs", function()
    local result = adapter.detect({ "2026 service started", "   1 worker ready" }, {
      path = "/tmp/server.dump",
    })

    h.truthy(result.confidence < 0.75)
    h.falsy(vim.tbl_contains(result.evidence, "agent_signature"))
  end),

  h.test("Claude parser recognizes turns, tools, summaries, and interface rows", function()
    local parsed = adapter.parse(fixture, { transport = "zellij_scrollback" })
    local prompt = fixture_region(parsed, "❯ Make every ExampleController endpoint return 404")
    local response = fixture_region(parsed, "⏺ I'll inspect the controller and its routes.")
    local summary = fixture_region(
      parsed,
      "  Searched for 3 patterns, read 2 files, ran 1 shell command"
    )
    local footer =
      fixture_region(parsed, "  developer@example  …/example-project  |  Fable 5  ctx:7%")

    h.eq("claude", parsed.source)
    h.eq("command", prompt.kind)
    h.eq("Make every ExampleController endpoint return 404", prompt.metadata.text)
    h.eq("response", response.kind)
    h.eq("summary", summary.metadata.metadata_type)
    h.eq("warning", fixture_region(parsed, " ⚠ 1 MCP server needs authentication · run /mcp").kind)
    h.eq(
      "progress",
      fixture_region(parsed, "✽ Bootstrapping… (5m 27s · ↓ 18.4k tokens)").metadata.metadata_type
    )
    h.eq("", fixture_region(parsed, "❯ ").metadata.text)
    h.eq("interface", footer.metadata.metadata_type)
  end),

  h.test("Claude parser preserves Write state across blank and wrapped output", function()
    local parsed = adapter.parse(fixture, { transport = "zellij_scrollback" })
    local action = fixture_region(
      parsed,
      "⏺ Write(/tmp/example-project/tests/Feature/ExampleControllerNotFoundTest.php)"
    )
    local output = fixture_region(parsed, "  ⎿  Wrote 10 lines to")
    local continuation = fixture_region(
      parsed,
      "     /tmp/example-project/tests/Feature/ExampleControllerNotFoundTest.php"
    )
    local first = fixture_region(parsed, "       1 <?php")
    local blank = fixture_region(parsed, "       2")

    h.eq("action", action.kind)
    h.eq("write", action.metadata.action_type)
    h.eq(
      "/tmp/example-project/tests/Feature/ExampleControllerNotFoundTest.php",
      action.metadata.path
    )
    h.eq("php", action.metadata.language)
    h.eq("output", output.kind)
    h.eq("file_reference", continuation.kind)
    h.truthy(continuation.metadata.continuation)
    h.eq(action.metadata.path, continuation.metadata.path)
    h.eq("add", first.metadata.line_type)
    h.eq(1, first.metadata.line_number)
    h.eq(nil, first.metadata.marker_col)
    h.eq("<?php", first.metadata.code)
    h.eq("", blank.metadata.code)
    h.eq(action.metadata.diff_id, first.metadata.diff_id)
  end),

  h.test("Claude parser maps Update previews as contextual compact diffs", function()
    local parsed = adapter.parse(fixture, { transport = "zellij_scrollback" })
    local action = fixture_region(
      parsed,
      "⏺ Update(app/Http/Controllers/ExampleController.php)"
    )
    local context = fixture_region(parsed, "      48      /**")
    local deleted = fixture_region(parsed, "      49 -     * Previous description.")
    local added = fixture_region(parsed, "      49 +     * Every endpoint must return 404.")

    h.eq("update", action.metadata.action_type)
    h.eq("app/Http/Controllers/ExampleController.php", action.metadata.path)
    h.eq("php", action.metadata.language)
    h.eq("context", context.metadata.line_type)
    h.eq("delete", deleted.metadata.line_type)
    h.eq("add", added.metadata.line_type)
    h.truthy(added.metadata.marker_col ~= nil)
    h.eq("     * Every endpoint must return 404.", added.metadata.code)
    h.eq(action.metadata.diff_id, added.metadata.diff_id)
  end),

  h.test("Claude parser maps Read previews as contextual source", function()
    local parsed = adapter.parse({
      "⏺ Read(src/example.lua)",
      "  ⎿ Read 2 lines",
      "       1 local answer = 42",
      "       2 return answer",
    }, {})
    local action = region_at(parsed, 0)
    local first = region_at(parsed, 2)

    h.eq("read", action.metadata.action_type)
    h.eq("src/example.lua", action.metadata.path)
    h.eq("lua", action.metadata.language)
    h.eq("context", first.metadata.line_type)
    h.eq(nil, first.metadata.marker_col)
    h.eq("local answer = 42", first.metadata.code)
  end),

  h.test("Claude parser recognizes collapsed source output", function()
    local parsed = adapter.parse({
      "⏺ Write(src/example.lua)",
      "  ⎿ Wrote 90 lines to src/example.lua",
      "       1 local answer = 42",
      "     … +89 lines",
    }, {})

    h.eq("collapsed", region_at(parsed, 3).metadata.metadata_type)
  end),

  h.test("Claude parser preserves structural highlighting for a truncated diff", function()
    local parsed = adapter.parse({
      "      59      {",
      "      60          return true;",
      "",
      "  Ran 1 shell command",
    }, {})

    h.eq("diff", region_at(parsed, 0).kind)
    h.eq("context", region_at(parsed, 0).metadata.line_type)
    h.eq(59, region_at(parsed, 0).metadata.line_number)
    h.eq("summary", region_at(parsed, 3).metadata.metadata_type)
  end),
}
