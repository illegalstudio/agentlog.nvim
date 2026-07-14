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

local colorscheme_autocmd_created = false

local function channel(color, shift)
  return math.floor(color / (2 ^ shift)) % 256
end

local function blend_channel(color, background, shift, intensity)
  local value = channel(color, shift) * intensity + channel(background, shift) * (1 - intensity)
  return math.floor(value + 0.5)
end

local function blend(color, background, intensity)
  if not color then
    return nil
  end
  if not background then
    return color
  end

  intensity = math.max(0, math.min(1, intensity))
  local red = blend_channel(color, background, 16, intensity)
  local green = blend_channel(color, background, 8, intensity)
  local blue = blend_channel(color, background, 0, intensity)
  return red * 0x10000 + green * 0x100 + blue
end

local function background_group(name, source_name)
  local source = vim.api.nvim_get_hl(0, { name = source_name, link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local source_background = source.reverse and source.fg or source.bg
  local cterm_background = source.reverse and source.ctermfg or source.ctermbg

  if not source_background then
    source_background = source.fg
  end

  vim.api.nvim_set_hl(0, name, {
    default = true,
    bg = blend(source_background, normal.bg, 0.2),
    ctermbg = cterm_background,
  })
end

function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = target })
  end

  background_group("AgentlogDiffAddBackground", "DiffAdd")
  background_group("AgentlogDiffDeleteBackground", "DiffDelete")

  if not colorscheme_autocmd_created then
    colorscheme_autocmd_created = true
    local group = vim.api.nvim_create_augroup("agentlog_highlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = M.setup,
    })
  end
end

return M
