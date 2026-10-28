#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

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
        printf "fmt\nlint\ntest\ndoc\ndeny\naudit\ntypos\ntombi\nmachete\nmsrv\nsemver\nechoes\nrefquiem\nci\nci-nightly\nci-release\nmutants\ncoverage\npowerset\nwasm\nsetup\n"
        exit 0
        ;;
    setup)
        rustup toolchain install stable
        rustup toolchain install nightly 2>/dev/null || true
        rustup component add rustfmt clippy rust-docs 2>/dev/null || true
        rustup component add miri --toolchain nightly 2>/dev/null || true
        rustup target add wasm32-unknown-unknown 2>/dev/null || true
        cargo install typos-cli --locked
        cargo install cargo-deny --locked
        cargo install cargo-audit --locked
        cargo install cargo-machete --locked
        cargo install cargo-hack --locked
        cargo install cargo-semver-checks --locked
        cargo install cargo-mutants --locked
        cargo install cargo-llvm-cov --locked
        cargo install tombi --locked 2>/dev/null || true
        cargo install cargo-msrv --locked
        cargo install cargo-outdated --locked
        ;;
    fmt)
        cargo fmt --all -- --check
        typos
        if command -v tombi >/dev/null 2>&1; then
            tombi format --check
        else
            echo "tombi missing"; exit 1
        fi
        ;;
    lint) cargo clippy --workspace --all-targets --all-features -- -D warnings ;;
    test) cargo test --workspace --all-features ;;
    doc) RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps ;;
    deny) cargo deny check ;;
    audit) cargo audit ;;
    typos) typos ;;
    tombi) if command -v tombi >/dev/null 2>&1; then tombi format --check; else echo "tombi missing"; exit 1; fi ;;
    machete) cargo machete ;;
    msrv) if command -v cargo-msrv >/dev/null 2>&1; then cargo msrv verify; else echo "cargo-msrv missing"; exit 1; fi ;;
    semver) if [ $DETECT_LIB -eq 1 ]; then cargo semver-checks --workspace || echo "[warn] semver skipped/failed for unpublished crate"; else echo "[skip] semver: no lib target"; fi ;;
    echoes) if command -v cargo-echoes >/dev/null 2>&1; then cargo echoes; else echo "cargo-echoes missing"; exit 1; fi ;;
    refquiem) if command -v cargo-refquiem >/dev/null 2>&1; then cargo refquiem; else echo "cargo-refquiem missing"; exit 1; fi ;;
    wasm) if [ $DETECT_WASM -eq 1 ]; then rustup target add wasm32-unknown-unknown; cargo check --workspace --target wasm32-unknown-unknown --all-features; else echo "[skip] wasm: no wasm target declared"; fi ;;
    mutants) [ -f mutants.toml ] && [ -f .mutants-baseline ] && cargo mutants --workspace || (echo "ERROR: mutants baseline missing" && exit 1) ;;
    coverage) cargo llvm-cov --workspace --all-features --lcov --output-path lcov.info ;;
    powerset) cargo hack --workspace --feature-powerset --no-dev-deps check ;;
    ci)
        echo "--- fmt ---"; cargo fmt --all -- --check
        echo "--- lint ---"; cargo clippy --workspace --all-targets --all-features -- -D warnings
        echo "--- test ---"; cargo test --workspace --all-features
        echo "--- doc ---"; RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps
        echo "--- deny ---"; cargo deny check
        echo "--- audit ---"; cargo audit
        echo "--- typos ---"; typos
        echo "--- tombi ---"; if command -v tombi >/dev/null 2>&1; then tombi format --check; else echo "tombi missing"; exit 1; fi
        echo "--- machete ---"; cargo machete
        echo "--- msrv ---"; if command -v cargo-msrv >/dev/null 2>&1; then cargo msrv verify; else echo "cargo-msrv missing"; exit 1; fi
        if [ $DETECT_LIB -eq 1 ]; then echo "--- semver ---"; cargo semver-checks --workspace || echo "[warn] semver check failed (unpublished)"; else echo "[skip] semver: no lib target"; fi
        echo "--- echoes ---"; if command -v cargo-echoes >/dev/null 2>&1; then cargo echoes; else echo "cargo-echoes missing"; exit 1; fi
        echo "--- refquiem ---"; if command -v cargo-refquiem >/dev/null 2>&1; then cargo refquiem; else echo "cargo-refquiem missing"; exit 1; fi
        if [ $DETECT_WASM -eq 1 ]; then echo "--- wasm ---"; rustup target add wasm32-unknown-unknown; cargo check --workspace --target wasm32-unknown-unknown --all-features; else echo "[skip] wasm: no wasm target declared"; fi
        echo "==> All blocking CI gates passed successfully!"
        ;;
    ci-nightly) "$0" mutants; "$0" coverage; "$0" powerset; cargo +nightly miri test || (echo "miri requires nightly setup" && exit 1); cargo outdated ;;
    ci-release) "$0" semver || true; cargo publish --workspace --dry-run ;;
    *) echo "Usage: ./mk {--list|setup|fmt|lint|test|doc|deny|audit|typos|tombi|machete|msrv|semver|echoes|refquiem|ci|ci-nightly|ci-release|mutants|coverage|powerset|wasm}"; exit 1 ;;
esac
