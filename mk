#!/usr/bin/env bash
# Single entrypoint for every gate. CI calls exactly these tasks.
# A gate either runs and can fail, or is skipped because it cannot apply
# (printed with a reason). A missing tool, or one at the wrong version, is a failure.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"
# shellcheck source=mk.versions
. ./mk.versions

SKIP_RC=78
CI_GATES="tools actions fmt tombi typos lint lints-inherit test doc deny audit machete msrv echoes refquiem semver wasm"
NIGHTLY_GATES="mutants coverage powerset miri outdated"

cmd="${1:-ci}"
shift || true

die() { echo "ERROR: $*" >&2; exit 1; }

# Not applicable here: exit 0 when run directly, SKIP_RC when run by a tier.
skip() {
    echo "[skip] $cmd: $*"
    if [ "${MK_NESTED:-0}" = 1 ]; then exit "$SKIP_RC"; fi
    exit 0
}

has_lib() { cargo metadata --no-deps --format-version 1 --locked | grep -q '"kind":\["lib"\]'; }
has_wasm() { grep -q 'wasm32' rust-toolchain.toml Cargo.toml 2>/dev/null; }
msrv() { sed -n 's/^rust-version *= *"\([^"]*\)".*/\1/p' Cargo.toml | head -1; }

# --- pinned tools -----------------------------------------------------------

tool_version() {
    case "$1" in
        typos-cli) typos --version ;;
        zizmor) zizmor --version ;;
        echoes | refquiem) cargo "$1" --version ;;
        cargo-*) cargo "${1#cargo-}" --version ;;
        tombi) tombi --version ;;
        *) echo "unknown tool $1" >&2; return 1 ;;
    esac
}

# Exact pinned version installed? (probe only, never exits)
has_version() {
    local out
    out="$(tool_version "$1" 2>/dev/null)" || return 1
    printf '%s\n' "$out" | grep -Eq "(^|[^0-9.])${2//./\\.}([^0-9.]|$)"
}

require() {
    has_version "$1" "$2" ||
        die "$1 $2 (mk.versions) is required, found '$(tool_version "$1" 2>&1 | head -1)'; run ./mk setup"
}

require_spec() { require "${1%@*}" "${1#*@}"; }

require_tools() {
    local spec
    for spec in "$@"; do require_spec "$spec"; done
}

spec_of() {
    local spec
    for spec in $CARGO_TOOLS_CI $CARGO_TOOLS_NIGHTLY; do
        if [ "${spec%@*}" = "$1" ]; then echo "$spec"; return; fi
    done
    die "$1 is not pinned in mk.versions"
}

need() { require_spec "$(spec_of "$1")"; }

install_tombi() {
    if has_version tombi "$TOMBI_VERSION"; then return; fi
    local host target tmp bin_dir
    host="$(rustc -vV | sed -n 's/^host: //p')"
    target="${host/-linux-gnu/-linux-musl}"
    tmp="$(mktemp -d)"
    bin_dir="${CARGO_HOME:-$HOME/.cargo}/bin"
    curl -fsSL "https://github.com/tombi-toml/tombi/releases/download/v${TOMBI_VERSION}/tombi-cli-${TOMBI_VERSION}-${target}.tar.gz" |
        tar xz -C "$tmp"
    mkdir -p "$bin_dir"
    install -m 0755 "$tmp/tombi-cli-${TOMBI_VERSION}-${target}/tombi" "$bin_dir/tombi"
    rm -rf "$tmp"
}

install_cargo_tools() {
    command -v cargo-binstall >/dev/null || die "cargo-binstall is required: https://github.com/cargo-bins/cargo-binstall"
    local spec
    for spec in "$@"; do
        has_version "${spec%@*}" "${spec#*@}" || cargo binstall --no-confirm --locked --force "$spec"
        require_spec "$spec"
    done
}

# --- tiers ------------------------------------------------------------------

# Runs every gate as its own process (so `set -e` holds inside each), keeps
# going after a failure, then prints a ran/skipped/failed table.
run_tier() {
    local tier="$1" gate rc start
    shift
    local -a report=()
    local failed=0
    for gate in "$@"; do
        echo "--- $gate ---"
        start=$SECONDS
        rc=0
        MK_NESTED=1 "$0" "$gate" || rc=$?
        case "$rc" in
            0) report+=("PASS  $gate ($((SECONDS - start))s)") ;;
            "$SKIP_RC") report+=("SKIP  $gate") ;;
            *) report+=("FAIL  $gate (exit $rc)"); failed=1 ;;
        esac
    done
    echo "=== $tier summary ==="
    printf '%s\n' "${report[@]}"
    [ "$failed" = 0 ] || die "$tier failed"
    echo "==> $tier passed"
}

