local attach = require("agentlog.attach")
local config = require("agentlog.config")
local highlight = require("agentlog.highlight")

local M = {}

local bootstrapped = false

function M.setup(options)
  local values = config.setup(options)
  highlight.setup()
  attach.configure_auto_attach()
  return values
end

function M.attach(bufnr, options)
  return attach.attach(bufnr, options)
end

function M.refresh(bufnr)
  return attach.refresh(bufnr)
end

function M.detach(bufnr)
  return attach.detach(bufnr)
end

function M.is_attached(bufnr)
  return attach.is_attached(bufnr)
end

function M.get_document(bufnr)
  return attach.get_document(bufnr)
end

function M._bootstrap()
  if bootstrapped then
    return
  end

  bootstrapped = true
  highlight.setup()
  attach.configure_auto_attach()
end

return M
