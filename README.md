# agentlog.nvim

> Make AI agent scrollback readable.

`agentlog.nvim` turns terminal scrollback produced by AI agents into a structured,
navigable Neovim buffer without changing its original text.

The first supported path is Codex scrollback opened from Zellij. The project is
currently in its initial scaffold phase: manual attachment, the document/adapter
boundary, basic semantic highlighting, and dependency-free headless tests are in
place. Automatic attachment remains disabled until it is backed by representative,
anonymized fixtures.

## Requirements

- Neovim 0.10 or newer during the prototype phase

The minimum supported version will be finalized before the first public release.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "illegalstudio/agentlog.nvim",
  opts = {},
}
```

Calling `setup()` is optional. The commands are available with the default
configuration as soon as the plugin is on `runtimepath`.

## Usage

Open a scrollback dump and run:

```vim
:AgentlogAttach
```

The initial commands are:

- `:AgentlogAttach` — parse and render the current buffer;
- `:AgentlogRefresh` — rebuild the document and its decorations;
- `:AgentlogDetach` — remove decorations and restore the previous filetype;
- `:checkhealth agentlog` — inspect the local runtime.

Automatic detection exists only as an experimental boundary and is off by default:

```lua
require("agentlog").setup({
  auto_attach = false,
})
```

## Development

Run the headless test suite with:

```sh
make test
```

Real scrollback fixtures must be anonymized before being committed. See
`tests/fixtures/codex/README.md` for the fixture policy.

## Status

The immediate next milestone is to collect and annotate representative Codex
scrollbacks, then expand the adapter from the current conservative recognizers into
the region model described in the development plan.

The license for the first public release has not been selected yet.
