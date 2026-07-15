local document = require("agentlog.document")
local language = require("agentlog.language")

local M = {
  name = "cursor",
}

local preview_border = "▎"

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function trim_start(value)
  return value:gsub("^%s+", "")
end

local function trim(value)
  return trim_start(value):gsub("%s+$", "")
end

local function leading_spaces(value)
  return #(value:match("^ *") or "")
end

local function is_header(line)
  return trim(line) == "Cursor Agent"
end

local function is_version(line)
  return trim(line):match("^v%d%d%d%d%.%d%d%.%d%d[%w%.%-]*$") ~= nil
end

local function is_tip(line)
  return starts_with(trim_start(line), "Tip:")
end

local function is_separator(line)
  local candidate = trim_start(line)
  return starts_with(candidate, "────────")
    or starts_with(candidate, "▄▄▄▄▄▄")
    or starts_with(candidate, "▀▀▀▀▀▀")
end

local function workspace_footer(line)
  return trim(line):match("^(/.+)%s+·%s+[%w%._/-]+$")
end

local function is_footer(line)
  local candidate = trim(line)
  return starts_with(candidate, "→ Add a follow-up")
    or candidate:match("%sHigh%s+·%s+[%d%.]+%%") ~= nil
    or workspace_footer(line) ~= nil
end

local function is_todo(line)
  local candidate = trim_start(line)
  return starts_with(candidate, "To-do ")
    or starts_with(candidate, "◐ ")
    or starts_with(candidate, "○ ")
    or starts_with(candidate, "✔ ")
end

local function is_summary(line)
  local candidate = trim_start(line)
  return candidate:match("^Read, .+%d+ files?") ~= nil
    or candidate:match("^Read %d+ files?$") ~= nil
    or candidate:match("^… %d+ earlier items hidden$") ~= nil
end

local function collapsed_type(line)
  local candidate = trim_start(line)
  if candidate:match("^… %d+ output lines? hidden") then
    return "output"
  end
  if candidate:match("^… truncated %(") then
    return "preview"
  end
end

local function usable_path(path)
  if not path or path == "" or path == "." then
    return false
  end

  if path:find("...", 1, true) or path:find("…", 1, true) then
    return false
  end
  if path:match("^%a[%w+%.%-]*://") then
    return false
  end

  return path:find("/", 1, true) ~= nil or path:match("%.[%w_%-]+$") ~= nil
end

local function path_metadata(path)
  local metadata = { display_path = path }
  if usable_path(path) then
    metadata.path = path
    metadata.language = language.from_path(path)
  end
  return metadata
end

local function shell_action(line)
  local candidate = trim_start(line)
  if not starts_with(candidate, "$ ") then
    return nil
  end

  local exit_code = candidate:match("%sexit%s+(%d+)%s*[•·]")
  local metadata = {
    action_type = "run",
    command = candidate:sub(3),
  }

  if exit_code then
    metadata.exit_code = tonumber(exit_code)
    metadata.status = tonumber(exit_code) == 0 and "success" or "failure"
  end

  return metadata
end

local function edit_action(candidate)
  local path, additions, deletions = candidate:match("^Edited%s+(.+)%s+%+(%d+)%s+%-(%d+)$")
  if not path then
    path, additions = candidate:match("^Edited%s+(.+)%s+%+(%d+)$")
    deletions = "0"
  end

  if not path then
    return nil
  end

  local metadata = path_metadata(path)
  metadata.action_type = "edit"
  metadata.additions = tonumber(additions)
  metadata.deletions = tonumber(deletions)
  return metadata
end

local function read_action(candidate)
  local path, first_line, last_line = candidate:match("^Read%s+(.+)%s+lines%s+(%d+)%-(%d+)$")
  if not path then
    path, first_line = candidate:match("^Read%s+(.+)%s+line%s+(%d+)$")
    last_line = first_line
  end

  if not path then
    local possible_path = candidate:match("^Read%s+(.+)$")
    if usable_path(possible_path) then
      path = possible_path
    end
  end

  if not path then
    return nil
  end

  local metadata = path_metadata(path)
  metadata.action_type = "read"
  metadata.first_line = tonumber(first_line)
  metadata.last_line = tonumber(last_line)
  metadata.target_line = tonumber(first_line)
  return metadata
