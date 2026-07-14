local document = require("agentlog.document")
local language = require("agentlog.language")

local M = {
  name = "codex",
}

local action_labels = {
  "Ran",
  "Edited",
  "Explored",
  "Read",
  "Searched",
}

local markers = {
  "• ",
  "● ",
  "* ",
}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function action_text(line)
  local candidate = line:gsub("^%s+", "")

  for _, marker in ipairs(markers) do
    if starts_with(candidate, marker) then
      candidate = candidate:sub(#marker + 1)
      break
    end
  end

  return candidate
end

local function action_label(line)
  local candidate = action_text(line)

  for _, label in ipairs(action_labels) do
    if
      candidate == label
      or starts_with(candidate, label .. " ")
      or starts_with(candidate, label .. ":")
    then
      return label
    end
  end
end

local function edited_action_path(line)
  local path = action_text(line):match("^Edited%s+(.+)%s+%(%+%d+%s+%-%d+%)%s*$")
  if path and not path:match("^%d+%s+files?$") then
    return path
  end
end

local function add_evidence(result, name, weight)
  if result.seen[name] then
    return
  end

  result.seen[name] = true
  result.confidence = result.confidence + weight
  result.evidence[#result.evidence + 1] = name
end

local function edited_file_path(line)
  return line:match("^%s*└%s+(.+)%s+%(%+%d+%s+%-%d+%)%s*$")
end

local function compact_diff_line(line)
  local number_start, number, number_end, marker_start, marker, content_start =
    line:match("^%s*()(%d+)() ()([+%- ])()")

  if not number then
    return nil
  end

  local line_type = "context"
  if marker == "+" then
    line_type = "add"
  elseif marker == "-" then
    line_type = "delete"
  end

  return {
    line_type = line_type,
    line_number = tonumber(number),
    line_number_col = number_start - 1,
    line_number_end_col = number_end - 1,
    marker_col = marker_start - 1,
    content_col = content_start - 1,
    code = line:sub(content_start),
  }
end

function M.detect(lines, context)
  context = context or {}
  local result = {
    source = M.name,
    transport = nil,
    confidence = 0,
    evidence = {},
    seen = {},
  }

  local distinct_actions = {}
  local has_diff = false

  for _, line in ipairs(lines) do
    local label = action_label(line)
    if label then
      distinct_actions[label] = true
    end

    local compact_line = compact_diff_line(line)
    if
      line:match("^diff %-%-git ")
      or line:match("^@@ .+ @@")
      or (compact_line and compact_line.line_type ~= "context")
    then
      has_diff = true
    end
  end

  local action_count = vim.tbl_count(distinct_actions)
  if action_count > 0 then
    add_evidence(result, "codex_action", 0.45)
  end
  if action_count > 1 then
    add_evidence(result, "multiple_action_types", 0.15)
  end
  if has_diff then
    add_evidence(result, "unified_diff", 0.25)
  end

  local path = (context.path or ""):lower()
  if path:match("%.dump$") then
    add_evidence(result, "dump_extension", 0.1)
  end
  if path:find("zellij", 1, true) then
    result.transport = "zellij_scrollback"
    add_evidence(result, "zellij_path", 0.15)
  end
  if context.readonly then
    add_evidence(result, "readonly_buffer", 0.05)
  end

  result.confidence = math.min(result.confidence, 1)
  result.seen = nil
  return result
end

local function unknown_region(start_row, end_row)
  return {
    kind = "unknown",
    start_row = start_row,
    end_row = end_row,
    source = M.name,
    confidence = 0,
  }
end

function M.parse(lines, context)
  context = context or {}
  local regions = {}
  local unknown_start = 0
  local inside_diff = false
  local current_action
  local inside_edited = false
  local current_path
  local current_language
  local current_diff_id
  local next_diff_id = 0

  local function select_diff(path)
    current_path = path
    current_language = language.from_path(path)
    next_diff_id = next_diff_id + 1
    current_diff_id = next_diff_id
  end

  local function diff_metadata(metadata)
    metadata.path = current_path
    metadata.language = current_language
    metadata.diff_id = current_diff_id
    return metadata
  end

  local function recognize(row, kind, metadata, confidence)
    if unknown_start < row then
      regions[#regions + 1] = unknown_region(unknown_start, row)
    end

    regions[#regions + 1] = {
      kind = kind,
      start_row = row,
      end_row = row + 1,
      source = M.name,
      confidence = confidence or 1,
      metadata = metadata or {},
    }
    unknown_start = row + 1
  end

  for index, line in ipairs(lines) do
    local row = index - 1
    local label = action_label(line)
    local file_path = inside_edited and edited_file_path(line) or nil
    local compact_line = inside_edited and compact_diff_line(line) or nil

    if label then
      inside_diff = false
      current_action = label:lower()
      inside_edited = current_action == "edited"
      current_path = nil
      current_language = nil
      current_diff_id = nil

      local metadata = { action_type = current_action }
      local inline_path = inside_edited and edited_action_path(line) or nil
      if inline_path then
        select_diff(inline_path)
        metadata = diff_metadata(metadata)
      end

      recognize(row, "action", metadata, 0.9)
    elseif line:match("^diff %-%-git ") then
      inside_diff = true
      current_action = nil
      local _, new_path = line:match("^diff %-%-git a/(.-) b/(.+)$")
      select_diff(new_path)
      recognize(row, "diff_header", diff_metadata({}), 1)
    elseif
      inside_diff
      and (line:match("^index ") or line:match("^%-%-%- ") or line:match("^%+%+%+ "))
    then
      local new_path = line:match("^%+%+%+ b/(.+)$")
      if new_path and new_path ~= "/dev/null" then
        current_path = new_path
        current_language = language.from_path(new_path)
      end
      recognize(row, "diff_header", diff_metadata({}), 1)
    elseif inside_diff and line:match("^@@ .+ @@") then
      recognize(row, "diff_hunk", diff_metadata({}), 1)
    elseif inside_diff and starts_with(line, "+") then
      recognize(
        row,
        "diff",
        diff_metadata({ line_type = "add", marker_col = 0, content_col = 1, code = line:sub(2) }),
        1
      )
    elseif inside_diff and starts_with(line, "-") then
      recognize(
        row,
        "diff",
        diff_metadata({
          line_type = "delete",
          marker_col = 0,
          content_col = 1,
          code = line:sub(2),
        }),
        1
      )
    elseif inside_diff and (starts_with(line, " ") or starts_with(line, "\\ No newline")) then
      recognize(
        row,
        "diff",
        diff_metadata({
          line_type = "context",
          marker_col = 0,
          content_col = 1,
          code = line:sub(2),
        }),
        1
      )
    elseif inside_diff and line == "" then
      inside_diff = false
      current_action = nil
    elseif file_path then
      select_diff(file_path)
      recognize(row, "file_reference", diff_metadata({}), 1)
    elseif compact_line then
      recognize(row, "diff", diff_metadata(compact_line), 1)
    elseif current_action and line:match("^%s+") and line ~= "" then
      recognize(row, "output", {}, 0.8)
    elseif line == "" then
      current_action = nil
    end
  end

  if unknown_start < #lines then
    regions[#regions + 1] = unknown_region(unknown_start, #lines)
  end

  return document.new({
    source = M.name,
    transport = context.transport,
    regions = regions,
    metadata = {
      line_count = #lines,
    },
  })
end

return M
