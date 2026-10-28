# AGENTS.md

This repository follows the rusti-graben hygiene baseline.

- **Single entrypoint**: Always use `./mk <task>`. CI and local runs must be identical.
- **No direct tool invocation**: Do not call cargo/rustfmt/clippy/typos/etc directly in CI scripts; add tasks to `mk`.
- **Strict lints**: `unsafe_code = forbid`, `unwrap_used = deny` at workspace level. Do not weaken gates.
- **Pre-commit**: Use `prek` (hooks must call `./mk`). Slow gates stay out of fast hooks.
- **Adoption**: Use `scripts/adopt.sh` (idempotent, dry-run by default).
