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
    └── Contextual syntax renderer
```

Manual attachment selects the Codex adapter directly. Automatic attachment first
scores enabled adapters and proceeds only when the configured confidence threshold
is met.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `plugin/agentlog.lua` | Defines user commands and bootstraps defaults. |
| `lua/agentlog/init.lua` | Public Lua API. |
| `lua/agentlog/config.lua` | Defaults and deep configuration merging. |
| `lua/agentlog/attach.lua` | Per-buffer lifecycle and state. |
| `lua/agentlog/detect.lua` | Adapter scoring and buffer sampling. |
| `lua/agentlog/document.lua` | Region validation, normalization, and traversal. |
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

Current region kinds include actions, output, file references, unified-diff
headers and hunks, compact diff rows, errors, warnings, and unknown text.

## Attachment lifecycle

`attach.lua` stores state by buffer number:

- selected source and transport;
- parsed region document;
- original filetype.

Attaching an already attached buffer performs a refresh. Refresh reparses first,
clears the plugin namespace, and renders a new document, which keeps the operation
idempotent. Detach clears decorations and restores the previous filetype.

State is discarded on `BufUnload` and `BufWipeout`. The plugin never executes
commands found in scrollback and never writes to referenced files.

## Codex adapter

The Codex adapter currently recognizes:

- action headings such as `Ran`, `Edited`, `Explored`, `Read`, and `Searched`;
- indented action output;
- single-file and multi-file `Edited` blocks;
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
background and never changes copied content.

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
signals such as Codex actions, diff formats, dump extension, Zellij paths, and
readonly state. A filename alone is insufficient for a confident attachment.

Automatic attachment is off by default while the fixture corpus grows.

## Extension points

New agents should be implemented as adapters registered through
`lua/agentlog/adapters/init.lua`. An adapter may expose `detect(lines, context)`
and must expose `parse(lines, context)`.

Rendering code should remain agent-agnostic. New source languages normally require
only an extension mapping in `language.lua` and tests showing graceful behavior
with and without the parser.
