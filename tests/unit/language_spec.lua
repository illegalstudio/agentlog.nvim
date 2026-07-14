local h = require("tests.helpers")
local language = require("agentlog.language")

return {
  h.test("language is inferred from common file extensions", function()
    h.eq("php", language.from_path("/tmp/example.php"))
    h.eq("lua", language.from_path("lua/agentlog/init.lua"))
    h.eq("rust", language.from_path("src/main.rs"))
    h.eq("typescript", language.from_path("src/main.ts"))
  end),

  h.test("language inference is conservative for unknown paths", function()
    h.eq(nil, language.from_path("Makefile"))
    h.eq(nil, language.from_path("example.unknown"))
    h.eq(nil, language.from_path(nil))
  end),
}
