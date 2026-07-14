local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))

vim.opt.runtimepath:prepend(root)
package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
