<p align="center">
  <img src="assets/agentlog-logo.png" alt="agentlog.nvim logo" width="130">
</p>

<h1 align="center">agentlog.nvim</h1>

<p align="center">
  <em>Make AI agent scrollback readable.</em>
</p>

<p align="center">
  <a href="https://github.com/illegalstudio/agentlog.nvim/stargazers"><img src="https://img.shields.io/github/stars/illegalstudio/agentlog.nvim?style=flat-square&logo=github&logoColor=white&label=stars&color=4BD4B3" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/illegalstudio/agentlog.nvim?style=flat-square&color=4BD4B3" alt="License: MIT"></a>
  <a href="https://neovim.io"><img src="https://img.shields.io/badge/Neovim-%E2%89%A5%200.10-4BD4B3?style=flat-square&logo=neovim&logoColor=white" alt="Neovim ≥ 0.10"></a>
  <a href="https://x.com/nahime0"><img src="https://img.shields.io/badge/Follow-%40nahime0-4BD4B3?style=flat-square&logo=x&logoColor=white" alt="Follow @nahime0 on X"></a>
</p>

<p align="center">
  <strong>Automatic source detection &middot; Structured document model &middot; Layered diff rendering &middot; Tree-sitter highlighting</strong>
</p>

<p align="center">
  agentlog.nvim turns terminal scrollback produced by AI agents — Codex and
  Claude Code, opened from Zellij — into a structured, navigable Neovim buffer
  without changing its original text.
</p>

---

## Requirements

- Neovim 0.10 or newer during the prototype phase
- A Tree-sitter parser for each language you want highlighted inside diffs

The minimum supported version will be finalized before the first public release.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "illegalstudio/agentlog.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter", -- Optional; enables immediate code highlighting.
  },
  opts = {
    -- auto_attach = true, -- Uncomment to enable automatic attachment.
  },
}
```

Calling `setup()` is optional. The commands are available with the default
configuration as soon as the plugin is on `runtimepath`.

## Usage

Open a scrollback dump and run:

```vim
:AgentlogAttach
```

The command detects the matching Codex or Claude adapter from the buffer.

The initial commands are:

- `:AgentlogAttach` — parse and render the current buffer;
- `:AgentlogRefresh` — rebuild the document and its decorations;
- `:AgentlogDetach` — remove decorations and restore the previous filetype;
- `:checkhealth agentlog` — inspect the local runtime.

Automatic attachment is off by default:

```lua
require("agentlog").setup({
  -- auto_attach = true, -- Uncomment to enable automatic attachment.
  render = {
    diff_background = true,
    diff_code_padding = 1,
  },
  syntax = {
    enabled = true,
    treesitter = true,
    max_region_lines = 500,
  },
})
```

When enabled, automatic attachment considers only `*.dump` files with a strong
Codex or Claude signature and enough independent evidence. Set
`vim.b.agentlog_disable = true` before `BufReadPost` to opt a buffer out.

For Codex `Edited` and Claude `Update` blocks, agentlog separates line numbers and
diff markers from the source, infers the language from the file path, and parses
normalized old and new snapshots. Claude `Write` previews receive the same syntax
highlighting without inventing a diff marker or visual padding. If a parser or
highlight query is unavailable, structural highlighting continues to work.
`diff_code_padding` inserts virtual screen cells, so the extra spacing never
changes copied text.

## Documentation

- [`doc/agentlog.txt`](doc/agentlog.txt) is the Neovim `:help agentlog` manual.
- [`docs/`](docs/README.md) contains internal architecture and development
  documentation for maintainers.

## Development

Run the headless test suite with:

```sh
make test
```

Real scrollback fixtures must be anonymized before being committed. See the
fixture notes under [`tests/fixtures/`](tests/fixtures/).

## Status

The immediate next milestone is to expand the anonymized Codex and Claude fixture
corpus, then add navigation, folding, copying, and coverage for additional output
variants.

## License

MIT © 2026 Vincenzo Petrucci. See [LICENSE](LICENSE).