case "$cmd" in
    --list | --list-all-steps)
        printf '%s\n' setup tools $CI_GATES $NIGHTLY_GATES ci ci-nightly ci-release selftest | sort -u
        ;;
    setup)
        tier="${1:-all}"
        rustup toolchain install # from rust-toolchain.toml
        rustup toolchain install "$(msrv)" --profile minimal
        install_tombi
        install_cargo_tools $CARGO_TOOLS_CI
        if [ "$tier" = all ] || [ "$tier" = nightly ]; then
            rustup toolchain install "$RUST_NIGHTLY" --profile minimal --component miri,rust-src
            rustup component add llvm-tools
            install_cargo_tools $CARGO_TOOLS_NIGHTLY
        fi
        ;;
    tools)
        require tombi "$TOMBI_VERSION"
        require_tools $CARGO_TOOLS_CI
        ;;
    actions) need zizmor; zizmor --offline .github/workflows ;;
    fmt) cargo fmt --all -- --check ;;
    tombi)
        require tombi "$TOMBI_VERSION"
        tombi format --check
        # Also fails on a config tombi cannot parse (format only warns and uses defaults).
        tombi lint --error-on-warnings
        ;;
    typos) need typos-cli; typos ;;
    lint) cargo clippy --workspace --all-targets --all-features --locked -- -D warnings ;;
    lints-inherit)
        # Workspace lints only apply to crates that opt in.
        missing=0
        for manifest in $(cargo metadata --no-deps --format-version 1 --locked | grep -o '"manifest_path":"[^"]*"' | cut -d'"' -f4); do
            awk '/^\[lints\]/{s=1;next} /^\[/{s=0} s && /^workspace *= *true/{f=1} END{exit !f}' "$manifest" ||
                { echo "missing '[lints] workspace = true' in $manifest"; missing=1; }
        done
        [ "$missing" = 0 ]
        ;;
    test) cargo test --workspace --all-features --locked ;;
    doc) RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps --locked ;;
    deny) need cargo-deny; cargo deny --all-features --locked check ;;
    audit) need cargo-audit; cargo audit --deny warnings ;;
    machete) need cargo-machete; cargo machete ;;
    msrv)
        v="$(msrv)"
        [ -n "$v" ] || die "set rust-version in Cargo.toml"
        rustup run "$v" true 2>/dev/null || die "MSRV toolchain $v is not installed; run ./mk setup"
        cargo "+$v" check --workspace --all-targets --all-features --locked
        ;;
    echoes)
        need echoes
        # echoes silently falls back to a shallow scan without its config, so insist on the deep one.
        for key in 'functions = true' 'context-blocks = true' 'fail-on-findings = true'; do
            grep -q "^$key" .echoes.toml 2>/dev/null || die ".echoes.toml must set '$key'"
        done
        grep -Eq '^depth = [1-9]' .echoes.toml || die ".echoes.toml must set [context-dependencies] depth > 0"
        if [ "${GITHUB_ACTIONS:-}" = true ]; then set -- --github; fi
        cargo echoes --all-targets --config .echoes.toml "$@"
        ;;
    refquiem)
        need refquiem
        [ "$(git rev-parse --is-shallow-repository)" = false ] || die "refquiem needs full git history (fetch-depth: 0)"
        if [ "${GITHUB_ACTIONS:-}" = true ]; then cargo refquiem --github; else cargo refquiem; fi
        ;;
    semver)
        need cargo-semver-checks
        has_lib || skip "no library target"
        base="$(git tag --merged HEAD --no-contains HEAD --list 'v*' --sort=-v:refname | head -1)"
        [ -n "$base" ] || skip "no earlier v* release tag to compare against"
        cargo semver-checks --workspace --all-features --baseline-rev "$base"
        ;;
    wasm)
        has_wasm || skip "no wasm32 target declared"
        cargo check --workspace --target wasm32-unknown-unknown --all-features --locked
        ;;
    mutants)
        need cargo-mutants
        # Exit 2 = missed mutants, 3 = timeouts: both fail. Exclusions live in mutants.toml.
        cargo mutants --workspace --all-features --config mutants.toml
        ;;
    coverage)
        need cargo-llvm-cov
        cargo llvm-cov --workspace --all-features --locked --lcov --output-path lcov.info \
            --fail-under-lines "$COVERAGE_FAIL_UNDER_LINES"
        ;;
    powerset) need cargo-hack; cargo hack --workspace --feature-powerset --no-dev-deps check ;;
    miri) cargo "+$RUST_NIGHTLY" miri test --workspace --all-features --locked ;;
    outdated) need cargo-outdated; cargo outdated --workspace --root-deps-only --exit-code 1 ;;
    ci) run_tier ci $CI_GATES ;;
    ci-nightly) run_tier ci-nightly $NIGHTLY_GATES ;;
    ci-release)
        "$0" ci
        cargo publish --workspace --dry-run --locked
        ;;
    selftest) tests/gate_selftest.sh ;;
    *) echo "Usage: ./mk {$(./mk --list | paste -sd'|' -)}"; exit 1 ;;
esac
