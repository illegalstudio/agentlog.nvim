local document = require("agentlog.document")

local M = {}

local navigation_kinds = {
  action = true,
  diff = true,
  response = true,
}

local function diff_region_has_changes(region)
  if region.kind == "diff_header" or region.kind == "diff_hunk" then
    return true
  end

  local line_type = region.metadata and region.metadata.line_type
  return region.kind == "diff" and (line_type == "add" or line_type == "delete")
end

local function unique_sorted(rows)
  table.sort(rows)

  local result = {}
  for _, row in ipairs(rows) do
    if result[#result] ~= row then
      result[#result + 1] = row
    end
  end

  return result
end

local function diff_targets(parsed_document)
  local groups = {}
  local orphan
  local rows = {}

  local function finish_orphan()
    if orphan and orphan.has_changes then
      rows[#rows + 1] = orphan.start_row
    end
    orphan = nil
  end

  document.walk(parsed_document, function(region)
    local metadata = region.metadata or {}
    local diff_id = metadata.diff_id

    if diff_id ~= nil then
      finish_orphan()
      local key = table.concat({ region.source or "unknown", tostring(diff_id) }, ":")
      local group = groups[key]
      if not group then
        group = { start_row = region.start_row, has_changes = false }
        groups[key] = group
      end

      group.start_row = math.min(group.start_row, region.start_row)
      group.has_changes = group.has_changes or diff_region_has_changes(region)
    elseif region.kind == "diff" then
      if not orphan or orphan.end_row ~= region.start_row then
        finish_orphan()
        orphan = {
          start_row = region.start_row,
          end_row = region.end_row,
          has_changes = false,
        }
      else
        orphan.end_row = region.end_row
      end

      orphan.has_changes = orphan.has_changes or diff_region_has_changes(region)
    else
      finish_orphan()
    end
  end)

  finish_orphan()
  for _, group in pairs(groups) do
    if group.has_changes then
      rows[#rows + 1] = group.start_row
    end
  end

  return unique_sorted(rows)
end

function M.kinds()
  return { "action", "diff", "response" }
end

function M.targets(parsed_document, kind)
  if not navigation_kinds[kind] then
    error(("unsupported navigation kind %q"):format(tostring(kind)))
  end

  if kind == "diff" then
    return diff_targets(parsed_document)
  end

  local rows = {}
  document.walk(parsed_document, function(region)
    if region.kind == kind then
      rows[#rows + 1] = region.start_row
    end
  end)
  return unique_sorted(rows)
end

function M.find_target(parsed_document, kind, current_row, direction, count, wrap)
  local targets = M.targets(parsed_document, kind)
  if #targets == 0 then
    return nil, ("no %s regions in this buffer"):format(kind)
  end

  direction = direction or "next"
  if direction ~= "next" and direction ~= "previous" then
    error(("unsupported navigation direction %q"):format(tostring(direction)))
  end

  count = count or 1
  if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
    error("navigation count must be a positive integer")
  end

  local row = current_row
  for _ = 1, count do
    local target

    if direction == "next" then
      for _, candidate in ipairs(targets) do
        if candidate > row then
          target = candidate
          break
        end
      end
      if target == nil and wrap then
        target = targets[1]
      end
    else
      for index = #targets, 1, -1 do
        if targets[index] < row then
          target = targets[index]
          break
        end
      end
      if target == nil and wrap then
        target = targets[#targets]
      end
    end

    if target == nil then
      return nil, ("no %s %s region"):format(direction, kind)
    end
    row = target
  end

  return row
end

local function buffer_window(bufnr)
  local current_window = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current_window) == bufnr then
    return current_window
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    error("buffer is not displayed in a window")
  end
  return winid
end

function M.goto_region(bufnr, parsed_document, kind, direction, count, wrap)
  local winid = buffer_window(bufnr)
  local current_row = vim.api.nvim_win_get_cursor(winid)[1] - 1
  local target, message = M.find_target(
    parsed_document,
    kind,
    current_row,
    direction,
    count,
    wrap
  )

  if target == nil then
    return nil, message
  end

  vim.api.nvim_win_call(winid, function()
    vim.cmd(("normal! %dG"):format(target + 1))
  end)
  return target
end

function M.path_at(parsed_document, row)
  local path
  document.walk(parsed_document, function(region)
    local metadata = region.metadata or {}
    if region.start_row <= row and row < region.end_row and metadata.path then
      path = metadata.path
    end
  end)
  return path
end

function M.open_file(bufnr, parsed_document)
  local winid = buffer_window(bufnr)
  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1
  local path = M.path_at(parsed_document, row)
  if not path or path == "" then
    return nil, "no recognized file at cursor", "no_file"
  end

  local resolved = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if vim.fn.filereadable(resolved) ~= 1 and vim.fn.isdirectory(resolved) ~= 1 then
    return nil, ("file does not exist: %s"):format(path), "not_found"
  end

  vim.api.nvim_win_call(winid, function()
    vim.cmd("silent edit " .. vim.fn.fnameescape(resolved))
  end)
  return resolved
end

return M
