local h = require("tests.helpers")
local document = require("agentlog.document")

return {
  h.test("document normalizes nested regions", function()
    local parsed = document.new({
      source = "codex",
      regions = {
        {
          kind = "action",
          start_row = 1,
          end_row = 4,
          children = {
            {
              kind = "command",
              start_row = 2,
              end_row = 3,
            },
          },
        },
      },
    })

    h.eq("codex", parsed.source)
    h.eq("command", parsed.regions[1].children[1].kind)
  end),

  h.test("document rejects inverted row ranges", function()
    local ok = pcall(document.region, {
      kind = "output",
      start_row = 3,
      end_row = 3,
    })

    h.falsy(ok)
  end),
}
