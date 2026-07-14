local M = {}

local links = {
  AgentlogResponse = "Normal",
  AgentlogAction = "Function",
  AgentlogActionSuccess = "DiagnosticOk",
  AgentlogActionFailure = "DiagnosticError",
  AgentlogCommand = "Statement",
  AgentlogOutput = "Comment",
  AgentlogMetadata = "Comment",
  AgentlogFile = "Directory",
  AgentlogDiffAdd = "DiffAdd",
  AgentlogDiffDelete = "DiffDelete",
  AgentlogDiffContext = "Normal",
  AgentlogDiffHeader = "DiffChange",
  AgentlogDiffLineNumber = "LineNr",
  AgentlogError = "DiagnosticError",
  AgentlogWarning = "DiagnosticWarn",
  AgentlogCollapsed = "Conceal",
}

function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = target })
  end
end

return M