end

local function search_action(candidate)
  local query, scope = candidate:match('^Grepped%s+"(.*)"%s+in%s+(.+)$')
  if not query then
    return nil
  end

  return {
    action_type = "search",
    query = query,
    scope = scope,
  }
end

local function action_metadata(line)
  local shell = shell_action(line)
  if shell then
    return shell
  end

  local candidate = trim(line)
  return edit_action(candidate) or read_action(candidate) or search_action(candidate)
end

local function file_reference(line)
  local candidate = trim(line)
  local path, first_line, last_line = candidate:match("^(.+)%s+lines%s+(%d+)%-(%d+)$")
  local target_column

  if not path then
    path, first_line, target_column = candidate:match("^(.+):(%d+):(%d+)$")
    last_line = first_line
  end
  if not path then
    path, first_line = candidate:match("^(.+):(%d+)$")
    last_line = first_line
  end
  if not path or not usable_path(path) then
    return nil
  end

  local metadata = path_metadata(path)
  metadata.first_line = tonumber(first_line)
  metadata.last_line = tonumber(last_line)
  metadata.target_line = tonumber(first_line)
  metadata.target_column = tonumber(target_column)
  return metadata
end

local function preview_line(line)
  local border_start = line:find(preview_border, 1, true)
  if not border_start or not line:sub(1, border_start - 1):match("^%s*$") then
    return nil
  end

  local rest_start = border_start + #preview_border
  local rest = line:sub(rest_start)
  if starts_with(trim_start(rest), "… truncated (") then
    return { collapsed = true }
  end

  local marker = rest:sub(1, 1)
  local line_type = "context"
  local marker_col
  local content_start = rest_start

  if marker == "+" or marker == "-" then
    line_type = marker == "+" and "add" or "delete"
    marker_col = rest_start - 1
    content_start = rest_start + 1
  end

  if line:sub(content_start, content_start) == " " then
    content_start = content_start + 1
  end

  return {
    line_type = line_type,
    marker_col = marker_col,
    content_col = content_start - 1,
    code = line:sub(content_start),
  }
end

local function output_kind(line)
  local candidate = trim_start(line)
  local lowered = candidate:lower()

  if starts_with(lowered, "warning:") or starts_with(candidate, "⚠") then
    return "warning"
  end

  if
    starts_with(lowered, "error:")
    or starts_with(lowered, "fatal:")
    or starts_with(lowered, "failed")
    or starts_with(lowered, "aborting")
    or lowered:find(": command not found", 1, true)
    or lowered:find("no such file or directory", 1, true)
  then
    return "error"
  end

  return "output"
end

