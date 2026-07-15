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

local file_change_tui_lines = {
  "• Added crates/example/src/lib.rs (+3 -0)",
  "      1 +//! Purpose:",
  "      2 +",
  "      3 +pub const ANSWER: u8 = 42;",
  "",
  "• Deleted /tmp/obsolete.lua (+0 -1)",
  "      1 -return false",
}

local response_lines = {
  "• Sto verificando il comportamento sul runtime reale.",
  "  Il dettaglio continua sulla riga successiva.",
  "",
  "• Calling codex_apps.github.get_pr_info({})",
  "• Updated Plan",
  "• Waited for background terminal · make test",
  "• You have 4 usage limit resets available.",
  "• You have two valid implementation options.",
  "• ## Risultato",
  "  Tutte le verifiche sono passate.",
}

local diagnostic_lines = {
  "⚠ MCP client failed to start: connection closed",
  "",
  "• Ran cargo test",
  "  └ Finished test profile",
  "",
  "    error: could not compile `example` due to 2 previous errors",
  "    warning: build failed, waiting for other jobs to finish...",
  "",
  "• Ran php example.php",
  "  └ PHP Fatal error: incompatible value",
  "",
  "• Ran rg pattern missing.rs",
  "  └ rg: missing.rs: No such file or directory (os error 2)",
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

  h.test("Codex detector accepts one structured action in a temporary dump", function()
    local result = adapter.detect({ "• Ran pwd", "  └ /tmp/example" }, {
      path = "/private/var/folders/example/T/session.dump",
    })

    h.truthy(result.confidence >= 0.75)
    h.truthy(vim.tbl_contains(result.evidence, "codex_action"))
    h.truthy(vim.tbl_contains(result.evidence, "structured_output"))
    h.truthy(vim.tbl_contains(result.evidence, "temporary_path"))
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

  h.test("Codex parser maps Added and Deleted compact file changes", function()
    local parsed = adapter.parse(file_change_tui_lines, { transport = "zellij_scrollback" })
    local added_action = region_at(parsed, 0)
    local added_line = region_at(parsed, 1)
    local deleted_action = region_at(parsed, 5)
    local deleted_line = region_at(parsed, 6)

    h.eq("added", added_action.metadata.action_type)
    h.eq("crates/example/src/lib.rs", added_action.metadata.path)
    h.eq("rust", added_action.metadata.language)
    h.eq("add", added_line.metadata.line_type)
    h.eq(added_action.metadata.diff_id, added_line.metadata.diff_id)
    h.eq("deleted", deleted_action.metadata.action_type)
    h.eq("/tmp/obsolete.lua", deleted_action.metadata.path)
    h.eq("lua", deleted_action.metadata.language)
    h.eq("delete", deleted_line.metadata.line_type)
    h.eq(deleted_action.metadata.diff_id, deleted_line.metadata.diff_id)
  end),

  h.test("Codex parser recognizes prose responses but excludes status bullets", function()
    local parsed = adapter.parse(response_lines, { transport = "zellij_scrollback" })
    local first = region_at(parsed, 0)
    local statuses = region_at(parsed, 1)
    local genuine_you_have = region_at(parsed, 7)
    local final = region_at(parsed, 8)

    h.eq("response", first.kind)
    h.eq("Sto verificando il comportamento sul runtime reale.", first.metadata.text)
    h.eq("unknown", statuses.kind)
    h.eq(1, statuses.start_row)
    h.eq(7, statuses.end_row)
    h.eq("response", genuine_you_have.kind)
    h.eq("response", final.kind)
    h.eq("## Risultato", final.metadata.text)
  end),

  h.test("Codex parser recognizes warnings and command errors", function()
    local parsed = adapter.parse(diagnostic_lines, { transport = "zellij_scrollback" })
    local startup_warning = region_at(parsed, 0)
    local compile_error = region_at(parsed, 5)
    local compile_warning = region_at(parsed, 6)
    local fatal_error = region_at(parsed, 9)
    local missing_file = region_at(parsed, 12)

    h.eq("warning", startup_warning.kind)
    h.eq("MCP client failed to start: connection closed", startup_warning.metadata.text)
    h.eq("error", compile_error.kind)
    h.eq("warning", compile_warning.kind)
    h.eq("error", fatal_error.kind)
    h.eq("error", missing_file.kind)
  end),
}
