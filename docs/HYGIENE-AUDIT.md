# HYGIENE-AUDIT

## Gate evidence (what each catches)
| Gate | What it catches | Evidence it can fail |
|---|---|---|
| fmt | Unformatted code | `cargo fmt --check` fails |
| lint | Clippy violations (-D warnings) | Clippy reports errors |
| test | Logic regressions | Tests fail |
| doc | Broken docs/links under -D warnings | rustdoc fails |
| deny | License/advisory/source policy violations | cargo-deny fails |
| audit | Vulnerabilities | cargo-audit fails |
| typos | Spelling errors | typos fails |
| taplo | TOML formatting | taplo fails |
| machete | Unused deps | cargo-machete fails |
| msrv | MSRV incompatibility | cargo-msrv fails |
| semver | Breaking API changes (libs) | cargo-semver-checks fails |
| wasm | WASM target issues (if declared) | cargo check --target wasm32 fails |

Unknown tools cargo-dejadoc/cargo-echoes/cargo-refquiem not found on crates.io - removed/disabled; replaced by explicit checks or dropped. No commands ship that can pass without running.
