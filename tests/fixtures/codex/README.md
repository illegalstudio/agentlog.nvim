# Codex fixture policy

Only commit scrollback captured from real sessions after removing:

- secrets and credentials;
- client and project names;
- personal filesystem paths;
- proprietary source code and output.

Each fixture should document the Codex version when known, the transport used to
capture it, and which regions are expected. Synthetic inputs may be used inside
small unit tests, but they must not be presented as representative fixtures.
