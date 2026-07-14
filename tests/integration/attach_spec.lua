local h = require("tests.helpers")
local agentlog = require("agentlog")
local render = require("agentlog.render")

return {
  h.test("plugin commands load without setup", function()
    h.eq(2, vim.fn.exists(":AgentlogAttach"))
    h.eq(2, vim.fn.exists(":AgentlogRefresh"))
    h.eq(2, vim.fn.exists(":AgentlogDetach"))
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
    h.eq(before, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end),
}
