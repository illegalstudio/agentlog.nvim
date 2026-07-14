local document = require("agentlog.document")

local M = {
  name = "codex",
}

local action_labels = {
  "Ran",
  "Edited",
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

local function action_label(line)
  local candidate = line:gsub("^%s+", "")

  for _, marker in ipairs(markers) do
    if starts_with(candidate, marker) then
      candidate = candidate:sub(#marker + 1)
      break
    end
  end

  for _, label in ipairs(action_labels) do
    if candidate == label or starts_with(candidate, label .. " ") or starts_with(candidate, label .. ":") then
      return label
    end
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

    if line:match("^diff %-%-git ") or line:match("^@@ .+ @@") then
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

    if label then
      inside_diff = false
      recognize(row, "action", { action_type = label:lower() }, 0.9)
    elseif line:match("^diff %-%-git ") then
      inside_diff = true
      recognize(row, "diff_header", {}, 1)
    elseif inside_diff and (line:match("^index ") or line:match("^%-%-%- ") or line:match("^%+%+%+ ")) then
      recognize(row, "diff_header", {}, 1)
    elseif inside_diff and line:match("^@@ .+ @@") then
      recognize(row, "diff_hunk", {}, 1)
    elseif inside_diff and starts_with(line, "+") then
      recognize(row, "diff", { line_type = "add" }, 1)
    elseif inside_diff and starts_with(line, "-") then
      recognize(row, "diff", { line_type = "delete" }, 1)
    elseif inside_diff and (starts_with(line, " ") or starts_with(line, "\\ No newline")) then
      recognize(row, "diff", { line_type = "context" }, 1)
    elseif inside_diff and line == "" then
      inside_diff = false
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
