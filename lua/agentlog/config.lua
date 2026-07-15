local M = {}

M.defaults = {
  -- Kept off until detection is covered by real positive and negative fixtures.
  auto_attach = false,
  min_confidence = 0.75,
  adapters = {
    claude = { enabled = true },
    codex = { enabled = true },
    cursor = { enabled = true },
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
  navigation = {
    wrap = true,
  },
  mappings = {
    enabled = true,
    next_action = "]a",
    previous_action = "[a",
    next_diff = "]d",
    previous_diff = "[d",
    next_response = "]r",
    previous_response = "[r",
    next_file = "]f",
    previous_file = "[f",
    next_error = "]e",
    previous_error = "[e",
    next_hunk = "]h",
    previous_hunk = "[h",
    open_file = "gf",
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
