local h = require("tests.helpers")
local agentlog = require("agentlog")
local render = require("agentlog.render")
local syntax = require("agentlog.syntax")

local function buffer_mapping(bufnr, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.lhs == lhs then
      return mapping
    end
  end
end

return {
  h.test("plugin commands load without setup", function()
    h.eq(2, vim.fn.exists(":AgentlogAttach"))
    h.eq(2, vim.fn.exists(":AgentlogRefresh"))
    h.eq(2, vim.fn.exists(":AgentlogDetach"))
    h.eq(2, vim.fn.exists(":AgentlogNext"))
    h.eq(2, vim.fn.exists(":AgentlogPrevious"))
  end),

  h.test("attach, refresh, and detach preserve buffer text", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local lines = {
      "• Ran pwd",
      "diff --git a/a.lua b/a.lua",
      "@@ -1 +1 @@",
      "-old",
      "+new",
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "text", { buf = bufnr })
    vim.api.nvim_set_option_value("modified", false, { buf = bufnr })

    local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local parsed = agentlog.attach(bufnr)
    local first_marks = vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, {})

    h.eq("codex", parsed.source)
    h.truthy(agentlog.is_attached(bufnr))
    h.eq("agentlog", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
    h.eq("agentlog.nvim: next action", buffer_mapping(bufnr, "]a").desc)
    h.eq("agentlog.nvim: next response", buffer_mapping(bufnr, "]r").desc)
    h.eq("agentlog.nvim: next file", buffer_mapping(bufnr, "]f").desc)
    h.eq("agentlog.nvim: next error or warning", buffer_mapping(bufnr, "]e").desc)
    h.eq("agentlog.nvim: open recognized file", buffer_mapping(bufnr, "gf").desc)
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    h.falsy(vim.api.nvim_get_option_value("modified", { buf = bufnr }))
    h.truthy(#first_marks > 0)

    agentlog.refresh(bufnr)
    local refreshed_marks = vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, {})
    h.eq(#first_marks, #refreshed_marks)
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    h.truthy(agentlog.detach(bufnr))
    h.falsy(agentlog.is_attached(bufnr))
    h.eq("text", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
    h.eq(0, #vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, {}))
    h.eq(nil, buffer_mapping(bufnr, "]a"))
    h.eq(nil, buffer_mapping(bufnr, "]r"))
    h.eq(nil, buffer_mapping(bufnr, "]f"))
    h.eq(nil, buffer_mapping(bufnr, "]e"))
    h.eq(nil, buffer_mapping(bufnr, "gf"))
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("navigation mappings support counts, wrapping, commands, and file opening", function()
    local first_path = vim.fn.tempname() .. ".lua"
    h.eq(0, vim.fn.writefile({ "return 1" }, first_path))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      ("• Edited %s (+1 -0)"):format(first_path),
      "     1 +return 1",
      "",
      "• Explored",
      "  └ Search answer in example.lua",
      "",
      "• Added README.md (+1 -0)",
      "     1 +return 2",
    })
    vim.api.nvim_set_current_buf(bufnr)
    agentlog.attach(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.cmd("AgentlogNext action")
    h.eq(4, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal 2]a")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal [d")
    h.eq(7, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]d")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("AgentlogNext file")
    h.eq(7, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]f")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal [f")
    h.eq(7, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]f")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])

    vim.cmd("normal gf")
    local opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(vim.uv.fs_realpath(first_path), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })

    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    vim.cmd("normal gf")
    opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(
      vim.uv.fs_realpath("README.md"),
      vim.uv.fs_realpath(vim.api.nvim_buf_get_name(opened_buffer))
    )

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })
    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(first_path)
  end),

  h.test("response mappings and commands navigate Codex prose", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "• Prima risposta.",
      "",
      "• Ran pwd",
      "  └ /tmp/example",
      "",
      "• Seconda risposta.",
    })
    vim.api.nvim_set_current_buf(bufnr)
    agentlog.attach(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.cmd("AgentlogNext response")
    h.eq(6, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]r")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal [r")
    h.eq(6, vim.api.nvim_win_get_cursor(0)[1])

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("error mappings combine Codex errors and warnings", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "⚠ MCP client failed to start",
      "",
      "• Ran cargo test",
      "  └ error: could not compile `example`",
      "    warning: build failed, waiting for other jobs to finish...",
      "",
      "• Ran printf ok",
      "  └ ok",
      "",
      "• Ran php example.php",
      "  └ PHP Fatal error: incompatible value",
    })
    vim.api.nvim_set_current_buf(bufnr)
    agentlog.attach(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.cmd("AgentlogNext error")
    h.eq(4, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]e")
    h.eq(11, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]e")
    h.eq(1, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal [e")
    h.eq(11, vim.api.nvim_win_get_cursor(0)[1])

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("attachment preserves pre-existing buffer-local mappings", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "• Ran pwd", "  └ /tmp" })
    vim.keymap.set("n", "]a", "<Nop>", {
      buffer = bufnr,
      desc = "existing buffer mapping",
    })

    agentlog.attach(bufnr)
    h.eq("existing buffer mapping", buffer_mapping(bufnr, "]a").desc)
    agentlog.detach(bufnr)
    h.eq("existing buffer mapping", buffer_mapping(bufnr, "]a").desc)

    vim.keymap.del("n", "]a", { buffer = bufnr })
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("compact diffs layer gutter, background, and Tree-sitter captures", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "• Added /tmp/example.lua (+1 -0)",
      "     1 +local answer = 42",
    })

    agentlog.attach(bufnr)
    local marks =
      vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, { details = true })
    local groups = {}
    local padding

    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details.hl_group then
        groups[details.hl_group] = (groups[details.hl_group] or 0) + 1
      end
      if details.virt_text and details.virt_text_pos == "inline" then
        padding = details.virt_text[1][1]
        h.eq("replace", details.hl_mode)
      end
    end

    h.truthy(groups.AgentlogDiffLineNumber)
    h.truthy(groups.AgentlogDiffAdd)
    h.truthy(groups.AgentlogDiffAddBackground)
    h.truthy(groups["@keyword.lua"])
    h.truthy(groups["@number.lua"])
    h.eq(" ", padding)
    h.eq({}, syntax.get_errors(bufnr))

    agentlog.detach(bufnr)
    h.eq({}, syntax.get_errors(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("Claude Write previews render source without virtual diff padding", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local lines = {
      "⏺ Write(/tmp/example.lua)",
      "",
      "  ⎿ Wrote 2 lines to",
      "     /tmp/example.lua",
      "       1 local answer = 42",
      "       2 return answer",
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local parsed = agentlog.attach(bufnr)
    local marks =
      vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, { details = true })
    local groups = {}
    local has_padding = false

    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details.hl_group then
        groups[details.hl_group] = true
      end
      has_padding = has_padding or details.virt_text_pos == "inline"
    end

    h.eq("claude", parsed.source)
    h.eq("claude", vim.b[bufnr].agentlog_source)
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    h.truthy(groups.AgentlogDiffLineNumber)
    h.truthy(groups.AgentlogDiffAddBackground)
    h.truthy(groups["@keyword.lua"])
    h.falsy(has_padding)

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("structural diff highlighting survives when syntax is disabled", function()
    agentlog.setup({ syntax = { enabled = false } })
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "• Edited /tmp/example.lua (+1 -0)",
      "     1 +local answer = 42",
    })

    agentlog.attach(bufnr)
    local marks =
      vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, { details = true })
    local groups = {}

    for _, mark in ipairs(marks) do
      if mark[4].hl_group then
        groups[mark[4].hl_group] = true
      end
    end

    h.truthy(groups.AgentlogDiffLineNumber)
    h.truthy(groups.AgentlogDiffAdd)
    h.truthy(groups.AgentlogDiffAddBackground)
    h.falsy(groups["@keyword.lua"])

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    agentlog.setup()
  end),

  h.test("automatic attachment is conservative and supports a buffer opt-out", function()
    agentlog.setup({ auto_attach = true })

    local function open_dump(lines, disable)
      local path = vim.fn.tempname() .. ".dump"
      h.eq(0, vim.fn.writefile(lines, path))

      if disable then
        vim.api.nvim_create_autocmd("BufReadPre", {
          pattern = "*.dump",
          once = true,
          callback = function(event)
            vim.b[event.buf].agentlog_disable = true
          end,
        })
      end

      vim.cmd.edit(vim.fn.fnameescape(path))
      return path, vim.api.nvim_get_current_buf()
    end

    local positive_path, positive_buffer =
      open_dump({ "• Ran pwd", "  └ /tmp/example" }, false)
    h.truthy(agentlog.is_attached(positive_buffer))
    h.eq("agentlog", vim.bo[positive_buffer].filetype)
    agentlog.detach(positive_buffer)
    vim.api.nvim_buf_delete(positive_buffer, { force = true })
    vim.fn.delete(positive_path)

    local claude_path, claude_buffer = open_dump({
      "❯ Create an example module",
      "⏺ Write(/tmp/example.lua)",
      "",
      "  ⎿ Wrote 1 line to",
      "     /tmp/example.lua",
      "       1 return true",
    }, false)
    h.truthy(agentlog.is_attached(claude_buffer))
    h.eq("claude", vim.b[claude_buffer].agentlog_source)
    agentlog.detach(claude_buffer)
    vim.api.nvim_buf_delete(claude_buffer, { force = true })
    vim.fn.delete(claude_path)

    local negative_path, negative_buffer = open_dump({ "ordinary server log" }, false)
    h.falsy(agentlog.is_attached(negative_buffer))
    vim.api.nvim_buf_delete(negative_buffer, { force = true })
    vim.fn.delete(negative_path)

    local disabled_path, disabled_buffer =
      open_dump({ "• Ran pwd", "  └ /tmp/example" }, true)
    h.falsy(agentlog.is_attached(disabled_buffer))
    vim.api.nvim_buf_delete(disabled_buffer, { force = true })
    vim.fn.delete(disabled_path)

    agentlog.setup()
  end),
}
