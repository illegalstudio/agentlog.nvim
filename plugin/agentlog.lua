if vim.g.loaded_agentlog == 1 then
  return
end

vim.g.loaded_agentlog = 1

local agentlog = require("agentlog")

local function run(callback)
  return function()
    local ok, err = pcall(callback)
    if not ok then
      vim.notify(("agentlog.nvim: %s"):format(err), vim.log.levels.ERROR)
    end
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

agentlog._bootstrap()
