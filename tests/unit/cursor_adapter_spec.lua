local h = require("tests.helpers")
local adapter = require("agentlog.adapters.cursor")
local codex_adapter = require("agentlog.adapters.codex")
local detect = require("agentlog.detect")
local navigation = require("agentlog.navigation")

local fixture = vim.fn.readfile("tests/fixtures/cursor/session.dump")

local function region_at(parsed, row)
  for _, region in ipairs(parsed.regions) do
    if region.start_row == row then
      return region
    end
  end
end

local function region_containing(parsed, row)
  for _, region in ipairs(parsed.regions) do
    if region.start_row <= row and row < region.end_row then
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
  h.test("Cursor detector recognizes a representative agent session", function()
    local result = adapter.detect(fixture, {
      path = "/tmp/zellij/cursor-session.dump",
      readonly = true,
    })

    h.eq("cursor", result.source)
    h.eq("zellij_scrollback", result.transport)
    h.truthy(result.confidence >= 0.75)
    h.truthy(vim.tbl_contains(result.evidence, "cursor_header"))
    h.truthy(vim.tbl_contains(result.evidence, "cursor_version"))
    h.truthy(vim.tbl_contains(result.evidence, "cursor_tool_ui"))
    h.truthy(vim.tbl_contains(result.evidence, "agent_signature"))
  end),

  h.test("source detection prefers Cursor over overlapping Codex actions", function()
    local result = detect.from_lines(fixture, {
      path = "/tmp/cursor-session.dump",
    })
    local codex_result = codex_adapter.detect(fixture, {
      path = "/tmp/cursor-session.dump",
    })

    h.eq("cursor", result.source)
    h.truthy(result.confidence >= 0.75)
    h.truthy(result.confidence > codex_result.confidence)
  end),

  h.test("explicit Cursor signature wins a confidence tie with Codex", function()
    local overlapping = {
      "Cursor Agent",
      "v2026.07.09-a3815c0",
      "Read example.lua lines 1-2",
      "Edited example.lua +1 -1",
      "│ structured output",
      "diff --git a/example.lua b/example.lua",
    }
    local context = { path = "/tmp/cursor-overlap.dump" }
    local cursor_result = adapter.detect(overlapping, context)
    local codex_result = codex_adapter.detect(overlapping, context)
    local result = detect.from_lines(overlapping, context)

    h.eq(1, cursor_result.confidence)
    h.eq(1, codex_result.confidence)
    h.truthy(cursor_result.specificity > codex_result.specificity)
    h.eq("cursor", result.source)
  end),

  h.test("Cursor detector remains conservative for ordinary version logs", function()
    local result = adapter.detect({
      "Cursor Agent connected to the service",
      "v2026.07.09 released to production",
      "ordinary application output",
    }, {
      path = "/tmp/server.dump",
    })

    h.truthy(result.confidence < 0.75)
    h.falsy(vim.tbl_contains(result.evidence, "agent_signature"))
  end),

  h.test("Cursor parser recognizes the banner and conservative text turns", function()
    local parsed = adapter.parse(fixture, { transport = "zellij_scrollback" })
    local header = fixture_region(parsed, "  Cursor Agent")
    local version = fixture_region(parsed, "  v2026.07.09-a3815c0")
    local prompt = fixture_region(
      parsed,
      "  Inspect this project and find the product update script."
    )
    local response = fixture_region(
      parsed,
      "  I’ll inspect the project and trace the product import flow."
    )
    local ambiguous = region_containing(
      parsed,
      fixture_row("  Please add a command and schedule it every morning.")
    )

    h.eq("cursor", parsed.source)
    h.eq("zellij_scrollback", parsed.transport)
    h.eq("header", header.metadata.metadata_type)
    h.eq("v2026.07.09-a3815c0", version.metadata.version)
    h.eq("command", prompt.kind)
    h.eq("response", response.kind)
    h.eq("unknown", ambiguous.kind)
  end),

  h.test("Cursor parser maps read, search, edit, and file-reference metadata", function()
    local parsed = adapter.parse(fixture, {})
    local read = fixture_region(parsed, "    Read docs/progress.md lines 680-779")
    local search = fixture_region(
      parsed,
      '    Grepped "importProducts|UniversalXmlParser" in .'
    )
    local truncated = fixture_region(
      parsed,
      "    Read .../Services/ProductFeedParser.php lines 85-134"
    )
    local edit = fixture_region(parsed, "    Edited Kernel.php +2 -1")
    local reference = fixture_region(parsed, "  app/Console/Kernel.php lines 28-31")

    h.eq("action", read.kind)
    h.eq("read", read.metadata.action_type)
    h.eq("docs/progress.md", read.metadata.path)
    h.eq("markdown", read.metadata.language)
    h.eq(680, read.metadata.first_line)
    h.eq(779, read.metadata.last_line)
    h.eq("search", search.metadata.action_type)
    h.eq("importProducts|UniversalXmlParser", search.metadata.query)
    h.eq(".../Services/ProductFeedParser.php", truncated.metadata.display_path)
    h.eq(nil, truncated.metadata.path)
    h.eq("edit", edit.metadata.action_type)
    h.eq(2, edit.metadata.additions)
    h.eq(1, edit.metadata.deletions)
    h.eq("file_reference", reference.kind)
    h.eq("app/Console/Kernel.php", reference.metadata.path)
    h.eq(28, reference.metadata.first_line)
  end),

  h.test("Cursor parser normalizes edit previews and collapsed rows", function()
    local parsed = adapter.parse(fixture, {})
    local edit = fixture_region(parsed, "    Edited Kernel.php +2 -1")
    local context = fixture_region(parsed, "    ▎       */")
    local deleted = fixture_region(
      parsed,
      "    ▎-         // $schedule->command('inspire')->hourly();"
    )
    local added = fixture_region(
      parsed,
      "    ▎+         $schedule->command('stores:import-products')->dailyAt('07:00');"
    )
    local collapsed = fixture_region(
      parsed,
      "    ▎ … truncated (12 more lines) · ctrl+r to review"
    )

    h.eq("context", context.metadata.line_type)
    h.eq("delete", deleted.metadata.line_type)
    h.eq("add", added.metadata.line_type)
    h.eq("Kernel.php", added.metadata.path)
    h.eq("php", added.metadata.language)
    h.eq(edit.metadata.diff_id, added.metadata.diff_id)
    h.truthy(added.metadata.marker_col ~= nil)
    h.eq("collapsed", collapsed.metadata.metadata_type)
    h.eq("preview", collapsed.metadata.collapsed_type)
  end),

  h.test("Cursor parser recognizes shell output, failures, todos, and interface rows", function()
    local parsed = adapter.parse(fixture, {})
    local command = fixture_region(
      parsed,
      '  $ ssh shop.example "cd /srv/shop && git pull origin main" 2>&1 exit 1 • 3.1s'
    )
    local hidden = fixture_region(parsed, "    … 2 output lines hidden · ctrl+o to expand")
    local failure = fixture_region(parsed, "    Aborting")
    local todo = fixture_region(parsed, "    To-do Working on 1 to-do • 2 done")
    local footer = fixture_region(parsed, "  → Add a follow-up")

    h.eq("action", command.kind)
    h.eq("run", command.metadata.action_type)
    h.eq(1, command.metadata.exit_code)
    h.eq("failure", command.metadata.status)
    h.eq("collapsed", hidden.metadata.metadata_type)
    h.eq("output", hidden.metadata.collapsed_type)
    h.eq("error", failure.kind)
    h.eq("progress", todo.metadata.metadata_type)
    h.eq("interface", footer.metadata.metadata_type)
  end),

  h.test("Cursor regions feed shared semantic navigation", function()
    local parsed = adapter.parse(fixture, {})

    h.eq({ 27, 38 }, navigation.targets(parsed, "diff"))
    h.eq({ 12, 27, 38, 67 }, navigation.targets(parsed, "file"))
    h.eq({ 62 }, navigation.targets(parsed, "error"))
    h.eq({ 8, 16, 36, 52, 58, 65 }, navigation.targets(parsed, "response"))
  end),
}
