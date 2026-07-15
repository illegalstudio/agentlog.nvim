# Architecture

agentlog.nvim turns terminal scrollback into a structured document and renders
that structure without modifying the original buffer text.

## Core invariants

1. Buffer contents remain unchanged during attach, refresh, and detach.
2. Recognition is conservative: ambiguous text stays `unknown`.
3. Structural rendering works without Tree-sitter or language-specific parsers.
4. Parsing is line-oriented and linear in the size of the inspected input.
5. Source detection, agent parsing, document representation, and rendering are
   independent layers.

## Data flow

```text
Neovim buffer
    ↓
Source detector
    ↓
Agent adapter
    ↓
Structured region document
    ├── Semantic renderer
    ├── Diff renderer
    ├── Contextual syntax renderer
    └── Semantic navigator
```

Manual attachment scores enabled adapters and selects the best source carrying an
explicit agent signature, falling back to Codex when no signature is available.
Automatic attachment additionally requires the configured confidence threshold.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `plugin/agentlog.lua` | Defines user commands and bootstraps defaults. |
| `lua/agentlog/init.lua` | Public Lua API. |
| `lua/agentlog/config.lua` | Defaults and deep configuration merging. |
| `lua/agentlog/attach.lua` | Per-buffer lifecycle and state. |
| `lua/agentlog/detect.lua` | Adapter scoring and buffer sampling. |
| `lua/agentlog/document.lua` | Region validation, normalization, and traversal. |
| `lua/agentlog/navigation.lua` | Semantic targets, cursor jumps, and file opening. |
| `lua/agentlog/adapters/` | Agent-specific detection and parsing. |
| `lua/agentlog/render.lua` | Extmarks for semantic regions and diff layers. |
| `lua/agentlog/highlight.lua` | Semantic groups and colorscheme integration. |
| `lua/agentlog/language.lua` | File-extension to parser-language mapping. |
| `lua/agentlog/syntax.lua` | Normalized snapshots and Tree-sitter remapping. |
| `lua/agentlog/health.lua` | `:checkhealth agentlog` checks. |

## Region document

Adapters produce documents containing normalized regions:

```lua
{
  kind = "diff",
  start_row = 12, -- zero-based, inclusive
  end_row = 13,   -- zero-based, exclusive
  source = "codex",
  confidence = 1,
  metadata = {},
  children = {},
}
```

Rows use Neovim's zero-based indexing. A region owns semantic metadata but does
not render itself. Renderers consume the same document independently.

Current region kinds include prompts, responses, actions, output, interface
metadata, file references, unified-diff headers and hunks, compact diff rows,
errors, warnings, and unknown text.

## Attachment lifecycle

`attach.lua` stores state by buffer number:

- selected source and transport;
- parsed region document;
- original filetype.

Attaching an already attached buffer performs a refresh. Refresh reparses first,
clears the plugin namespace, and renders a new document, which keeps the operation
idempotent. Detach clears decorations and restores the previous filetype.

State is discarded on `BufUnload` and `BufWipeout`. Buffer-local navigation
mappings are installed after the `agentlog` filetype is set, so an existing
buffer-local mapping takes precedence. Detach removes only mappings that still
carry agentlog's own description. The plugin never executes commands found in
scrollback and never writes to referenced files.

## Navigation

`navigation.lua` derives destinations from the same parsed region document used
by the renderers. Action and response navigation target every region of the
corresponding kind. Diff navigation groups regions by `diff_id`, chooses the
first row of the group, and requires either a diff header/hunk or at least one
added/deleted row. Consecutive changed rows without a `diff_id` form a fallback
target for truncated scrollback. Context-only previews are intentionally
excluded from diff navigation.

File navigation groups every region carrying `metadata.path` by `diff_id`, so an
action heading, its file-reference continuation, and all preview rows remain one
destination. Consecutive path-bearing regions without a `diff_id` are grouped by
path as a fallback. Unlike diff navigation, context-only `Read` previews qualify.

Diagnostic navigation combines `error` and `warning` regions. Adjacent diagnostic
rows collapse into one target, preventing a compiler error followed by its build
warning from requiring two jumps while preserving separate diagnostic blocks.

Hunk navigation targets `diff_hunk` regions directly. These correspond to
explicit `@@ ... @@` headers in unified diffs and remain distinct from the single
file-level target produced by diff navigation. Compact previews do not synthesize
hunk boundaries because the source format does not preserve them.

The target search is independent of cursor movement and supports direction,
counts, and optional wrapping. The final move uses a normal line jump inside the
buffer's window so Neovim records it in the jump list.

File opening uses only `metadata.path` from a region containing the cursor. The
path is normalized relative to Neovim's current working directory and must exist
before `:edit` is called with an escaped filename. When no structured path is
available, the `gf` mapping delegates to Neovim's native command.

