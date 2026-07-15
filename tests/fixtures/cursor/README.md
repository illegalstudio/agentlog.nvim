# Cursor Agent fixture

`session.dump` is an anonymized and shortened Cursor Agent CLI v2026.07.09
terminal session. It preserves the significant display forms from the captured
session:

- banner, version, tip, unmarked conversational text, and footer rows;
- grouped read/search summaries and collapsed history;
- todo progress and completion rows;
- `Edited` previews with context, added, deleted, blank, and truncated rows;
- shell commands, collapsed output, ordinary output, and a failed command;
- standalone file references with line ranges and a workspace-root footer.

Hostnames, repository names, paths, prompts, source code, and deployment output
were replaced before committing the fixture. As the CLI does not preserve an
explicit marker for every conversational turn in plain scrollback, the fixture
expects ambiguous later prompts to remain neutral.
