# ADOPTING

1. Preview: `DRY_RUN=1 scripts/adopt.sh <repo>` (default; writes nothing).
2. Apply: `DRY_RUN=0 scripts/adopt.sh <repo>`. Missing configs are copied;
   existing ones are kept and their diff against the template is printed, so
   you merge by hand. Running it again changes nothing.
3. In the repo: `./mk setup && ./mk ci`.

Every gate stays on. Legacy noise is recorded, never hidden by removing a gate:

| Noise | Where it is recorded |
|---|---|
| Lint findings | `#[expect(lint, reason = "...")]` at the site (fails once no longer needed) |
| Duplicate dependency versions | `deny.toml` `[bans] skip`, with a reason |
| Intentional duplicate code | `// echoes: allow` above the copy, with a reason |
| Mutants no test can kill | `mutants.toml` exclusion, with a comment |
| Coverage below 100% | `COVERAGE_FAIL_UNDER_LINES` in `mk.versions` set to today's value; only raise it |

Gates that cannot apply skip themselves with a reason (no library: semver; no
wasm32 target: wasm). Hooks and CI call `./mk` only.
