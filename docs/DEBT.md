# Technical Debt & Ratchet Ledger

Every unavoidable lint suppression, duplicate-dependency skip, echoes/coverage ratchet, or mutation exclusion in this repository is recorded here with its reason, owner, and removal condition.

## Active Exceptions

| Location | Gate / Lint | Reason | Owner | Removal Condition |
|---|---|---|---|---|
| `Cargo.toml` (`[workspace.lints.clippy]`) | `redundant_pub_crate = "allow"` | Contradicts `rustc`'s `unreachable_pub` lint (one demands `pub(crate)`, the other `pub`). | `@Adafede` | Upstream `clippy` / `rustc` lint reconciliation. |
| `crates/sample-bin/src/main.rs` | `#[expect(clippy::print_stdout, reason = "...")]` | Intentional CLI output of the sample binary. | `@Adafede` | Permanent (CLI binary edge). |

## Ratchet Floors (`mk.local`)

- `COVERAGE_FAIL_UNDER_LINES="100"`
- `ECHOES_MAX_APPROXIMATE=0`
- `ECHOES_MAX_REUSE=0`
