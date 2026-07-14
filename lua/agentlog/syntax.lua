local config = require("agentlog.config")
local document = require("agentlog.document")

local M = {}
local errors = {}

local function collect_diff_groups(parsed_document)
  local groups = {}

  document.walk(parsed_document, function(region)
    local metadata = region.metadata
    if
      region.kind == "diff"
      and metadata.diff_id
      and metadata.language
      and metadata.content_col
      and metadata.code ~= nil
    then
      local key = table.concat({ region.source, metadata.diff_id, metadata.path or "" }, ":")
      local group = groups[key]
      if not group then
        group = {
          language = metadata.language,
          path = metadata.path,
          entries = {},
          has_add = false,
          has_delete = false,
        }
        groups[key] = group
      end

      group.entries[#group.entries + 1] = {
        row = region.start_row,
        content_col = metadata.content_col,
        code = metadata.code,
        line_type = metadata.line_type,
      }
      group.has_add = group.has_add or metadata.line_type == "add"
      group.has_delete = group.has_delete or metadata.line_type == "delete"
    end
  end)

  local result = vim.tbl_values(groups)
  for _, group in ipairs(result) do
    table.sort(group.entries, function(left, right)
      return left.row < right.row
    end)
  end
  return result
end

local function included(entry, side)
  return entry.line_type == "context"
    or entry.line_type == "add" and side == "new"
    or entry.line_type == "delete" and side == "old"
end

local function build_snapshot(group, side)
  local lines = {}
  local mappings = {}
  local has_php_tag = false

  for _, entry in ipairs(group.entries) do
    if included(entry, side) then
      lines[#lines + 1] = entry.code
      mappings[#mappings + 1] = {
        row = entry.row,
        content_col = entry.content_col,
      }
      has_php_tag = has_php_tag or entry.code:find("<?", 1, true) ~= nil
    end
  end

  if group.language == "php" and not has_php_tag then
    table.insert(lines, 1, "<?php")
    table.insert(mappings, 1, { synthetic = true })
  end

  return {
    language = group.language,
    source = table.concat(lines, "\n"),
    lines = lines,
    mappings = mappings,
  }
end

local function capture_priority(metadata, capture)
  local capture_metadata = metadata and metadata[capture]
  local priority = metadata and metadata.priority or capture_metadata and capture_metadata.priority
  local treesitter_priority = vim.hl and vim.hl.priorities and vim.hl.priorities.treesitter or 100
  return (tonumber(priority) or treesitter_priority) + 20
end

local function apply_capture(bufnr, namespace, snapshot, query, capture, node, metadata, seen)
  local capture_name = query.captures[capture]
  if not capture_name or capture_name:sub(1, 1) == "_" then
    return 0
  end

  local range = vim.treesitter.get_range(node, snapshot.source, metadata and metadata[capture])
  local start_row, start_col, end_row, end_col = range[1], range[2], range[4], range[5]
  local final_row = end_row
  if end_row > start_row and end_col == 0 then
    final_row = end_row - 1
  end

  local count = 0
  local highlight = "@" .. capture_name .. "." .. snapshot.language

  for snapshot_row = start_row, final_row do
    local mapping = snapshot.mappings[snapshot_row + 1]
    local source_line = snapshot.lines[snapshot_row + 1] or ""

    if mapping and not mapping.synthetic then
      local local_start = snapshot_row == start_row and start_col or 0
      local local_end = snapshot_row == end_row and end_col or #source_line
      local buffer_start = mapping.content_col + local_start
      local buffer_end = mapping.content_col + local_end
      local key = table.concat({ mapping.row, buffer_start, buffer_end, highlight }, ":")

      if buffer_end > buffer_start and not seen[key] then
        seen[key] = true
        vim.api.nvim_buf_set_extmark(bufnr, namespace, mapping.row, buffer_start, {
          end_row = mapping.row,
          end_col = buffer_end,
          hl_group = highlight,
          hl_mode = "combine",
          priority = capture_priority(metadata, capture),
          strict = false,
        })
        count = count + 1
      end
    end
  end

  return count
end

local function apply_snapshot(bufnr, namespace, snapshot, seen)
  if snapshot.source == "" then
    return 0
  end

  local parser = vim.treesitter.get_string_parser(snapshot.source, snapshot.language)
  local trees = parser:parse()
  local query = vim.treesitter.query.get(snapshot.language, "highlights")
  if not trees[1] or not query then
    return 0
  end

  local count = 0
  for capture, node, metadata in query:iter_captures(trees[1]:root(), snapshot.source, 0, -1) do
    count = count + apply_capture(bufnr, namespace, snapshot, query, capture, node, metadata, seen)
  end
  return count
end

function M.apply(bufnr, parsed_document, namespace)
  errors[bufnr] = {}
  local syntax_config = config.get().syntax
  if
    not syntax_config.enabled
    or not syntax_config.treesitter
    or not vim.treesitter
    or type(vim.treesitter.get_string_parser) ~= "function"
  then
    return 0
  end

  local count = 0
  local seen = {}

  for _, group in ipairs(collect_diff_groups(parsed_document)) do
    if #group.entries <= syntax_config.max_region_lines then
      local sides = {}
      if group.has_add then
        sides[#sides + 1] = "new"
      end
      if group.has_delete then
        sides[#sides + 1] = "old"
      end

      for _, side in ipairs(sides) do
        local snapshot = build_snapshot(group, side)
        local ok, applied = pcall(apply_snapshot, bufnr, namespace, snapshot, seen)
        if ok then
          count = count + applied
        else
          errors[bufnr][#errors[bufnr] + 1] = applied
        end
      end
    end
  end

  return count
end

function M.get_errors(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return errors[bufnr] or {}
end

function M.clear(bufnr)
  errors[bufnr] = nil
end

return M
