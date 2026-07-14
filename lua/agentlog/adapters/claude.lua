local document = require("agentlog.document")
local language = require("agentlog.language")

local M = {
  name = "claude",
}

local non_breaking_space = " "

local tools = {
  agent = true,
  askuserquestion = true,
  bash = true,
  edit = true,
  enterplanmode = true,
  exitplanmode = true,
  glob = true,
  grep = true,
  list = true,
  multiedit = true,
  notebookedit = true,
  read = true,
  search = true,
  skill = true,
  task = true,
  todowrite = true,
  update = true,
  webfetch = true,
  websearch = true,
  write = true,
}

local path_tools = {
  edit = true,
  multiedit = true,
  notebookedit = true,
  read = true,
  update = true,
  write = true,
}

local edit_tools = {
  edit = true,
  multiedit = true,
  notebookedit = true,
  update = true,
}

local spinner_markers = {
  "✶",
  "✽",
  "✻",
  "✢",
}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function trim_start(value)
  value = value:gsub("^%s+", "")
  while starts_with(value, non_breaking_space) do
    value = value:sub(#non_breaking_space + 1)
  end
  return value
end

local function marked_text(line, marker)
  local candidate = line:gsub("^%s+", "")
  if not starts_with(candidate, marker) then
    return nil
  end
  return trim_start(candidate:sub(#marker + 1))
end

local function assistant_text(line)
  return marked_text(line, "⏺")
end

local function user_text(line)
  return marked_text(line, "❯")
end

local function tool_output_text(line)
  return marked_text(line, "⎿")
end

local function add_evidence(result, name, weight)
  if result.seen[name] then
    return
  end

  result.seen[name] = true
  result.confidence = result.confidence + weight
  result.evidence[#result.evidence + 1] = name
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

local function numbered_source_line(line, line_type)
  local number_start, number, number_end, content_start =
    line:match("^%s*()(%d+)() ()")

  if number then
    return {
      line_type = line_type,
      line_number = tonumber(number),
      line_number_col = number_start - 1,
      line_number_end_col = number_end - 1,
      content_col = content_start - 1,
      code = line:sub(content_start),
    }
  end

  number_start, number, number_end = line:match("^%s*()(%d+)()%s*$")
  if not number then
    return nil
  end

  return {
    line_type = line_type,
    line_number = tonumber(number),
    line_number_col = number_start - 1,
    line_number_end_col = number_end - 1,
    content_col = #line,
    code = "",
  }
end

local function tool_call(text)
  if text:match("^Running %d+ ") then
    return "run"
  end

  local name, argument = text:match("^([%a][%w_]*)%((.*)%)$")
  name = name and name:lower() or nil
  if not name or not tools[name] then
    return nil
  end

  if not path_tools[name] then
    argument = nil
  else
    argument = trim_start(argument):gsub("%s+$", "")
    if argument == "" then
      argument = nil
    end
  end

  return name, argument
end

local function is_header(line)
  return line:find("Claude Code v", 1, true) ~= nil
end

local function is_banner(line)
  local candidate = trim_start(line)
  return is_header(line)
    or starts_with(candidate, "▝▜")
    or starts_with(candidate, "▘▘")
end

local function is_summary(line)
  local candidate = trim_start(line)
  return candidate:match("^Ran %d+ shell command") ~= nil
    or starts_with(candidate, "Searched for ")
    or candidate:match("^Read %d+ files?") ~= nil
    or candidate:match("^Listed %d+ director") ~= nil
end

local function is_spinner(line)
  local candidate = trim_start(line)
  for _, marker in ipairs(spinner_markers) do
    if starts_with(candidate, marker) then
      return true
    end
  end
  return false
end

local function is_separator(line)
  return starts_with(trim_start(line), "────────")
end

local function is_footer_metadata(line)
  local candidate = trim_start(line)
  return starts_with(candidate, "⏵⏵")
    or line:find(" ctx:", 1, true) ~= nil
    or line:find(" bypass permissions ", 1, true) ~= nil
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

  local has_header = false
  local has_user_turn = false
  local has_assistant_turn = false
  local has_tool_output = false
  local has_code_preview = false

  for _, line in ipairs(lines) do
    has_header = has_header or is_header(line)
    has_user_turn = has_user_turn or user_text(line) ~= nil
    has_assistant_turn = has_assistant_turn or assistant_text(line) ~= nil
    has_tool_output = has_tool_output or tool_output_text(line) ~= nil
    has_code_preview = has_code_preview
      or compact_diff_line(line) ~= nil
      or numbered_source_line(line, "context") ~= nil
  end

  if has_header then
    add_evidence(result, "claude_header", 0.65)
  end
  if has_user_turn then
    add_evidence(result, "claude_user_turn", 0.15)
  end
  if has_assistant_turn then
    add_evidence(result, "claude_assistant_turn", 0.25)
  end
  if has_tool_output then
    add_evidence(result, "claude_tool_output", 0.15)
  end
  if has_code_preview then
    add_evidence(result, "claude_code_preview", 0.15)
  end
  if has_header or (has_assistant_turn and (has_user_turn or has_tool_output)) then
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
  local current_tool
  local current_path
  local current_language
  local current_diff_id
  local next_diff_id = 0
  local tool_output_active = false

  local function reset_tool()
    current_tool = nil
    current_path = nil
    current_language = nil
    current_diff_id = nil
    tool_output_active = false
  end

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
    local assistant = assistant_text(line)
    local user = user_text(line)
    local tool_output = tool_output_text(line)
    local compact_line = current_tool and edit_tools[current_tool] and compact_diff_line(line)
      or nil
    local orphan_compact_line = not current_tool and compact_diff_line(line) or nil
    local source_line

    if current_tool == "write" then
      source_line = numbered_source_line(line, "add")
    elseif current_tool == "read" then
      source_line = numbered_source_line(line, "context")
    elseif current_tool and edit_tools[current_tool] and not compact_line then
      local candidate = numbered_source_line(line, "context")
      if candidate and candidate.code == "" then
        source_line = candidate
      end
    end

    if is_banner(line) then
      reset_tool()
      recognize(row, "metadata", { metadata_type = "header" }, 1)
    elseif starts_with(trim_start(line), "⚠") then
      recognize(row, "warning", {}, 1)
    elseif starts_with(trim_start(line), "▎") then
      recognize(row, "metadata", { metadata_type = "notice" }, 0.9)
    elseif user ~= nil then
      reset_tool()
      recognize(row, "command", { text = user }, 1)
    elseif assistant ~= nil then
      local tool, path = tool_call(assistant)
      if tool then
        reset_tool()
        current_tool = tool
        if path then
          select_diff(path)
        end

        local metadata = { action_type = tool }
        if current_diff_id then
          metadata = diff_metadata(metadata)
        end
        recognize(row, "action", metadata, 1)
      else
        reset_tool()
        recognize(row, "response", {}, 1)
      end
    elseif tool_output ~= nil then
      tool_output_active = true
      local lowered = tool_output:lower()
      local kind = "output"
      if starts_with(lowered, "error") or starts_with(lowered, "failed") then
        kind = "error"
      elseif starts_with(lowered, "warning") then
        kind = "warning"
      end
      recognize(row, kind, {}, 0.9)
    elseif compact_line then
      recognize(row, "diff", diff_metadata(compact_line), 1)
    elseif source_line then
      recognize(row, "diff", diff_metadata(source_line), 1)
    elseif orphan_compact_line then
      recognize(row, "diff", orphan_compact_line, 0.7)
    elseif starts_with(trim_start(line), "… ") then
      recognize(row, "metadata", { metadata_type = "collapsed" }, 1)
    elseif is_summary(line) then
      reset_tool()
      recognize(row, "metadata", { metadata_type = "summary" }, 0.9)
    elseif is_spinner(line) then
      recognize(row, "metadata", { metadata_type = "progress" }, 0.9)
    elseif is_separator(line) or is_footer_metadata(line) then
      recognize(row, "metadata", { metadata_type = "interface" }, 0.8)
    elseif current_tool and tool_output_active and line:match("^%s+") and line ~= "" then
      if current_path and trim_start(line) == current_path then
        recognize(row, "file_reference", diff_metadata({ continuation = true }), 1)
      else
        recognize(row, "output", { continuation = true }, 0.8)
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
    },
  })
end

return M
