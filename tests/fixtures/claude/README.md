# Claude fixture

`session.dump` is an anonymized and shortened Claude Code v2.1.209 terminal
session. It preserves the significant display forms from the captured session:

- banner, warning, prompt, response, progress, and interface rows;
- expanded `Write` output with a blank separator, wrapped path, and numbered
  source without diff markers;
- `Update` output with compact context, added, and deleted rows;
- progress UI and shell-command summaries.

Names, paths, prompts, and source code were replaced before committing the
fixture. Future captures must follow the same anonymization requirements as the
Codex fixtures.
