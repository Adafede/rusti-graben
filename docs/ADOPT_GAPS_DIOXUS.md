# Gap list vs rusti-graben template (Adafede/dioxus)

Repo: https://github.com/Adafede/dioxus (read-only analysis)

Notes:
- Keep their working runners (dioxus uses prek + Makefile.toml; rusti-graben uses `./mk` as single source of truth). 
- prek hooks must only call `./mk <task>` if adopting rusti-graben style; otherwise preserve their existing model but align to "mk is single source of truth" rule.
- dioxus has rich checks (deny, audit, supply-chain, machete, license, tree-d, outdated, wasm32 checks) - many overlap.

## Suggested PR families
1. **CI/unification**: Ensure CI uses single entrypoint consistent with policy; SHA-pin actions; add concurrency/permissions.
2. **Tooling surface**: Add `./mk` tasks for missing gates (mutants/coverage/semver/msrv/powerset/wasm) if desired, but don't replace Makefile.toml.
3. **Config hygiene**: Align clippy/deny/rust-toolchain to template where compatible; add prek calling mk if migrating.
4. **Governance**: Add AGENTS.md/CONTRIBUTING/SECURITY/CODEOWNERS/templates if missing.

Report: keep existing `mk` tasks/prek config; adopt incrementally. If tool versions conflict, report and decide.
