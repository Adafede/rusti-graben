#!/usr/bin/env bash
set -e

cmd="${1:-ci}"
shift || true

case "$cmd" in
    setup)
        echo "==> Installing required cargo tools and components..."
        rustup toolchain install stable
        rustup component add rustfmt clippy miri wasm32-unknown-unknown
        cargo install cargo-deny cargo-machete cargo-audit typos-cli cargo-hack cargo-semver-checks cargo-mutants
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
        echo "Usage: ./mk {setup|fmt|lint|test|doc|deny|ci}"
        exit 1
        ;;
esac