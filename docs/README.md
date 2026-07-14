# Internal project documentation

This directory contains engineering documentation for agentlog.nvim maintainers
and contributors.

It is intentionally separate from [`doc/`](../doc/), which follows Neovim's
runtime convention and contains the user-facing `:help agentlog` manual.

## Contents

- [Architecture](architecture.md) — data flow, module boundaries, region model,
  rendering layers, and Tree-sitter integration.
- [Development](development.md) — local workflow, testing, fixtures, extension
  points, and engineering guardrails.

Future design notes, adapter specifications, performance investigations, and
architectural decisions should live here. User-facing behavior should also be
reflected in [`doc/agentlog.txt`](../doc/agentlog.txt).
