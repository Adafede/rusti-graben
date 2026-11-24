# shellcheck shell=bash
# scripts/adopt.sh idempotency, .mk/* sync, and layout fixture tests.

adopt() { DRY_RUN="$1" "$SRC/scripts/adopt.sh" "$2"; }
fingerprint() { (cd "$1" && find . -path ./target -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum | cksum); }

run_adopt_suite() {
    local legacy="$OUTSIDE/legacy-workspace" before f
    mkdir -p "$legacy/crates/core/src"
    printf '[workspace]\nresolver = "3"\nmembers = [\n  "crates/core",\n]\n' >"$legacy/Cargo.toml"
    printf '[package]\nname = "core-x"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$legacy/crates/core/Cargo.toml"
    echo '//! Core.' >"$legacy/crates/core/src/lib.rs"
    printf '# legacy policy\n' >"$legacy/.typos.toml"
    printf '/target' >"$legacy/.gitignore"
    (cd "$legacy" && cargo generate-lockfile --offline --quiet)
    before="$(fingerprint "$legacy")"
    check "adopt: dry run succeeds" adopt 1 "$legacy"
    check "adopt: dry run writes nothing" test "$before" = "$(fingerprint "$legacy")"
    check "adopt: apply succeeds" adopt 0 "$legacy"
    for f in mk mk.versions mk.local .mk/catalog.sh .mk/core.sh .mk/gates.sh .mk/meta.py .mk/mutants.sh .mk/tier.sh .mk/tools.sh \
        deny.toml .echoes.toml .refquiem.toml .config/nextest.toml bacon.toml .editorconfig .vscode/settings.json \
        CLAUDE.md docs/DEBT.md .github/PULL_REQUEST_TEMPLATE.md .github/workflows/ci.yml .github/actions/setup/action.yml .github/dependabot.yml; do
        check "adopt: copies $f" test -f "$legacy/$f"
    done
    check "adopt: mk is executable" test -x "$legacy/mk"
    check "adopt: does not copy the template selftest" test ! -e "$legacy/.github/workflows/selftest.yml"
    check "adopt: keeps an existing config" grep -qx '# legacy policy' "$legacy/.typos.toml"
    check "adopt: adds workspace lints" grep -q '^\[workspace\.lints\.clippy\]' "$legacy/Cargo.toml"
    check "adopt: members inherit them" bash -c 'cd "$1" && git init -q && ./mk lints-inherit' _ "$legacy"
    check "adopt: adopted workspace runs ./mk --list" bash -c 'cd "$1" && ./mk --list | grep -qx "ci"' _ "$legacy"
    check "adopt: adopted workspace runs ./mk mutants-plan --mode full" bash -c 'cd "$1" && ./mk mutants-plan --mode full | grep -q "\"core-x\""' _ "$legacy"
    check "adopt: deny no longer allows the template's AGPL license" bash -c '! grep -q AGPL "$1/deny.toml"' _ "$legacy"
    check "adopt: deny does not duplicate MIT" bash -c '[ "$(grep -c "\"MIT\"" "$1/deny.toml")" -eq 1 ]' _ "$legacy"
    check "adopt: gitignore preserves existing line without trailing newline" grep -qx '/target' "$legacy/.gitignore"
    check "adopt: gitignore appends lcov.info on its own line" grep -qx 'lcov.info' "$legacy/.gitignore"
    check "adopt: seeded docs/DEBT.md strips template specifics" bash -c '! grep -Eq "sample-bin|@Adafede|COVERAGE_FAIL_UNDER_LINES" "$1/docs/DEBT.md"' _ "$legacy"
    check "adopt: seeded AGENTS.md strips template specifics" bash -c '! grep -Eq "sample-lib|sample-bin|gate_selftest\.sh|tests/selftest/|\.agents/PLAYBOOK\.md" "$1/AGENTS.md"' _ "$legacy"
    check "adopt: seeded .cargo/mutants.toml enables gitignore and cap_lints" bash -c 'grep -q "^gitignore = true" "$1/.cargo/mutants.toml" && grep -q "^cap_lints = true" "$1/.cargo/mutants.toml"' _ "$legacy"
    check "adopt: seeded Cargo.toml sets dev/test dependency debug=false" bash -c 'grep -q "^\[profile\.dev\.package\." "$1/Cargo.toml" && grep -q "^\[profile\.test\.package\." "$1/Cargo.toml"' _ "$legacy"
    check "adopt: adopted workspace passes tombi" bash -c 'cd "$1" && ./mk tombi' _ "$legacy"
    before="$(fingerprint "$legacy")"
    check "adopt: second apply succeeds" adopt 0 "$legacy"
    check "adopt: second apply changes nothing" test "$before" = "$(fingerprint "$legacy")"
    check "adopt: mk.local does not inherit the template's coverage floor" bash -c '! grep -q "^COVERAGE_FAIL_UNDER_LINES" "$1/mk.local"' _ "$legacy"
    check "adopt: mk.local does not inherit template local gates" bash -c '! grep -qE "docs_boundary|runner_tests" "$1/mk.local"' _ "$legacy"
    check "adopt: a stale standard file is synced" bash -c 'echo "# stale" >>"$1/mk.versions" && echo "# stale" >>"$1/.mk/core.sh" && DRY_RUN=0 "$2/scripts/adopt.sh" "$1" && ! grep -q "# stale" "$1/mk.versions" && ! grep -q "# stale" "$1/.mk/core.sh"' _ "$legacy" "$SRC"

    local wrapped="$OUTSIDE/cargo-make-repo"
    mkdir -p "$wrapped/src"
    printf '[package]\nname = "wrapped"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$wrapped/Cargo.toml"
    echo '//! Wrapped.' >"$wrapped/src/lib.rs"
    printf '[tasks.hello]\nscript = "echo hello"\n' >"$wrapped/Makefile.toml"
    printf '#!/usr/bin/env bash\nexec cargo make --no-workspace "$@"\n' >"$wrapped/mk"
    chmod +x "$wrapped/mk"
    check "adopt: cargo-make wrapper: apply succeeds" adopt 0 "$wrapped"
    check "adopt: cargo-make wrapper: replaced by the standard mk" grep -q "rusti-graben standard runner" "$wrapped/mk"
    check "adopt: cargo-make wrapper: cargo-make pinned in mk.local" grep -q "^LOCAL_CARGO_TOOLS=(cargo-make@" "$wrapped/mk.local"

    local custom="$OUTSIDE/custom-runner"
    mkdir -p "$custom/src"
    printf '[package]\nname = "custom"\nversion = "0.1.0"\nedition = "2024"\n' >"$custom/Cargo.toml"
    printf '#!/bin/sh\necho mine\n' >"$custom/mk"
    check "adopt: own runner: adopt refuses" bash -c '! DRY_RUN=0 "$2/scripts/adopt.sh" "$1"' _ "$custom" "$SRC"
    check "adopt: own runner: left untouched" grep -qx 'echo mine' "$custom/mk"

    local single="$OUTSIDE/single-crate"
    mkdir -p "$single/src"
    printf '[package]\nname = "single"\nversion = "0.1.0"\nedition = "2024"\nlicense = "LGPL-3.0-only"\n' >"$single/Cargo.toml"
    echo '//! Single.' >"$single/src/lib.rs"
    check "adopt: single crate: apply succeeds" adopt 0 "$single"
    check "adopt: single crate: adds [lints.*] tables" grep -q '^\[lints\.clippy\]' "$single/Cargo.toml"
    check "adopt: single crate: lints gate passes" bash -c 'cd "$1" && git init -q && ./mk lints-inherit' _ "$single"
    check "adopt: single crate: deny allows its own license" grep -q '"LGPL-3.0-only",  # this project' "$single/deny.toml"
    check "adopt: single crate: passes tombi" bash -c 'cd "$1" && ./mk tombi' _ "$single"

    local wasm_repo="$OUTSIDE/wasm-crate"
    mkdir -p "$wasm_repo/src"
    printf '[package]\nname = "wasm-x"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$wasm_repo/Cargo.toml"
    printf '[toolchain]\nchannel = "1.100.0"\ntargets = ["wasm32-unknown-unknown"]\n' >"$wasm_repo/rust-toolchain.toml"
    echo '//! Wasm.' >"$wasm_repo/src/lib.rs"
    check "adopt: wasm crate: apply with ADOPT_MUTANTS=0 succeeds" bash -c 'DRY_RUN=0 ADOPT_MUTANTS=0 "$2/scripts/adopt.sh" "$1"' _ "$wasm_repo" "$SRC"
    check "adopt: wasm crate: respects ADOPT_MUTANTS=0" test ! -e "$wasm_repo/.cargo/mutants.toml"
    check "adopt: wasm crate: keeps existing rust-toolchain.toml with wasm32" grep -q 'wasm32-unknown-unknown' "$wasm_repo/rust-toolchain.toml"

    local bin_repo="$OUTSIDE/bin-only"
    mkdir -p "$bin_repo/src"
    printf '[package]\nname = "bin-only"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$bin_repo/Cargo.toml"
    printf 'fn main() {}\n#[test] fn ok() {}\n' >"$bin_repo/src/main.rs"
    (cd "$bin_repo" && cargo generate-lockfile --offline --quiet)
    check "adopt: binary-only crate: adopt succeeds" adopt 0 "$bin_repo"
    check "adopt: binary-only crate: ./mk test skips doctests cleanly" bash -c 'cd "$1" && ./mk test' _ "$bin_repo"
}
