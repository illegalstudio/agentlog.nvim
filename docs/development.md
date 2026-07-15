# Development

## Prerequisites

- Neovim 0.10 or newer.
- `make` for the standard test command.
- Optional Tree-sitter parsers for manual syntax-highlighting checks.

The automated suite has no external Lua test framework dependency.

## Running tests

```sh
make test
```

The command starts Neovim headlessly with `tests/minimal_init.lua` and executes
the suites registered in `tests/run.lua`.

Tests currently cover:

- configuration defaults and merging;
- region validation;
- language inference;
- Codex, Claude, and Cursor detection and parsing;
- compact and unified diff metadata;
- attach, refresh, and detach integrity;
- layered diff extmarks;
- contextual Tree-sitter captures;
- structural fallback when syntax highlighting is disabled;
- positive, negative, and per-buffer opt-out behavior for automatic attachment;
- semantic action/diff/error/file/hunk/response targets, counts, direction, and wrap behavior;
- navigation commands and buffer-local mapping lifecycle;
- structured `gf` file opening and preservation of existing local mappings.

Generate help tags as a documentation check:

```sh
nvim --headless -u NONE -c 'helptags doc' -c 'qa!'
rm -f doc/tags
```

`doc/tags` is generated and ignored by Git.

## Manual testing

Load the repository directly without modifying a normal Neovim configuration:

```sh
nvim -u NONE \
  --cmd 'set runtimepath^=/absolute/path/to/agentlog.nvim' \
  --cmd 'runtime plugin/agentlog.lua' \
  /path/to/scrollback.dump
```

Then run:

```vim
:AgentlogAttach
:AgentlogRefresh
:AgentlogDetach
:AgentlogNext action
:AgentlogPrevious diff
:checkhealth agentlog
```

After attaching, also verify `[a`, `]a`, `[d`, `]d`, `[r`, `]r`, `[f`, `]f`,
`[e`, `]e`, `[h`, `]h`, counts such as `3]a`, jump-list return with `Ctrl-o`, and
`gf` on absolute, repository-relative, and Cursor workspace-relative paths,
including recognized line/column positioning.

For contextual syntax checks, use the normal Neovim configuration or explicitly
add the relevant parser and query directories to `runtimepath`.

## Fixture policy

Fixtures must come from representative sessions, but they must be anonymized
before commit. Remove credentials, client names, personal paths, proprietary
source, and unrelated output.

See the Codex, Claude, and Cursor notes under
[`tests/fixtures/`](../tests/fixtures/) for the fixture checklist and captured
formats. Small synthetic inputs are acceptable in unit tests but must not be
presented as representative captured sessions.

When adding a new output variant:

1. preserve a minimal anonymized sample;
2. annotate the expected regions and metadata;
3. add a negative case that looks similar but must stay neutral;
4. update the adapter's declarative patterns or state machine;
5. verify that attach and refresh leave the input unchanged.

## Adding an adapter

1. Create `lua/agentlog/adapters/<name>.lua`.
2. Implement `parse(lines, context)` and return a document from
   `agentlog.document`.
3. Optionally implement `detect(lines, context)` with independent evidence and a
   confidence score.
4. Register the adapter in `lua/agentlog/adapters/init.lua`.
5. Add unit fixtures for complete, truncated, ambiguous, and negative inputs.
6. Confirm that no renderer needs agent-specific branching.

Adapter parsing must not execute commands, resolve shell substitutions, write
files, or evaluate text from the scrollback.

## Adding a language

Add the extension mapping to `lua/agentlog/language.lua`. Use the parser language
name expected by `vim.treesitter.get_string_parser()`.

Test both paths:

- parser and `highlights` query available;
- parser missing or syntax explicitly disabled.

The second path must retain semantic diff highlighting without raising an error.

## Performance guardrails

- Keep initial parsing linear in the number of lines.
- Do not parse advanced syntax above `syntax.max_region_lines`.
- Reuse one namespace and clear it before rerendering.
- Avoid work on cursor movement; rendering happens on attach or refresh.
- Keep snapshot failures isolated so one missing parser cannot abort attachment.
- Verify large changes with representative 1,000-, 10,000-, and 100,000-line
  inputs as the fixture corpus grows.

## Documentation ownership

- `doc/agentlog.txt` is the installed Neovim user manual.
- `README.md` is the public project overview.
- `docs/` contains maintainer-facing architecture and development material.
- `tests/fixtures/` documents captured-format expectations alongside test data.

Behavior changes should update the user manual and internal documentation when
they affect both audiences.

## Near-term priorities

1. Grow the anonymized Codex, Claude, and Cursor fixture corpus.
2. Cover more compact diff and truncated-scrollback variants.
3. Complete the navigation follow-ups below.
4. Add folding and copy commands without mutating buffer text.
5. Enable automatic attachment only after broader negative detection coverage.

## Navigation follow-ups

Navigation currently covers actions, changed diff blocks, assistant responses,
file occurrences, explicit unified-diff hunks, errors/warnings, and structured
file opening. Follow-up work should add:

1. contextual `<CR>` behavior after folding exists, so opening a file and
   expanding a block are unambiguous;
2. tests for mapping changes applied to buffers that are already attached.
