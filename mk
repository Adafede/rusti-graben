#!/usr/bin/env bash
set -e

cmd="${1:-ci}"
shift || true

case "$cmd" in
    setup)
        echo "==> Installing required cargo tools and components..."
        rustup toolchain install stable
        rustup component add rustfmt clippy miri rust-docs wasm32-unknown-unknown
        cargo install cargo-deny cargo-machete cargo-audit typos-cli cargo-hack cargo-semver-checks cargo-mutants cargo-llvm-cov --locked 2>/dev/null || cargo install cargo-deny cargo-machete cargo-audit typos-cli cargo-hack cargo-semver-checks cargo-mutants cargo-llvm-cov
        ;;
    fmt)
        echo "==> Running formatters..."
        cargo fmt --all -- --check
        typos
        ;;
    lint)
        echo "==> Running clippy and checks..."
        cargo clippy --workspace --all-targets --all-features -- -D warnings
        cargo machete
        ;;
    test)
        echo "==> Running test suite..."
        cargo test --workspace --all-features
        ;;
    doc)
        echo "==> Building documentation..."
        RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps
        ;;
    deny)
        echo "==> Running cargo-deny and cargo-audit..."
        cargo deny check
        cargo audit
        ;;
    mutants)
        echo "==> Running mutation testing (scoped)..."
        # Scoped by default to avoid long runs; see mutants.toml for configuration
        if [ -f mutants.toml ]; then
            cargo mutants --workspace --in-place 2>&1 | tail -40 || cargo mutants
        else
            cargo mutants
        fi
        ;;
    coverage)
        echo "==> Running coverage with llvm-cov..."
        cargo llvm-cov --workspace --all-features --lcov --output-path lcov.info
        echo "==> Coverage report written to lcov.info"
        ;;
    semver)
        echo "==> Running cargo-semver-checks..."
        cargo semver-checks --workspace
        ;;
    msrv)
        echo "==> Checking MSRV..."
        if command -v cargo-msrv >/dev/null 2>&1; then
            cargo msrv verify
        else
            echo "cargo-msrv not installed; verify MSRV from rust-toolchain.toml/clippy.toml (MSRV policy documented)"
        fi
        ;;
    powerset)
        echo "==> Running cargo-hack feature powerset..."
        cargo hack --workspace --feature-powerset --no-dev-deps check
        ;;
    wasm)
        echo "==> Building/checking wasm32 target (opt-in)..."
        rustup target add wasm32-unknown-unknown 2>/dev/null || true
        cargo check --workspace --target wasm32-unknown-unknown --all-features
        ;;
    dejadoc|echoes)
        echo "==> Running dejadoc/echoes (duplication check)..."
        if command -v cargo-dejadoc >/dev/null 2>&1; then
            cargo dejadoc
        elif command -v cargo-echoes >/dev/null 2>&1; then
            cargo echoes
        else
            echo "cargo-dejadoc/cargo-echoes not installed or not published on crates.io; skipping (intent: detect duplicate code/docs)."
        fi
        ;;
    refquiem)
        echo "==> Running refquiem (stale references check)..."
        if command -v cargo-refquiem >/dev/null 2>&1; then
            cargo refquiem
        else
            echo "cargo-refquiem not installed or not published on crates.io; skipping (intent: detect stale references to removed items)."
        fi
        ;;
    ci)
        echo "==> Running full local CI gate..."
        "$0" fmt
        "$0" lint
        "$0" test
        "$0" doc
        "$0" deny
        echo "==> All CI gates passed successfully!"
        ;;
    *)
        echo "Usage: ./mk {setup|fmt|lint|test|doc|deny|ci|mutants|coverage|semver|msrv|powerset|wasm|dejadoc|echoes|refquiem}"
        exit 1
        ;;
esac