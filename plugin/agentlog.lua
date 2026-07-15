if vim.g.loaded_agentlog == 1 then
  return
end

vim.g.loaded_agentlog = 1

local agentlog = require("agentlog")

local function run(callback)
  return function(...)
    local ok, err = pcall(callback, ...)
    if not ok then
      vim.notify(("agentlog.nvim: %s"):format(err), vim.log.levels.ERROR)
    end
  end
end

local function complete_navigation_kind(arg_lead)
  return vim.tbl_filter(function(kind)
    return vim.startswith(kind, arg_lead)
  end, agentlog.navigation_kinds())
end

local function report_navigation(result, message)
  if result == nil then
    vim.notify(("agentlog.nvim: %s"):format(message), vim.log.levels.INFO)
  end
end

vim.api.nvim_create_user_command("AgentlogAttach", run(function()
  agentlog.attach(0)
end), {
  desc = "Attach agentlog.nvim to the current buffer",
})

vim.api.nvim_create_user_command("AgentlogRefresh", run(function()
  agentlog.refresh(0)
end), {
  desc = "Reparse and rerender the current agent log",
})

vim.api.nvim_create_user_command("AgentlogDetach", run(function()
  agentlog.detach(0)
end), {
  desc = "Detach agentlog.nvim from the current buffer",
})

vim.api.nvim_create_user_command("AgentlogNext", run(function(options)
  report_navigation(agentlog.goto_next(options.args, 0, options.count))
end), {
  nargs = 1,
  count = 1,
  complete = complete_navigation_kind,
  desc = "Jump to the next agentlog region of a given kind",
})

vim.api.nvim_create_user_command("AgentlogPrevious", run(function(options)
  report_navigation(agentlog.goto_previous(options.args, 0, options.count))
end), {
  nargs = 1,
  count = 1,
  complete = complete_navigation_kind,
  desc = "Jump to the previous agentlog region of a given kind",
})

agentlog._bootstrap()
