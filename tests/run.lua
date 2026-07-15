local suites = {
  require("tests.unit.config_spec"),
  require("tests.unit.document_spec"),
  require("tests.unit.language_spec"),
  require("tests.unit.navigation_spec"),
  require("tests.unit.codex_adapter_spec"),
  require("tests.unit.claude_adapter_spec"),
  require("tests.integration.attach_spec"),
}

local total = 0
local failures = {}

for _, suite in ipairs(suites) do
  for _, test in ipairs(suite) do
    total = total + 1
    local ok, err = xpcall(test.run, debug.traceback)

    if ok then
      print(("ok %d - %s"):format(total, test.name))
    else
      failures[#failures + 1] = {
        name = test.name,
        error = err,
      }
      print(("not ok %d - %s"):format(total, test.name))
    end
  end
end

print(("\n%d tests, %d failures"):format(total, #failures))

if #failures > 0 then
  for _, failure in ipairs(failures) do
    vim.api.nvim_err_writeln(("\n%s\n%s"):format(failure.name, failure.error))
  end
  vim.cmd("cquit 1")
end

vim.cmd("qa!")
