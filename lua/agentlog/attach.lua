local adapters = require("agentlog.adapters")
local config = require("agentlog.config")
local detect = require("agentlog.detect")
local navigation = require("agentlog.navigation")
local render = require("agentlog.render")

local M = {}

local states = {}
local auto_attach_group = vim.api.nvim_create_augroup("agentlog_auto_attach", { clear = true })
local state_group = vim.api.nvim_create_augroup("agentlog_state", { clear = true })

vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
  group = state_group,
  callback = function(event)
    states[event.buf] = nil
  end,
})

local function resolve_buffer(bufnr)
  bufnr = bufnr or 0
  return bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
end

local function assert_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    error("buffer is invalid or unloaded")
  end
end

local function has_evidence(detection, name)
  return detection.evidence and vim.tbl_contains(detection.evidence, name)
end

local function notify(message, level)
  vim.notify(("agentlog.nvim: %s"):format(message), level)
end

local function buffer_mapping(bufnr, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.lhs == lhs then
      return mapping
    end
  end
end

local function run_navigation_mapping(bufnr, kind, direction)
  local ok, target, message = pcall(M.navigate, bufnr, kind, direction, vim.v.count1)
  if not ok then
    notify(target, vim.log.levels.ERROR)
  elseif target == nil then
    notify(message, vim.log.levels.INFO)
  end
end

local function run_open_file_mapping(bufnr)
  local ok, path, message, reason = pcall(M.open_file, bufnr)
  if not ok then
    notify(path, vim.log.levels.ERROR)
  elseif path then
    return
  elseif reason == "no_file" then
    local native_ok, native_error = pcall(vim.cmd, "normal! gf")
    if not native_ok then
      notify(native_error, vim.log.levels.ERROR)
    end
  else
    notify(message, vim.log.levels.WARN)
  end
end

local mapping_specs = {
  {
    option = "next_action",
    description = "agentlog.nvim: next action",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "action", "next")
    end,
  },
  {
    option = "previous_action",
    description = "agentlog.nvim: previous action",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "action", "previous")
    end,
  },
  {
    option = "next_diff",
    description = "agentlog.nvim: next diff",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "diff", "next")
    end,
  },
  {
    option = "previous_diff",
    description = "agentlog.nvim: previous diff",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "diff", "previous")
    end,
  },
  {
    option = "next_response",
    description = "agentlog.nvim: next response",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "response", "next")
    end,
  },
  {
    option = "previous_response",
    description = "agentlog.nvim: previous response",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "response", "previous")
    end,
  },
  {
    option = "next_file",
    description = "agentlog.nvim: next file",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "file", "next")
    end,
  },
  {
    option = "previous_file",
    description = "agentlog.nvim: previous file",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "file", "previous")
    end,
  },
  {
    option = "next_error",
    description = "agentlog.nvim: next error or warning",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "error", "next")
    end,
  },
  {
    option = "previous_error",
    description = "agentlog.nvim: previous error or warning",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "error", "previous")
    end,
  },
  {
    option = "next_hunk",
    description = "agentlog.nvim: next diff hunk",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "hunk", "next")
    end,
  },
  {
    option = "previous_hunk",
    description = "agentlog.nvim: previous diff hunk",
    callback = function(bufnr)
      run_navigation_mapping(bufnr, "hunk", "previous")
    end,
  },
  {
    option = "open_file",
    description = "agentlog.nvim: open recognized file",
    callback = run_open_file_mapping,
  },
}

local function install_mappings(bufnr, state)
  local mappings = config.get().mappings or {}
  state.mappings = {}

  if mappings.enabled == false then
    return
  end

  for _, specification in ipairs(mapping_specs) do
    local lhs = mappings[specification.option]
    if type(lhs) == "string" and lhs ~= "" and not buffer_mapping(bufnr, lhs) then
      vim.keymap.set("n", lhs, function()
        specification.callback(bufnr)
      end, {
        buffer = bufnr,
        desc = specification.description,
        silent = true,
      })
      state.mappings[#state.mappings + 1] = {
        lhs = lhs,
        description = specification.description,
      }
    end
  end
end

local function clear_mappings(bufnr, state)
  for _, installed in ipairs(state.mappings or {}) do
    local current = buffer_mapping(bufnr, installed.lhs)
    if current and current.desc == installed.description then
      pcall(vim.keymap.del, "n", installed.lhs, { buffer = bufnr })
    end
  end
  state.mappings = {}
