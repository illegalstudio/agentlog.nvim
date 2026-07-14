local config = require("agentlog.config")
local document = require("agentlog.document")

local M = {}

local namespace = vim.api.nvim_create_namespace("agentlog")

local groups = {
  response = "AgentlogResponse",
  action = "AgentlogAction",
  command = "AgentlogCommand",
  output = "AgentlogOutput",
  metadata = "AgentlogMetadata",
  file_reference = "AgentlogFile",
  diff_header = "AgentlogDiffHeader",
  diff_hunk = "AgentlogDiffHeader",
  error = "AgentlogError",
  warning = "AgentlogWarning",
}

local function group_for(region)
  if region.kind == "diff" then
    local line_type = region.metadata.line_type
    if line_type == "add" then
      return "AgentlogDiffAdd"
    elseif line_type == "delete" then
      return "AgentlogDiffDelete"
    end
    return "AgentlogDiffContext"
  end

  return groups[region.kind]
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.render(bufnr, parsed_document)
  M.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local count = 0

  document.walk(parsed_document, function(region)
    local group = group_for(region)
    local start_row = region.start_row
    local last_row = math.min(region.end_row, line_count) - 1

    if group and start_row >= 0 and last_row >= start_row and start_row < line_count then
      local last_line = vim.api.nvim_buf_get_lines(bufnr, last_row, last_row + 1, false)[1] or ""
      vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row, 0, {
        end_row = last_row,
        end_col = #last_line,
        hl_group = group,
        hl_eol = config.get().render.diff_background,
        priority = 100,
        strict = false,
      })
      count = count + 1
    end
  end)

  return count
end

function M.namespace()
  return namespace
end

return M
