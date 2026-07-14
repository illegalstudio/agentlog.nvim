local config = require("agentlog.config")

local M = {}

function M.check()
  vim.health.start("agentlog.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10 or newer is available")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end

  if config.get().auto_attach then
    vim.health.info("Automatic attachment is enabled")
  else
    vim.health.info("Automatic attachment is disabled; use :AgentlogAttach")
  end

  if vim.treesitter then
    vim.health.ok("Neovim Tree-sitter APIs are available")
  else
    vim.health.warn("Tree-sitter APIs are unavailable; semantic structure will still work")
  end
end

return M
