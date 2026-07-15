local document = require("agentlog.document")

local M = {}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local navigation_kinds = {
  action = true,
  diff = true,
  error = true,
  file = true,
  hunk = true,
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

local function file_targets(parsed_document)
  local groups = {}
  local ungrouped
  local rows = {}

  local function finish_ungrouped()
    if ungrouped then
      rows[#rows + 1] = ungrouped.start_row
    end
    ungrouped = nil
  end

  document.walk(parsed_document, function(region)
    local metadata = region.metadata or {}
    local path = metadata.path

    if type(path) ~= "string" or path == "" then
      finish_ungrouped()
      return
    end

    if metadata.diff_id ~= nil then
      finish_ungrouped()
      local key = table.concat({ region.source or "unknown", tostring(metadata.diff_id) }, ":")
      local group = groups[key]
      if not group then
        group = { start_row = region.start_row }
        groups[key] = group
      end
      group.start_row = math.min(group.start_row, region.start_row)
    elseif
      ungrouped
      and ungrouped.path == path
      and ungrouped.end_row == region.start_row
    then
      ungrouped.end_row = region.end_row
    else
      finish_ungrouped()
      ungrouped = {
        path = path,
        start_row = region.start_row,
        end_row = region.end_row,
      }
    end
  end)

  finish_ungrouped()
  for _, group in pairs(groups) do
    rows[#rows + 1] = group.start_row
  end
  return unique_sorted(rows)
end

local function diagnostic_targets(parsed_document)
  local rows = {}
  local previous_end

  document.walk(parsed_document, function(region)
    if region.kind == "error" or region.kind == "warning" then
      if previous_end ~= region.start_row then
        rows[#rows + 1] = region.start_row
      end
      previous_end = region.end_row
    else
      previous_end = nil
    end
  end)

  return unique_sorted(rows)
end

function M.kinds()
  return { "action", "diff", "error", "file", "hunk", "response" }
end

function M.targets(parsed_document, kind)
  if not navigation_kinds[kind] then
    error(("unsupported navigation kind %q"):format(tostring(kind)))
  end

  if kind == "diff" then
    return diff_targets(parsed_document)
  elseif kind == "error" then
    return diagnostic_targets(parsed_document)
  elseif kind == "file" then
    return file_targets(parsed_document)
  end

  local region_kind = kind == "hunk" and "diff_hunk" or kind
  local rows = {}
  document.walk(parsed_document, function(region)
    if region.kind == region_kind then
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

local function positive_integer(value)
  if type(value) == "number" and value >= 1 and value % 1 == 0 then
    return value
  end
end

function M.location_at(parsed_document, row)
  local location
  document.walk(parsed_document, function(region)
    local metadata = region.metadata or {}
    if region.start_row <= row and row < region.end_row and metadata.path then
      location = {
        path = metadata.path,
        line = positive_integer(metadata.target_line)
          or positive_integer(metadata.first_line)
          or positive_integer(metadata.line_number),
        column = positive_integer(metadata.target_column),
      }
    end
  end)
  return location
end

function M.path_at(parsed_document, row)
  local location = M.location_at(parsed_document, row)
  return location and location.path or nil
end

local function is_absolute(path)
  return starts_with(path, "/")
    or path:match("^%a:[/\\]") ~= nil
    or starts_with(path, "\\\\")
end

local function existing_path(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

local function repository_root(path)
  local marker = vim.fs.find(".git", {
    path = path,
    upward = true,
    limit = 1,
  })[1]
  return marker and vim.fs.dirname(marker) or nil
end

local function cursor_search_root(parsed_document, cwd)
  local metadata = parsed_document.metadata or {}
  local workspace_root = metadata.workspace_root
  if type(workspace_root) == "string"
    and is_absolute(workspace_root)
    and vim.fn.isdirectory(workspace_root) == 1
  then
    return vim.fs.normalize(workspace_root)
  end

  return repository_root(cwd) or vim.fs.normalize(cwd)
end

local function resolve_cursor_basename(path, parsed_document, cwd)
  if parsed_document.source ~= "cursor" or path:find("[/\\]") then
    return nil
  end

  local root = cursor_search_root(parsed_document, cwd)
  local matches = vim.fs.find(path, {
    path = root,
    type = "file",
    limit = 2,
  })

  if #matches == 1 then
    return vim.fs.normalize(matches[1])
  end
  if #matches > 1 then
    matches = vim.fs.find(path, {
      path = root,
      type = "file",
      limit = math.huge,
    })
    table.sort(matches)
    return nil, "ambiguous", {
      candidates = matches,
      root = root,
    }
  end
end

local function resolve_path(path, parsed_document, cwd)
  local candidates = {}
  local seen = {}

  local function add(candidate)
    if not candidate or candidate == "" then
      return
    end

    candidate = vim.fs.normalize(candidate)
    if not seen[candidate] then
      seen[candidate] = true
      candidates[#candidates + 1] = candidate
    end
  end

  if is_absolute(path) then
    add(path)
  else
    local metadata = parsed_document.metadata or {}
    local workspace_root = metadata.workspace_root
    if type(workspace_root) == "string" and is_absolute(workspace_root) then
      add(workspace_root .. "/" .. path)
    end

    local git_root = repository_root(cwd)
    if git_root then
      add(git_root .. "/" .. path)
    end
    add(cwd .. "/" .. path)
  end

  for _, candidate in ipairs(candidates) do
    if existing_path(candidate) then
      return candidate
    end
  end

  return resolve_cursor_basename(path, parsed_document, cwd)
end

local function move_to_location(winid, location)
  if not location.line then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line = math.min(location.line, line_count)
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local column = math.min((location.column or 1) - 1, #text)
  vim.api.nvim_win_set_cursor(winid, { line, column })
end

function M.open_file(bufnr, parsed_document, options)
  options = options or {}
  local winid = buffer_window(bufnr)
  local location = options.location
  if not location then
    local row = vim.api.nvim_win_get_cursor(winid)[1] - 1
    location = M.location_at(parsed_document, row)
  end
  if not location or not location.path or location.path == "" then
    return nil, "no recognized file at cursor", "no_file"
  end

  local resolved = options.resolved_path
  local resolution_error
  local resolution_details
  if resolved then
    resolved = vim.fs.normalize(resolved)
  else
    local cwd = vim.api.nvim_win_call(winid, function()
      return vim.fn.getcwd()
    end)
    resolved, resolution_error, resolution_details = resolve_path(
      location.path,
      parsed_document,
      cwd
    )
  end

  if not resolved then
    if resolution_error == "ambiguous" then
      local message = ("multiple files named %s found under %s"):format(
        location.path,
        resolution_details.root
      )
      resolution_details.location = location
      return nil, message, "ambiguous", resolution_details
    end
    return nil, ("file does not exist: %s"):format(location.path), "not_found"
  end
  if not existing_path(resolved) then
    return nil, ("file does not exist: %s"):format(resolved), "not_found"
  end

  vim.api.nvim_win_call(winid, function()
    vim.cmd("silent edit " .. vim.fn.fnameescape(resolved))
    move_to_location(winid, location)
  end)
  return resolved
end

return M
