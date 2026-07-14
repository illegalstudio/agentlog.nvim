local adapters = require("agentlog.adapters")
local config = require("agentlog.config")
local detect = require("agentlog.detect")
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
        or not has_evidence(detection, "codex_action")
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