## Codex adapter

The Codex adapter currently recognizes:

- action headings such as `Ran`, `Edited`, `Added`, `Deleted`, `Explored`, `Read`,
  and `Searched`;
- assistant prose responses while excluding known tool and interface status
  bullets;
- top-level warning notices and conservatively matched command errors such as
  compiler errors, fatal errors, panic output, missing files, and failed tests;
- indented action output;
- single-file `Edited`, `Added`, and `Deleted` blocks, plus multi-file `Edited`
  blocks;
- standard unified diffs;
- Codex compact rows containing a line number, diff marker, and source text.

Compact rows carry enough metadata to render each visual layer separately:

```lua
{
  path = "/tmp/example.php",
  language = "php",
  diff_id = 1,
  line_type = "add",
  line_number = 12,
  line_number_col = 4,
  line_number_end_col = 6,
  marker_col = 7,
  content_col = 8,
  code = "return $value;",
}
```

The original prefix remains in the buffer. Column metadata lets renderers operate
on the meaningful parts without rewriting the line.

## Claude adapter

The Claude adapter recognizes:

- the Claude Code banner and interface metadata;
- user prompts, assistant responses, warnings, and progress rows;
- tool calls and their structured output;
- shell-command and search summaries;
- `Update` compact diffs;
- numbered `Write` and `Read` source previews.

`Update` rows use the same normalized compact-diff metadata as Codex. A `Write`
preview has line numbers and source but no visual diff marker, so it is modeled as
added source with `marker_col = nil`. This enables Tree-sitter and muted added-line
backgrounds without inserting artificial padding. Tool state survives blank rows
and wrapped result paths before the numbered source begins. `Read` previews are
contextual source and do not receive an added/deleted background.

## Cursor Agent adapter

The Cursor adapter recognizes the CLI banner and version, read/search/edit and
shell actions, collapsed output, todo progress, file references, command output,
and footer interface rows. `Edited` previews use `▎` as a structural border and
carry normalized context/add/delete metadata without modifying the visible text.
Truncated preview paths are retained as `display_path` only, so navigation never
tries to open a path Cursor has abbreviated with an ellipsis.

Cursor's plain scrollback does not preserve a textual prompt/response marker on
every turn. The first prompt after the banner and the first top-level prose after
known tool activity are classified when the state machine can prove the boundary;
later ambiguous prose remains `unknown`. This keeps response navigation useful
without guessing that every paragraph starts a new turn.

## Rendering layers

All decorations use one dedicated namespace. Compact diff rows are rendered as
independent layers:

1. line number using `AgentlogDiffLineNumber`;
2. marker using `AgentlogDiffAdd`, `AgentlogDiffDelete`, or the context group;
3. muted add/delete background starting at the source column;
4. inline virtual padding between marker and source;
5. Tree-sitter captures at higher priority.

Muted backgrounds are derived from the active colorscheme's standard diff groups.
The padding uses inline virtual text in `replace` mode, so it has the same muted
background and never changes copied content. Cursor previews already encode
separator spacing after `▎`, so their renderer path skips configured padding.

## Contextual Tree-sitter highlighting

Diff prefixes make the visible lines invalid source code. `syntax.lua` therefore
groups rows by `diff_id` and builds two internal strings:

- old snapshot: context plus deleted lines;
- new snapshot: context plus added lines.

Each snapshot stores a row and column mapping back to the original buffer. A
string parser and the language's `highlights` query produce captures, which are
translated into extmarks on the visible rows.

PHP snippets without an opening tag receive a synthetic `<?php` line only in the
internal snapshot. Tree-sitter failures are isolated per snapshot; semantic diff
rendering remains active. Regions larger than `syntax.max_region_lines` skip
advanced parsing.

## Detection

The detector samples at most the first 2,000 lines and combines independent
signals such as Codex actions, Claude's banner and turn markers, Cursor's banner
and version, structured tool output, code previews, dump extension, temporary or
Zellij paths, and readonly state. A filename alone is insufficient for a
confident attachment.

When adapters have the same confidence, the detector prefers the candidate with
the more specific agent signature. An explicit Cursor or Claude banner therefore
wins over generic action patterns that another adapter can also recognize.

Automatic attachment is limited to normal `*.dump` buffers and requires both a
supported agent signature and the configured confidence score. It is off by
default while the fixture corpus grows. `vim.b.agentlog_disable = true` opts one
buffer out without disabling manual attachment.

## Extension points

New agents should be implemented as adapters registered through
`lua/agentlog/adapters/init.lua`. An adapter may expose `detect(lines, context)`
and must expose `parse(lines, context)`.

Rendering code should remain agent-agnostic. New source languages normally require
only an extension mapping in `language.lua` and tests showing graceful behavior
with and without the parser.
