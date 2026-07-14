local config = require("agentlog.config")
local document = require("agentlog.document")
local syntax = require("agentlog.syntax")

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
  return groups[region.kind]
end

local function set_mark(bufnr, row, start_col, end_col, group, options)
  if not group or start_col < 0 or end_col <= start_col then
    return 0
  end

  options = options or {}
  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, start_col, {
    end_row = row,
    end_col = end_col,
    hl_group = group,
    hl_eol = options.hl_eol or false,
    hl_mode = options.hl_mode or "combine",
    priority = options.priority or 100,
    strict = false,
  })
  return 1
end

local function render_diff(bufnr, region, line)
  local metadata = region.metadata
  local count = 0

  if metadata.line_number_col and metadata.line_number_end_col then
    count = count
      + set_mark(
        bufnr,
        region.start_row,
        metadata.line_number_col,
        metadata.line_number_end_col,
        "AgentlogDiffLineNumber",
        { priority = 120 }
      )
  end

  local marker_group = "AgentlogDiffContext"
  if metadata.line_type == "add" then
    marker_group = "AgentlogDiffAdd"
  elseif metadata.line_type == "delete" then
    marker_group = "AgentlogDiffDelete"
  end

  if metadata.marker_col then
    count = count
      + set_mark(
        bufnr,
        region.start_row,
        metadata.marker_col,
        metadata.marker_col + 1,
        marker_group,
        { priority = 120 }
      )
  end

  local padding = math.max(0, math.floor(tonumber(config.get().render.diff_code_padding) or 0))
  if padding > 0 and metadata.content_col then
    local padding_group = "Normal"
    if config.get().render.diff_background and metadata.line_type == "add" then
      padding_group = "AgentlogDiffAddBackground"
    elseif config.get().render.diff_background and metadata.line_type == "delete" then
      padding_group = "AgentlogDiffDeleteBackground"
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, region.start_row, metadata.content_col, {
      virt_text = { { string.rep(" ", padding), padding_group } },
      virt_text_pos = "inline",
      hl_mode = "replace",
      priority = 90,
      strict = false,
    })
    count = count + 1
  end

  if config.get().render.diff_background and metadata.content_col then
    local background_group
    if metadata.line_type == "add" then
      background_group = "AgentlogDiffAddBackground"
    elseif metadata.line_type == "delete" then
      background_group = "AgentlogDiffDeleteBackground"
    end

    if background_group then
      count = count
        + set_mark(bufnr, region.start_row, metadata.content_col, #line, background_group, {
          priority = 80,
          hl_eol = true,
        })
    end
  end

  return count
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  syntax.clear(bufnr)
end

function M.render(bufnr, parsed_document)
  M.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local count = 0

  document.walk(parsed_document, function(region)
    if region.kind == "diff" and region.start_row < line_count then
      local line =
        vim.api.nvim_buf_get_lines(bufnr, region.start_row, region.start_row + 1, false)[1] or ""
      count = count + render_diff(bufnr, region, line)
      return
    end

    local group = group_for(region)
    local start_row = region.start_row
    local last_row = math.min(region.end_row, line_count) - 1

    if group and start_row >= 0 and last_row >= start_row and start_row < line_count then
      local last_line = vim.api.nvim_buf_get_lines(bufnr, last_row, last_row + 1, false)[1] or ""
      vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row, 0, {
        end_row = last_row,
        end_col = #last_line,
        hl_group = group,
        hl_eol = false,
        hl_mode = "combine",
        priority = 100,
        strict = false,
      })
      count = count + 1
    end
  end)

  count = count + syntax.apply(bufnr, parsed_document, namespace)

  return count
end

function M.namespace()
  return namespace
end

return M
