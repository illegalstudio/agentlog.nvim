local M = {}

M.defaults = {
  -- Kept off until detection is covered by real positive and negative fixtures.
  auto_attach = false,
  min_confidence = 0.75,
  adapters = {
    claude = { enabled = true },
    codex = { enabled = true },
  },
  render = {
    diff_background = true,
    diff_code_padding = 1,
    conceal_noise = false,
    virtual_text = true,
  },
  folding = {
    enabled = true,
    fold_output_over = 20,
  },
  syntax = {
    enabled = true,
    treesitter = true,
    max_region_lines = 500,
  },
  mappings = {
    enabled = true,
  },
}

local values = vim.deepcopy(M.defaults)

function M.setup(options)
  if options ~= nil and type(options) ~= "table" then
    error("setup options must be a table")
  end

  values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  return values
end

function M.get()
  return values
end

return M
