local adapters = require("agentlog.adapters")
local config = require("agentlog.config")

local M = {}

function M.from_lines(lines, context)
  local best

  for _, name in ipairs(adapters.names()) do
    local adapter_config = config.get().adapters[name]
    local adapter = adapters.get(name)

    if
      (not adapter_config or adapter_config.enabled ~= false)
      and type(adapter.detect) == "function"
    then
      local candidate = adapter.detect(lines, context)
      if candidate and (not best or candidate.confidence > best.confidence) then
        best = candidate
      end
    end
  end

  return best
end

function M.buffer(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    error("cannot detect an invalid or unloaded buffer")
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(line_count, 2000), false)

  return M.from_lines(lines, {
    path = vim.api.nvim_buf_get_name(bufnr),
    buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr }),
    filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
    readonly = vim.api.nvim_get_option_value("readonly", { buf = bufnr }),
  })
end

return M
