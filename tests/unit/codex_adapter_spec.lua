local h = require("tests.helpers")
local adapter = require("agentlog.adapters.codex")

local lines = {
  "• Ran pwd",
  "  /tmp/example",
  "diff --git a/example.lua b/example.lua",
  "index 1111111..2222222 100644",
  "--- a/example.lua",
  "+++ b/example.lua",
  "@@ -1 +1 @@",
  "-return false",
  "+return true",
  " context",
  "",
  "Unclassified narrative text.",
}

local tui_lines = {
  "• Explored",
  "  └ Search function in example.lua",
  "",
  "• Edited 1 file (+2 -0)",
  "  └ /tmp/example.php (+2 -0)",
  "     1 +<?php",
  "     2 +echo 'ok';",
}

local inline_tui_lines = {
  "• Edited /tmp/tagged_parameter_loop.php (+1 -1)",
  "     1  <?php",
  "     2 -function normalize(?int $value): int {",
  "     2 +function normalize(?int $value): ?int {",
  "     3      return $value;",
}

local function region_at(parsed, row)
  for _, region in ipairs(parsed.regions) do
    if region.start_row == row then
      return region
    end
  end
end

return {
  h.test("Codex detector combines independent evidence", function()
    local result = adapter.detect(lines, {
      path = "/tmp/zellij/session.dump",
      readonly = true,
    })

    h.eq("codex", result.source)
    h.eq("zellij_scrollback", result.transport)
    h.truthy(result.confidence >= 0.75)
  end),

  h.test("Codex detector remains conservative for ordinary dumps", function()
    local result = adapter.detect({ "A normal log line", "Another line" }, {
      path = "/tmp/server.dump",
    })

    h.truthy(result.confidence < 0.75)
  end),

  h.test("Codex parser recognizes action and unified diff lines", function()
    local parsed = adapter.parse(lines, { transport = "zellij_scrollback" })
    local kinds = vim.tbl_map(function(region)
      return region.kind
    end, parsed.regions)

    h.eq("codex", parsed.source)
    h.eq("action", kinds[1])
    h.truthy(vim.list_contains(kinds, "diff_header"))
    h.truthy(vim.list_contains(kinds, "diff_hunk"))
    h.truthy(vim.list_contains(kinds, "diff"))
    h.eq("unknown", kinds[#kinds])
    h.eq("lua", region_at(parsed, 7).metadata.language)
    h.eq("example.lua", region_at(parsed, 7).metadata.path)
  end),

  h.test("Codex parser recognizes TUI actions, output, files, and compact diffs", function()
    local parsed = adapter.parse(tui_lines, { transport = "zellij_scrollback" })
    local kinds = vim.tbl_map(function(region)
      return region.kind
    end, parsed.regions)

    h.eq("action", kinds[1])
    h.eq("explored", parsed.regions[1].metadata.action_type)
    h.truthy(vim.list_contains(kinds, "output"))
    h.truthy(vim.list_contains(kinds, "file_reference"))
    h.eq("/tmp/example.php", parsed.regions[5].metadata.path)
    h.eq("add", parsed.regions[6].metadata.line_type)
    h.eq("add", parsed.regions[7].metadata.line_type)
  end),

  h.test("Codex parser maps inline compact diff prefixes and language", function()
    local parsed = adapter.parse(inline_tui_lines, { transport = "zellij_scrollback" })
    local action = region_at(parsed, 0)
    local context = region_at(parsed, 1)
    local deleted = region_at(parsed, 2)
    local added = region_at(parsed, 3)

    h.eq("/tmp/tagged_parameter_loop.php", action.metadata.path)
    h.eq("php", action.metadata.language)
    h.eq("context", context.metadata.line_type)
    h.eq(1, context.metadata.line_number)
    h.eq(5, context.metadata.line_number_col)
    h.eq(7, context.metadata.marker_col)
    h.eq(8, context.metadata.content_col)
    h.eq("<?php", context.metadata.code)
    h.eq("delete", deleted.metadata.line_type)
    h.eq("add", added.metadata.line_type)
    h.eq(action.metadata.diff_id, added.metadata.diff_id)
  end),
}
