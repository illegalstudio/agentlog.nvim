local h = require("tests.helpers")
local config = require("agentlog.config")

return {
  h.test("configuration starts with conservative defaults", function()
    config.setup()

    h.falsy(config.get().auto_attach)
    h.eq(0.75, config.get().min_confidence)
    h.truthy(config.get().adapters.claude.enabled)
    h.truthy(config.get().adapters.codex.enabled)
  end),

  h.test("configuration deep-merges user options", function()
    config.setup({
      min_confidence = 0.9,
      render = { virtual_text = false },
    })

    h.eq(0.9, config.get().min_confidence)
    h.falsy(config.get().render.virtual_text)
    h.truthy(config.get().render.diff_background)

    config.setup()
  end),

  h.test("configuration rejects non-table options", function()
    local ok = pcall(config.setup, "invalid")
    h.falsy(ok)
  end),
}
