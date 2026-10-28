# Gap list vs rusti-graben template (lotus-initiative/lotus-explore-rs)

Repo: https://github.com/lotus-initiative/lotus-explore-rs (read-only analysis)

Notes:
- Uses `./mk` via cargo-make (`Makefile.toml` + `make/*.toml`), `cargo make --no-workspace` pattern mentioned in task - keep this lesson.
- Has prek.toml, tombi, typos, echoes/refquiem (internal), doctested READMEs, CLI help checks, stale references.
- Many advanced checks already present.

## Suggested PR families
1. **Hygiene parity**: Add missing gates from template (mutants scoped, coverage, semver, msrv, powerset) if valuable.
2. **CI hardening**: SHA-pin actions, permissions, concurrency, timeout-minutes.
3. **Adoption script compatibility**: Ensure adopt.sh doesn't clobber their existing `mk`/Makefile.toml; diff-before-overwrite is critical.
4. **Governance/docs**: Add templates/governance files if missing.

Report: keep their working runners; prepare per-gate-family PRs, not full rewrites.
