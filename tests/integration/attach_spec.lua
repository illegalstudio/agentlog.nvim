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
    h.eq("agentlog.nvim: next diff hunk", buffer_mapping(bufnr, "]h").desc)
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
    h.eq(nil, buffer_mapping(bufnr, "]h"))
    h.eq(nil, buffer_mapping(bufnr, "gf"))
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),

  h.test("navigation mappings support counts, wrapping, commands, and file opening", function()
    local first_path = vim.fn.tempname() .. ".lua"
    local expected_readme = vim.uv.fs_realpath("README.md")
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
    local original_cwd = vim.fn.getcwd()
    vim.cmd("lcd " .. vim.fn.fnameescape("lua"))
    vim.cmd("normal gf")
    opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(
      expected_readme,
      vim.uv.fs_realpath(vim.api.nvim_buf_get_name(opened_buffer))
    )
    vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })
    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(first_path)
  end),

  h.test("Cursor file opening uses its workspace root and coordinates", function()
    local root = vim.fn.tempname()
    local path = root .. "/src/example.lua"
    h.eq(1, vim.fn.mkdir(root .. "/src", "p"))
    h.eq(0, vim.fn.writefile({ "one", "two", "abcdef", "four" }, path))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "Cursor Agent",
      "v2026.07.09-a3815c0",
      "",
      "src/example.lua:3:4",
      "",
      root .. " · main",
    })
    vim.api.nvim_set_current_buf(bufnr)
    local parsed = agentlog.attach(bufnr)
    h.eq(root, parsed.metadata.workspace_root)

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd("normal gf")
    local opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(vim.uv.fs_realpath(path), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    h.eq({ 3, 3 }, vim.api.nvim_win_get_cursor(0))

    vim.api.nvim_set_current_buf(bufnr)
    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })
    vim.api.nvim_buf_delete(bufnr, { force = true })
    h.eq(0, vim.fn.delete(root, "rf"))
  end),

  h.test("Cursor basename file opening requires one project match", function()
    local root = vim.fn.tempname()
    local unique_path = root .. "/tests/Feature/PublicMcpPagesTest.php"
    h.eq(1, vim.fn.mkdir(root .. "/tests/Feature", "p"))
    h.eq(1, vim.fn.mkdir(root .. "/app/First", "p"))
    h.eq(1, vim.fn.mkdir(root .. "/app/Second", "p"))
    h.eq(1, vim.fn.mkdir(root .. "/app/Third", "p"))
    h.eq(0, vim.fn.writefile({ "<?php" }, unique_path))
    h.eq(0, vim.fn.writefile({ "first" }, root .. "/app/First/Duplicate.php"))
    h.eq(0, vim.fn.writefile({ "second" }, root .. "/app/Second/Duplicate.php"))
    h.eq(0, vim.fn.writefile({ "third" }, root .. "/app/Third/Duplicate.php"))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "Cursor Agent",
      "v2026.07.09-a3815c0",
      "",
      "    Edited PublicMcpPagesTest.php +3 -3",
      "",
      "    Edited Duplicate.php +1 -1",
      "",
      root .. " · main",
    })
    vim.api.nvim_set_current_buf(bufnr)
    local parsed = agentlog.attach(bufnr)
    h.eq("cursor", parsed.source)

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd("normal gf")
    local opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(
      vim.uv.fs_realpath(unique_path),
      vim.uv.fs_realpath(vim.api.nvim_buf_get_name(opened_buffer))
    )

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    local resolved, message, reason, details = agentlog.open_file(bufnr)
    h.eq(nil, resolved)
    h.eq("ambiguous", reason)
    h.truthy(message:find("multiple files named Duplicate.php", 1, true))
    h.eq(root, details.root)
    h.eq(3, #details.candidates)
    h.eq(bufnr, vim.api.nvim_get_current_buf())

    local original_select = vim.ui.select
    local picker_items
    local picker_options
    vim.ui.select = function(items, options, on_choice)
      picker_items = items
      picker_options = options
      on_choice(items[2], 2)
    end
    local selected, select_error = pcall(vim.cmd, "normal gf")
    vim.ui.select = original_select
    if not selected then
      error(select_error)
    end

    h.eq("Select Duplicate.php:", picker_options.prompt)
    h.eq("app/First/Duplicate.php", picker_options.format_item(picker_items[1]))
    h.eq("app/Second/Duplicate.php", picker_options.format_item(picker_items[2]))
    h.eq("app/Third/Duplicate.php", picker_options.format_item(picker_items[3]))
    opened_buffer = vim.api.nvim_get_current_buf()
    h.eq(
      vim.uv.fs_realpath(root .. "/app/Second/Duplicate.php"),
      vim.uv.fs_realpath(vim.api.nvim_buf_get_name(opened_buffer))
    )

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_delete(opened_buffer, { force = true })
    vim.ui.select = function(_, _, on_choice)
      on_choice(nil, nil)
    end
    selected, select_error = pcall(vim.cmd, "normal gf")
    vim.ui.select = original_select
    if not selected then
      error(select_error)
    end
    h.eq(bufnr, vim.api.nvim_get_current_buf())

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    h.eq(0, vim.fn.delete(root, "rf"))
  end),

  h.test("recursive basename search remains Cursor-specific", function()
    local root = vim.fn.tempname()
    local path = root .. "/nested/PublicMcpPagesTest.php"
    h.eq(1, vim.fn.mkdir(root .. "/nested", "p"))
    h.eq(0, vim.fn.writefile({ "<?php" }, path))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "• Edited PublicMcpPagesTest.php (+1 -0)",
      "     1 +<?php",
    })
    vim.api.nvim_set_current_buf(bufnr)
    local parsed = agentlog.attach(bufnr)
    h.eq("codex", parsed.source)

    local original_cwd = vim.fn.getcwd()
    vim.cmd("lcd " .. vim.fn.fnameescape(root))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local resolved, _, reason = agentlog.open_file(bufnr)
    h.eq(nil, resolved)
    h.eq("not_found", reason)
    vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))

    agentlog.detach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    h.eq(0, vim.fn.delete(root, "rf"))
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

  h.test("hunk mappings navigate within one unified file diff", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "• Ran git diff",
      "diff --git a/example.lua b/example.lua",
      "index 1111111..2222222 100644",
      "--- a/example.lua",
      "+++ b/example.lua",
      "@@ -1 +1 @@",
      "-return false",
      "+return true",
      "@@ -10 +10 @@",
      "-local answer = 41",
      "+local answer = 42",
    })
    vim.api.nvim_set_current_buf(bufnr)
    agentlog.attach(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.cmd("AgentlogNext diff")
    h.eq(2, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("AgentlogNext hunk")
    h.eq(6, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]h")
    h.eq(9, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]h")
    h.eq(6, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal [h")
    h.eq(9, vim.api.nvim_win_get_cursor(0)[1])

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

  h.test("Cursor fixture attaches, navigates, and refreshes without mutation", function()
    agentlog.setup({ render = { diff_code_padding = 4 } })
    local lines = vim.fn.readfile("tests/fixtures/cursor/session.dump")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local parsed = agentlog.attach(bufnr)
    h.eq("cursor", parsed.source)
    h.eq("cursor", vim.b[bufnr].agentlog_source)

    local marks =
      vim.api.nvim_buf_get_extmarks(bufnr, render.namespace(), 0, -1, { details = true })
    local has_padding = false
    for _, mark in ipairs(marks) do
      has_padding = has_padding or mark[4].virt_text_pos == "inline"
    end
    h.falsy(has_padding)

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgentlogNext diff")
    h.eq(28, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal ]f")
    h.eq(39, vim.api.nvim_win_get_cursor(0)[1])

    agentlog.refresh(bufnr)
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    h.falsy(vim.api.nvim_get_option_value("modified", { buf = bufnr }))

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

    local cursor_path, cursor_buffer = open_dump({
      "Cursor Agent",
      "v2026.07.09-a3815c0",
      "",
      "Inspect this project",
      "",
      "$ pwd 0.1s",
      "  /tmp/example",
    }, false)
    h.truthy(agentlog.is_attached(cursor_buffer))
    h.eq("cursor", vim.b[cursor_buffer].agentlog_source)
    agentlog.detach(cursor_buffer)
    vim.api.nvim_buf_delete(cursor_buffer, { force = true })
    vim.fn.delete(cursor_path)

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
