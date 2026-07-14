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
  end),
}
