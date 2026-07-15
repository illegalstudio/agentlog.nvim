local h = require("tests.helpers")
local document = require("agentlog.document")
local navigation = require("agentlog.navigation")

local parsed = document.new({
  source = "codex",
  regions = {
    { kind = "action", start_row = 0, end_row = 1, metadata = { diff_id = 1 } },
    {
      kind = "diff",
      start_row = 1,
      end_row = 2,
      metadata = { diff_id = 1, line_type = "add" },
    },
    { kind = "action", start_row = 3, end_row = 4 },
    { kind = "response", start_row = 4, end_row = 5 },
    { kind = "action", start_row = 6, end_row = 7, metadata = { diff_id = 2 } },
    {
      kind = "diff",
      start_row = 7,
      end_row = 8,
      metadata = { diff_id = 2, line_type = "context" },
    },
    { kind = "response", start_row = 9, end_row = 10 },
    { kind = "diff_header", start_row = 10, end_row = 11, metadata = { diff_id = 3 } },
    {
      kind = "diff",
      start_row = 11,
      end_row = 12,
      metadata = { diff_id = 3, line_type = "context" },
    },
    { kind = "diff", start_row = 14, end_row = 15, metadata = { line_type = "context" } },
    { kind = "diff", start_row = 15, end_row = 16, metadata = { line_type = "delete" } },
    { kind = "unknown", start_row = 16, end_row = 17 },
    { kind = "diff", start_row = 17, end_row = 18, metadata = { line_type = "add" } },
  },
})

return {
  h.test("navigation collects actions and changed diff groups", function()
    h.eq({ 0, 3, 6 }, navigation.targets(parsed, "action"))
    h.eq({ 0, 10, 14, 17 }, navigation.targets(parsed, "diff"))
    h.eq({ 4, 9 }, navigation.targets(parsed, "response"))
  end),

  h.test("navigation supports direction, counts, and wrapping", function()
    h.eq(3, navigation.find_target(parsed, "action", 0, "next", 1, true))
    h.eq(0, navigation.find_target(parsed, "action", 3, "previous", 1, true))
    h.eq(0, navigation.find_target(parsed, "action", 3, "next", 2, true))
    h.eq(17, navigation.find_target(parsed, "diff", 0, "previous", 1, true))
    h.eq(9, navigation.find_target(parsed, "response", 4, "next", 1, true))

    local target, message = navigation.find_target(parsed, "action", 6, "next", 1, false)
    h.eq(nil, target)
    h.eq("no next action region", message)
  end),

  h.test("navigation rejects unsupported kinds and invalid counts", function()
    h.falsy(pcall(navigation.targets, parsed, "error"))
    h.falsy(pcall(navigation.find_target, parsed, "action", 0, "next", 0, true))
  end),
}