end

local function parse(bufnr, source, transport)
  local adapter_config = config.get().adapters[source]
  if adapter_config and adapter_config.enabled == false then
    error(("adapter %q is disabled"):format(source))
  end

  local adapter = adapters.get(source)
  if not adapter then
    error(("unknown adapter %q"):format(source))
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return adapter.parse(lines, {
    bufnr = bufnr,
    path = vim.api.nvim_buf_get_name(bufnr),
    transport = transport,
  })
end

function M.attach(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  options = options or {}
  assert_buffer(bufnr)

  if states[bufnr] then
    return M.refresh(bufnr)
  end

  local detection = options.detection
  if not options.source and not detection then
    local ok, candidate = pcall(detect.buffer, bufnr)
    if ok and candidate and has_evidence(candidate, "agent_signature") then
      detection = candidate
    end
  end

  local source = options.source or (detection and detection.source) or "codex"
  local transport = options.transport or (detection and detection.transport)
  local parsed_document = parse(bufnr, source, transport)
  local original_filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  states[bufnr] = {
    source = source,
    transport = transport,
    document = parsed_document,
    original = {
      filetype = original_filetype,
    },
  }

  vim.api.nvim_set_option_value("filetype", "agentlog", { buf = bufnr })
  vim.b[bufnr].agentlog_attached = true
  vim.b[bufnr].agentlog_source = source
  render.render(bufnr, parsed_document)
  install_mappings(bufnr, states[bufnr])

  return parsed_document
end

function M.refresh(bufnr)
  bufnr = resolve_buffer(bufnr)
  assert_buffer(bufnr)

  local state = states[bufnr]
  if not state then
    error("buffer is not attached")
  end

  local parsed_document = parse(bufnr, state.source, state.transport)
  render.render(bufnr, parsed_document)
  state.document = parsed_document

  return parsed_document
end

function M.detach(bufnr)
  bufnr = resolve_buffer(bufnr)
  local state = states[bufnr]
  if not state then
    return false
  end

  if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
    render.clear(bufnr)
    clear_mappings(bufnr, state)
    vim.b[bufnr].agentlog_attached = nil
    vim.b[bufnr].agentlog_source = nil

    local current_filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if current_filetype == "agentlog" then
      vim.api.nvim_set_option_value("filetype", state.original.filetype, { buf = bufnr })
    end
  end

  states[bufnr] = nil
  return true
end

function M.is_attached(bufnr)
  return states[resolve_buffer(bufnr)] ~= nil
end

function M.get_document(bufnr)
  local state = states[resolve_buffer(bufnr)]
  return state and state.document or nil
end

function M.navigation_kinds()
  return navigation.kinds()
end

function M.navigate(bufnr, kind, direction, count)
  bufnr = resolve_buffer(bufnr)
  assert_buffer(bufnr)

  local state = states[bufnr]
  if not state then
    error("buffer is not attached")
  end

  local navigation_config = config.get().navigation or {}
  return navigation.goto_region(
    bufnr,
    state.document,
    kind,
    direction,
    count,
    navigation_config.wrap ~= false
  )
end

function M.open_file(bufnr)
  bufnr = resolve_buffer(bufnr)
  assert_buffer(bufnr)

  local state = states[bufnr]
  if not state then
    error("buffer is not attached")
  end

  return navigation.open_file(bufnr, state.document)
end

function M.configure_auto_attach()
  vim.api.nvim_clear_autocmds({ group = auto_attach_group })

  if not config.get().auto_attach then
    return
  end

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = auto_attach_group,
    pattern = "*.dump",
    desc = "Attach agentlog.nvim to confidently detected scrollback",
    callback = function(event)
      if
        states[event.buf]
        or vim.b[event.buf].agentlog_disable
        or vim.api.nvim_get_option_value("buftype", { buf = event.buf }) ~= ""
      then
        return
      end

      local ok, detection = pcall(detect.buffer, event.buf)
      if
        not ok
        or not detection
        or not has_evidence(detection, "agent_signature")
        or detection.confidence < config.get().min_confidence
      then
        return
      end

      local attached, err = pcall(M.attach, event.buf, { detection = detection })
      if not attached then
        vim.schedule(function()
          vim.notify(("agentlog.nvim: %s"):format(err), vim.log.levels.WARN)
        end)
      end
    end,
  })
end

return M