local function add_evidence(result, name, weight)
  if result.seen[name] then
    return
  end

  result.seen[name] = true
  result.confidence = result.confidence + weight
  result.evidence[#result.evidence + 1] = name
end

function M.detect(lines, context)
  context = context or {}
  local result = {
    source = M.name,
    transport = nil,
    confidence = 0,
    specificity = 0,
    evidence = {},
    seen = {},
  }

  local has_header = false
  local has_version = false
  local has_tool_ui = false
  local has_preview = false
  local has_footer = false

  for _, line in ipairs(lines) do
    has_header = has_header or is_header(line)
    has_version = has_version or is_version(line)
    has_tool_ui = has_tool_ui
      or action_metadata(line) ~= nil
      or is_todo(line)
      or collapsed_type(line) ~= nil
    has_preview = has_preview or preview_line(line) ~= nil
    has_footer = has_footer or is_footer(line)
  end

  if has_header then
    result.specificity = has_version and 1 or 0.9
    add_evidence(result, "cursor_header", 0.65)
  end
  if has_version then
    add_evidence(result, "cursor_version", 0.2)
  end
  if has_tool_ui then
    add_evidence(result, "cursor_tool_ui", 0.15)
  end
  if has_preview then
    add_evidence(result, "cursor_diff_preview", 0.1)
  end
  if has_footer then
    add_evidence(result, "cursor_footer", 0.1)
  end
  if has_header or (has_version and has_tool_ui) then
    if not has_header then
      result.specificity = 0.75
    end
    add_evidence(result, "agent_signature", 0)
  end

  local path = (context.path or ""):lower()
  if path:match("%.dump$") then
    add_evidence(result, "dump_extension", 0.1)
  end
  if path:find("zellij", 1, true) then
    result.transport = "zellij_scrollback"
    add_evidence(result, "zellij_path", 0.15)
  end
  if
    path:match("^/tmp/")
    or path:match("^/private/var/folders/")
    or path:match("^/var/folders/")
  then
    add_evidence(result, "temporary_path", 0.05)
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
  local base_indent = 0
  local awaiting_command = false
  local awaiting_response = false
  local current_edit
  local current_shell_indent
  local next_operation_id = 0
  local workspace_root

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

  local function start_operation(metadata)
    next_operation_id = next_operation_id + 1
    metadata.diff_id = next_operation_id
    return {
      path = metadata.path,
      language = metadata.language,
      diff_id = next_operation_id,
    }
  end

  local function operation_metadata(operation, metadata)
    metadata = metadata or {}
    metadata.path = operation.path
    metadata.language = operation.language
    metadata.diff_id = operation.diff_id
    return metadata
  end

  for index, line in ipairs(lines) do
    local row = index - 1
    local candidate = trim_start(line)
    local action = action_metadata(line)
    local collapsed = collapsed_type(line)
    local preview = current_edit and preview_line(line) or nil
    local reference = file_reference(line)
    local footer_root = workspace_footer(line)

    if is_header(line) then
      base_indent = leading_spaces(line)
      awaiting_command = true
      awaiting_response = false
      current_edit = nil
      current_shell_indent = nil
      recognize(row, "metadata", { metadata_type = "header" }, 1)
    elseif is_version(line) then
      recognize(row, "metadata", { metadata_type = "version", version = trim(line) }, 1)
    elseif is_tip(line) then
      recognize(row, "metadata", { metadata_type = "tip" }, 0.9)
    elseif is_separator(line) or is_footer(line) then
      current_edit = nil
      current_shell_indent = nil
      if footer_root then
        workspace_root = vim.fs.normalize(footer_root)
      end
      recognize(row, "metadata", { metadata_type = "interface" }, 0.9)
    elseif is_todo(line) then
      current_edit = nil
      current_shell_indent = nil
      awaiting_response = true
      recognize(row, "metadata", { metadata_type = "progress" }, 1)
    elseif is_summary(line) then
      awaiting_response = true
      recognize(row, "metadata", { metadata_type = "summary" }, 0.9)
    elseif collapsed then
      recognize(row, "metadata", { metadata_type = "collapsed", collapsed_type = collapsed }, 1)
    elseif preview and preview.collapsed then
      recognize(row, "metadata", { metadata_type = "collapsed", collapsed_type = "preview" }, 1)
    elseif preview then
      recognize(row, "diff", operation_metadata(current_edit, preview), 1)
    elseif action then
      current_edit = nil
      current_shell_indent = nil

      if action.path or action.action_type == "edit" or action.action_type == "read" then
        local operation = start_operation(action)
        if action.action_type == "edit" then
          current_edit = operation
        end
      end
      if action.action_type == "run" then
        current_shell_indent = leading_spaces(line)
      end

      awaiting_command = false
      awaiting_response = true
      recognize(row, "action", action, 1)
    elseif reference then
      current_edit = nil
      local operation = start_operation(reference)
      recognize(row, "file_reference", operation_metadata(operation, reference), 1)
    elseif current_shell_indent and line ~= "" and leading_spaces(line) > current_shell_indent then
      recognize(row, output_kind(line), { text = candidate }, 0.9)
    elseif line == "" then
      current_shell_indent = nil
    elseif leading_spaces(line) <= base_indent then
      current_edit = nil
      current_shell_indent = nil

      if awaiting_command then
        awaiting_command = false
        awaiting_response = true
        recognize(row, "command", { text = trim(line) }, 0.9)
      elseif awaiting_response then
        awaiting_response = false
        recognize(row, "response", { text = trim(line) }, 0.8)
      end
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
      workspace_root = workspace_root,
    },
  })
end

return M
