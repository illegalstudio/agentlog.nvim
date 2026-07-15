local h = require("tests.helpers")
local document = require("agentlog.document")
local navigation = require("agentlog.navigation")

local parsed = document.new({
  source = "codex",
  regions = {
    {
      kind = "action",
      start_row = 0,
      end_row = 1,
      metadata = {
        diff_id = 1,
        path = "src/first.lua",
        target_line = 12,
        target_column = 4,
      },
    },
    {
      kind = "diff",
      start_row = 1,
      end_row = 2,
      metadata = {
        diff_id = 1,
        line_type = "add",
        line_number = 22,
        path = "src/first.lua",
      },
    },
    { kind = "action", start_row = 3, end_row = 4 },
    { kind = "response", start_row = 4, end_row = 5 },
    {
      kind = "action",
      start_row = 6,
      end_row = 7,
      metadata = { diff_id = 2, path = "src/read.lua" },
    },
    {
      kind = "diff",
      start_row = 7,
      end_row = 8,
      metadata = { diff_id = 2, line_type = "context", path = "src/read.lua" },
    },
    { kind = "response", start_row = 9, end_row = 10 },
    {
      kind = "diff_header",
      start_row = 10,
      end_row = 11,
      metadata = { diff_id = 3, path = "src/second.lua" },
    },
    {
      kind = "diff_hunk",
      start_row = 11,
      end_row = 12,
      metadata = { diff_id = 3, path = "src/second.lua" },
    },
    { kind = "error", start_row = 12, end_row = 13 },
    { kind = "warning", start_row = 13, end_row = 14 },
    {
      kind = "diff",
      start_row = 14,
      end_row = 15,
      metadata = { line_type = "context", path = "src/loose.lua" },
    },
    {
      kind = "diff",
      start_row = 15,
      end_row = 16,
      metadata = { line_type = "delete", path = "src/loose.lua" },
    },
    { kind = "unknown", start_row = 16, end_row = 17 },
    {
      kind = "diff",
      start_row = 17,
      end_row = 18,
      metadata = { line_type = "add", path = "src/loose.lua" },
    },
    { kind = "warning", start_row = 19, end_row = 20 },
    {
      kind = "diff_header",
      start_row = 21,
      end_row = 22,
      metadata = { diff_id = 4, path = "src/third.lua" },
    },
    {
      kind = "diff_hunk",
      start_row = 22,
      end_row = 23,
      metadata = { diff_id = 4, path = "src/third.lua" },
    },
  },
})

return {
  h.test("navigation collects semantic targets and changed diff groups", function()
    h.eq({ 0, 3, 6 }, navigation.targets(parsed, "action"))
    h.eq({ 0, 10, 14, 17, 21 }, navigation.targets(parsed, "diff"))
    h.eq({ 12, 19 }, navigation.targets(parsed, "error"))
    h.eq({ 0, 6, 10, 14, 17, 21 }, navigation.targets(parsed, "file"))
    h.eq({ 11, 22 }, navigation.targets(parsed, "hunk"))
    h.eq({ 4, 9 }, navigation.targets(parsed, "response"))
  end),

  h.test("navigation supports direction, counts, and wrapping", function()
    h.eq(3, navigation.find_target(parsed, "action", 0, "next", 1, true))
    h.eq(0, navigation.find_target(parsed, "action", 3, "previous", 1, true))
    h.eq(0, navigation.find_target(parsed, "action", 3, "next", 2, true))
    h.eq(21, navigation.find_target(parsed, "diff", 0, "previous", 1, true))
    h.eq(19, navigation.find_target(parsed, "error", 12, "next", 1, true))
    h.eq(6, navigation.find_target(parsed, "file", 0, "next", 1, true))
    h.eq(22, navigation.find_target(parsed, "hunk", 11, "next", 1, true))
    h.eq(9, navigation.find_target(parsed, "response", 4, "next", 1, true))

    local target, message = navigation.find_target(parsed, "action", 6, "next", 1, false)
    h.eq(nil, target)
    h.eq("no next action region", message)
  end),

  h.test("navigation rejects unsupported kinds and invalid counts", function()
    h.falsy(pcall(navigation.targets, parsed, "prompt"))
    h.falsy(pcall(navigation.find_target, parsed, "action", 0, "next", 0, true))
  end),

  h.test("navigation returns optional file coordinates", function()
    h.eq({ path = "src/first.lua", line = 12, column = 4 }, navigation.location_at(parsed, 0))
    h.eq({ path = "src/first.lua", line = 22 }, navigation.location_at(parsed, 1))
    h.eq("src/first.lua", navigation.path_at(parsed, 0))
    h.eq(nil, navigation.location_at(parsed, 4))
  end),
}
