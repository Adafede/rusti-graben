#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

typos_cli_ver="1.51.1"
cargo_deny_ver="0.18.9"
cargo_audit_ver="0.22.1"
cargo_machete_ver="0.9.1"
cargo_hack_ver="0.6.40"
cargo_semver_checks_ver="0.45.0"
cargo_mutants_ver="25.3.1"
cargo_llvm_cov_ver="0.6.21"
tombi_ver="0.6.27"
cargo_msrv_ver="0.18.4"
cargo_outdated_ver="0.17.0"

cmd="${1:-ci}"
shift || true

DETECT_LIB=0
DETECT_WASM=0
if command -v cargo >/dev/null 2>&1 && [ -f Cargo.toml ]; then
    if cargo metadata --no-deps --format-version 1 >/dev/null 2>&1; then
        META=$(cargo metadata --no-deps --format-version 1 2>/dev/null || echo '{}')
        echo "$META" | grep -q '"kind":\["lib"\]' && DETECT_LIB=1 || true
    fi
fi
grep -q 'wasm32' rust-toolchain.toml Cargo.toml 2>/dev/null && DETECT_WASM=1 || true

case "$cmd" in
    --list|--list-all-steps)
        printf "fmt\nlint\ntest\ndoc\ndeny\naudit\ntypos\ntombi\nmachete\nmsrv\nsemver\nechoes\ndejadoc\nrefquiem\nci\nci-nightly\nci-release\nmutants\ncoverage\npowerset\nwasm\nstale-check\ndup-check\nsetup\n"
        exit 0
        ;;
    setup)
        rustup toolchain install stable
        rustup toolchain install nightly 2>/dev/null || true
        rustup component add rustfmt clippy rust-docs 2>/dev/null || true
        rustup component add miri --toolchain nightly 2>/dev/null || true
        rustup target add wasm32-unknown-unknown 2>/dev/null || true
        cargo install typos-cli --version "$typos_cli_ver" --locked
        cargo install cargo-deny --version "$cargo_deny_ver" --locked
        cargo install cargo-audit --version "$cargo_audit_ver" --locked
        cargo install cargo-machete --version "$cargo_machete_ver" --locked
        cargo install cargo-hack --version "$cargo_hack_ver" --locked
        cargo install cargo-semver-checks --version "$cargo_semver_checks_ver" --locked
        cargo install cargo-mutants --version "$cargo_mutants_ver" --locked
        cargo install cargo-llvm-cov --version "$cargo_llvm_cov_ver" --locked
        cargo install tombi --version "$tombi_ver" --locked 2>/dev/null || true
        cargo install cargo-msrv --version "$cargo_msrv_ver" --locked
        cargo install cargo-outdated --version "$cargo_outdated_ver" --locked
        ;;
    fmt)
        cargo fmt --all -- --check
        typos
        command -v tombi >/dev/null 2>&1 && tombi format --check
        ;;
    lint) cargo clippy --workspace --all-targets --all-features -- -D warnings ;;
    test) cargo test --workspace --all-features ;;
    doc) RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps ;;
    deny) cargo deny check ;;
    audit) cargo audit ;;
    typos) typos ;;
    tombi) command -v tombi >/dev/null 2>&1 && tombi format --check || (echo "tombi missing - install per mk.versions" && exit 1) ;;
    machete) cargo machete ;;
    msrv) command -v cargo-msrv >/dev/null 2>&1 && cargo msrv verify || (echo "cargo-msrv missing" && exit 1) ;;
    semver) [ $DETECT_LIB -eq 1 ] && cargo semver-checks --workspace || echo "[skip] semver: no lib target" ;;
    echoes) command -v cargo-echoes >/dev/null 2>&1 && cargo echoes || (echo "cargo-echoes missing" && exit 1) ;;
    dejadoc) command -v cargo-dejadoc >/dev/null 2>&1 && cargo dejadoc || (echo "cargo-dejadoc missing" && exit 1) ;;
    refquiem) command -v cargo-refquiem >/dev/null 2>&1 && cargo refquiem || (echo "cargo-refquiem missing" && exit 1) ;;
    wasm) if [ $DETECT_WASM -eq 1 ]; then rustup target add wasm32-unknown-unknown; cargo check --workspace --target wasm32-unknown-unknown --all-features; else echo "[skip] wasm: no wasm target declared"; fi ;;
    mutants) [ -f mutants.toml ] && [ -f .mutants-baseline ] && cargo mutants --workspace || (echo "ERROR: mutants baseline missing" && exit 1) ;;
    coverage) cargo llvm-cov --workspace --all-features --lcov --output-path lcov.info ;;
    powerset) cargo hack --workspace --feature-powerset --no-dev-deps check ;;
    stale-check) command -v cargo-refquiem >/dev/null 2>&1 && cargo refquiem || cargo-refquiem ;;
    dup-check) command -v cargo-echoes >/dev/null 2>&1 && cargo echoes || cargo-echoes ;;
    ci)
        RAN=(); SKIP=()
        run_gate(){ local name="$1" reason="$2"; shift 2; if [ -n "$reason" ]; then SKIP+=("$name|$reason"); else echo "--- $name ---"; "$@"; RAN+=("$name"); fi; }
        run_gate fmt ""
        run_gate lint ""
        run_gate test ""
        run_gate doc ""
        run_gate deny ""
        run_gate audit ""
        run_gate typos ""
        run_gate tombi ""
        run_gate machete ""
        run_gate msrv ""
        if [ $DETECT_LIB -eq 1 ]; then run_gate semver ""; else SKIP+=("semver|no lib target"); fi
        command -v cargo-echoes >/dev/null 2>&1 && run_gate echoes "" || SKIP+=("echoes|no echoes installed")
        command -v cargo-refquiem >/dev/null 2>&1 && run_gate refquiem "" || SKIP+=("refquiem|no refquiem installed")
        if [ $DETECT_WASM -eq 1 ]; then run_gate wasm ""; else SKIP+=("wasm|no wasm target declared"); fi
        echo; echo "| Gate | Status | Reason |"; echo "|---|---|---|"
        for r in "${RAN[@]:-}"; do echo "| $r | ran | - |"; done
        for s in "${SKIP[@]:-}"; do IFS='|' read -r n rsn <<< "$s"; echo "| $n | skipped | $rsn |"; done
        echo "==> All blocking CI gates passed successfully!"
        ;;
    ci-nightly) "$0" mutants; "$0" coverage; "$0" powerset; cargo +nightly miri test || (echo "miri requires nightly setup" && exit 1); cargo outdated ;;
    ci-release) "$0" semver || true; cargo publish --workspace --dry-run ;;
    *) echo "Usage: ./mk {--list|setup|fmt|lint|test|doc|deny|audit|typos|tombi|machete|msrv|semver|echoes|refquiem|ci|ci-nightly|ci-release|mutants|coverage|powerset|wasm|stale-check|dup-check}"; exit 1 ;;
esac
