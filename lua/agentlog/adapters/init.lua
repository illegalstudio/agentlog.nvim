local M = {}

local registry = {
  claude = function()
    return require("agentlog.adapters.claude")
  end,
  codex = function()
    return require("agentlog.adapters.codex")
  end,
}

local loaded = {}

function M.register(name, adapter)
  if type(name) ~= "string" or name == "" then
    error("adapter name must be a non-empty string")
  end

  if type(adapter) ~= "table" or type(adapter.parse) ~= "function" then
    error("adapter must expose a parse function")
  end

  registry[name] = function()
    return adapter
  end
  loaded[name] = adapter
end

function M.get(name)
  if loaded[name] then
    return loaded[name]
  end

  local factory = registry[name]
  if not factory then
    return nil
  end

  loaded[name] = factory()
  return loaded[name]
end

function M.names()
  local names = vim.tbl_keys(registry)
  table.sort(names)
  return names
end

return M
