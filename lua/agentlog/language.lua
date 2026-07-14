local M = {}

local extensions = {
  bash = "bash",
  c = "c",
  cc = "cpp",
  cjs = "javascript",
  cpp = "cpp",
  css = "css",
  go = "go",
  h = "c",
  hpp = "cpp",
  html = "html",
  js = "javascript",
  json = "json",
  jsonc = "json",
  jsx = "javascript",
  lua = "lua",
  md = "markdown",
  mjs = "javascript",
  php = "php",
  py = "python",
  rs = "rust",
  sh = "bash",
  ts = "typescript",
  tsx = "tsx",
  vim = "vim",
  yaml = "yaml",
  yml = "yaml",
  zsh = "bash",
}

function M.from_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local extension = path:match("%.([^./\\]+)$")
  if not extension then
    return nil
  end

  return extensions[extension:lower()]
end

return M
