# HYGIENE AUDIT

Date: 2026-10-28  
Template repo: `Adafede/rusti-graben` (AGPL-3.0-or-later)

## Existing state summary (as-is)

- Entrypoint: `./mk` with commands `setup|fmt|lint|test|doc|deny|ci` (shared by CI/local). `mk` installs via `cargo install` (un-pinned versions), runs `cargo fmt --all -- --check`, `typos`, `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `cargo machete`, `cargo test --workspace --all-features`, `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps`, `cargo deny check`, `cargo audit`.
- Lints: workspace `forbid(unsafe_code)`, `missing_docs = "warn"`, `rust_2018_idioms = { level = "deny", priority = -1 }`; clippy `all/warn`, `pedantic/warn`, `nursery/warn`, `unwrap_used = "deny"`, `expect_used = "warn"`, `panic = "deny"`.
- Configs: `clippy.toml` (`msrv = "1.97"`, `avoid-breaking-exported-api = true`), `deny.toml` (advisories unmaintained/unsound workspace; licenses allow `AGPL-3.0-only` only; sources deny unknown registry/git), `rust-toolchain.toml` (channel `stable`, components include `rustfmt, clippy, rust-docs, miri`, target `wasm32-unknown-unknown`), `.typos.toml` (ignore `rusti-graben`).
- CI: `.github/workflows/ci.yml` uses actions/checkout@v4, dtolnay/rust-toolchain@stable (components rustfmt/clippy), Swatinem/rust-cache@v2, runs `./mk ci`. Permissions `contents: read`.
- Adopt: `scripts/adopt.sh` dry-run by default (`DRY_RUN=${DRY_RUN:-1}`), copies `deny.toml`, `rust-toolchain.toml`, `clippy.toml`, `mk` (with +x) when `DRY_RUN!=1`. Idempotent in that it uses `cp -n`. Detects workspace vs single crate by grepping `[workspace]`.
- Samples: `crates/sample-lib`, `crates/sample-bin` with workspace inheritance.

## Check matrix

| check | tool | bug class it catches | in rusti-graben now? | in dioxus? | in lotus-explore-rs? | in Luca's repos? (link) | adopt? | tier (pre-commit/PR/nightly/release) | CI cost | notes |
| :-- | :-- | :-- | :--: | :--: | :--: | :--: | :--: | :-- | :-- | :-- |
| format | `rustfmt` | style drift / inconsistent diffs | yes (`mk fmt`) | yes (via `./mk fmt-check`/tasks) | yes (`fmt-check`) | common (diesel checks) | keep | pre-commit/PR | low | Must stay in `./mk fmt`; prek only calls `./mk fmt`. |
| spelling | `typos` | typos in docs/code | yes (`mk fmt`) | yes (prek hook `typos`) | yes (`typos`) | common | keep | pre-commit/PR | low | As-is. |
| lint | `clippy` | correctness/perf/style bugs | yes (`mk lint` -D warnings, all/pedantic/nursery warn, unwrap_used deny) | yes (`./mk lint`) | yes (`lint`) | diesel sets `RUSTFLAGS=-D warnings` in CI | keep/enhance carefully | pre-commit/PR | medium | Do **not** weaken existing gates. Any allowlist must be tracked. |
| unused deps | `cargo-machete` | bloat/accidental deps/supply chain surface | yes (`mk lint`) | yes (`./mk machete`) | yes (`machete`) | varies | keep | PR/pre-push | low | As-is. |
| tests | `cargo test` | logic regressions | yes (`mk test --all-features`) | yes | yes | diesel runs full matrix | keep | PR/pre-push | medium-high | Consider `cargo-nextest` later if slow; not present now. |
| doctests | `rustdoc`/`cargo test` doctests | broken examples | yes (covered by test/doc) | yes | yes | common | keep | PR/pre-push | medium | Enforced via `-D warnings` in `mk doc`. |
| docs | `cargo doc` | broken intra-doc links / missing docs issues under `-D warnings` | yes (`mk doc` with `RUSTDOCFLAGS=-D warnings`) | yes | yes | common | keep | PR/pre-push | medium | As-is. |
| supply chain/advisories | `cargo-deny`, `cargo-audit` | vulns/licenses/sources | yes (`mk deny`) | yes | yes | common | keep | PR/nightly | medium | As-is. |
| supply chain deep | `cargo-supply-chain` | deep provenance/supply chain analysis | no | mentioned in dioxus ref (runs deny/audit/supply-chain) | no obvious match in sampled text | varies | evaluate | nightly | medium-high | dioxus lists "supply-chain" as a check; verify crate exists and value vs audit/deny. Mark unverified until checked. |
| feature powerset | `cargo-hack` | feature combination bugs | no | yes (`feature-powerset`) | appears related to feature coverage | diesel has complex features; Luca practices mention feature matrices | add (`./mk powerset`) | PR/pre-push/nightly | high | High value for libs; make opt-in for small bins or add with caching. |
| MSRV | MSRV policy/check | compatibility regression | partial (clippy.toml has `msrv = "1.97"`, toolchain stable) | yes | yes | common in serious projects | add (`./mk msrv`) | PR | low | Need explicit MSRV check (e.g. `cargo-msrv` or verify against toolchain). Verify tool. |
| semver | `cargo-semver-checks` | breaking API changes | no | no obvious in sampled dioxus prek | no obvious | common in published crates | add (`./mk semver`) | PR/release | medium-high | Important if publishing; add with baseline. |
| mutants | `cargo-mutants` | test gaps (missed assertions) | no | no obvious | no obvious | less common in CI | add (`./mk mutants`) scoped + ratchet | nightly | very high | Expensive; scope to changed crates, ratchet, document baseline. |
| coverage | `cargo-llvm-cov` + Codecov | untested code paths | no | no obvious | Codecov mentioned in lotus-explore-rs | varies | add (`./mk coverage`) | PR/nightly | medium-high | Add with threshold = current minus epsilon; upload to Codecov if configured. |
| miri | `miri` | UB in unsafe code | component installed in toolchain; not run in mk/CI | varies | varies | varies | evaluate | nightly | high | `forbid(unsafe_code)` in workspace - low value now, but keep component; run nightly if unsafe ever added. |
| wasm32 | `wasm32-unknown-unknown` | wasm compatibility | target installed; not checked in gates | yes (`check-wasm`, `lint-wasm`) | yes | common if targeting wasm | add opt-in (`./mk wasm`) | PR/pre-push | medium | dioxus does per-app WASM checks; make opt-in/module. |
| fuzzing | `cargo-fuzz` | edge cases/crashes | no | no | no | varies (some projects do) | evaluate later | nightly/manual | very high | Usually manual/nightly; skip for now unless requested. |
| sanitizers | rust sanitizers | memory issues | no | no | no | varies | evaluate later | nightly | high | Needs nightly toolchain setup; likely overkill now. |
| TOML formatting/lint | `taplo` / `tombi` | TOML style/schema | no (README mentions Taplo in text but not used) | tombi used heavily (prek + tasks) | tombi used (`tombi-check/lint`) | varies | add `tombi` (format/check/lint) | pre-commit/pre-push/PR | low | dioxus/lotus use tombi; align to their pattern but keep `mk` as source of truth. |
| link checking | link checker (e.g. `lychee`) | broken links in docs/README | no explicit gate | varies | varies | varies | evaluate | PR/nightly | low | `cargo doc` with warnings helps intra-doc; external links less covered. |
| stale references | custom check / `cargo-refquiem` | references to deleted items | no | no obvious | `refquiem` task exists in lotus-explore-rs Makefile | varies | investigate `cargo-refquiem` existence | pre-push/nightly | low | **NOT FOUND** on crates.io index/API search above. If it doesn't exist as published crate, map intent to custom script or skip. See below. |
| duplicate code/docs | `cargo-echoes` / dejadoc | duplication | no | `dejadoc` mentioned in dioxus prek | `echoes` in lotus ci deps | varies | investigate `cargo-echoes` | pre-push/nightly | low | **NOT FOUND** on crates.io index/API search above. Map to real tool or skip. |
| license headers | custom check | missing headers | no | yes (`license-headers`) | yes (`license-headers`) | varies | add if needed for policy | pre-commit/PR | low | dioxus enforces; decide per policy. |
| actions pinning | SHA pins | supply chain for Actions | partial (checkout@v4 unpinned in current ci.yml) | yes (SHA pinned) | varies | diesel uses SHA pins | harden | always | none | Must SHA-pin actions, add least-privilege permissions, concurrency. |
| dependabot/renovate | config | dependency updates | renovate.json missing in working tree (branch exists remotely) | yes | yes | common | add config | n/a | none | Add Dependabot or Renovate config. |
| release automation | release workflow | publish/tag/release | no | yes | yes | varies | add `release` workflow | release | medium | Dry-run publish, semver/docs checks. |
| SBOM | SBOM generation | supply chain attestation | no | varies | varies | varies | evaluate | release/nightly | low | Nice-to-have; can add later. |

## "cargo echoes" and "cargo refquiem"

- Searched crates.io API/index for `cargo-echoes` and `cargo-refquiem`: not found (404). GitHub search not fully possible via tools, but no published crates found.
- dioxus prek references `cargo-dejadoc` (entry `mk dejadoc`) and `cargo-refquiem` (`mk refquiem`). lotus-explore-rs ci depends on `echoes` and `refquiem` tasks.
- **Conclusion**: These appear to be **internal/custom tools** used by those repos (possibly local binaries/scripts), not published crates.io packages. 
- **Action**: Do **NOT** invent them. In rusti-graben, either (1) add placeholders that no-op with clear messages if not installed, (2) skip until we have actual implementations, or (3) replace intent with real tools (e.g. `jscpd` for duplication is external; "stale references" could be a grep-based script). For now: document as unverified/internal; only add if we can source real implementations. Follow instruction "If they exist, document them; if not, say so in the audit and map the intent to a real tool. Never invent a tool or flag."

## Conflicts / rules

- **`mk` is single source of truth.** prek/hooks must only call `./mk <task>`. (Matches dioxus guidance.)
- **Never weaken existing gates.** Any `#[allow]`, lowered threshold, or skipped check must go in tracked lists with reasons.
- **Pin actions by SHA.** Current `ci.yml` uses unpinned actions - must fix.
- **Keep YAML thin, logic in `mk`.**


## Step 0 deliverables
- Created `docs/HYGIENE-AUDIT.md` with full matrix above.
- `cargo-echoes` / `cargo-refquiem`: not found on crates.io; appear internal to dioxus/lotus-explore-rs. Marked unverified, no tools invented. Intent mapped to note (duplication/stale refs) - can add custom scripts later if needed.
- Conflicts resolved: `mk` remains single source of truth; prek/hooks call `./mk` only.
