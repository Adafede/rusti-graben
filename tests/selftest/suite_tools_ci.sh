# shellcheck shell=bash
# Rust and Markdown snippets are single-quoted on purpose: their backticks are literal.
# shellcheck disable=SC2016,SC2154  # fixtures from harness.sh / gate_selftest.sh
# Tool-isolation and blocking CI gate violation-injection tests.

test_tools_isolation() {
    perl -pi -e 's/^TOMBI_VERSION=.*/TOMBI_VERSION="0.0.0"/' mk.versions
    expect_fail tools "0.0.0" "tool version differs from mk.versions"

    mkdir -p "$OUTSIDE/mk-tools/tombi/9.9.1/bin" "$OUTSIDE/mk-tools/tombi/9.9.2/bin" "$OUTSIDE/shadow-bin"
    local v
    for v in 9.9.1 9.9.2; do
        printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "tombi %s"; exit 0; fi\necho "selected-%s" >&2\nexit 1\n' "$v" "$v" >"$OUTSIDE/mk-tools/tombi/$v/bin/tombi"
        chmod +x "$OUTSIDE/mk-tools/tombi/$v/bin/tombi"
    done
    printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "tombi 9.9.9"; exit 0; fi\necho "selected-9.9.9" >&2\nexit 1\n' >"$OUTSIDE/shadow-bin/tombi"
    chmod +x "$OUTSIDE/shadow-bin/tombi"

    perl -pi -e 's/^TOMBI_VERSION=.*/TOMBI_VERSION="9.9.1"/' mk.versions
    expect_fail_cmd "selected-9.9.1" "tombi: MK_TOOLS_DIR 9.9.1 wins over shadow PATH" \
        env -u _MK_BASE_PATH MK_TOOLS_DIR="$OUTSIDE/mk-tools" PATH="$OUTSIDE/shadow-bin:$PATH" ./mk tombi
    perl -pi -e 's/^TOMBI_VERSION=.*/TOMBI_VERSION="9.9.2"/' mk.versions
    expect_fail_cmd "selected-9.9.2" "tombi: MK_TOOLS_DIR 9.9.2 coexists independently" \
        env -u _MK_BASE_PATH MK_TOOLS_DIR="$OUTSIDE/mk-tools" PATH="$OUTSIDE/shadow-bin:$PATH" ./mk tombi
    perl -pi -e 's/^TOMBI_VERSION=.*/TOMBI_VERSION="9.9.3"/' mk.versions
    expect_fail_cmd "tombi 9.9.3 (mk.versions) is required" "tombi: uncached version does not fall back to wrong cached dir" \
        env -u _MK_BASE_PATH MK_TOOLS_DIR="$OUTSIDE/mk-tools" PATH="$OUTSIDE/shadow-bin:$PATH" ./mk tombi

    mkdir -p "$OUTSIDE/mk-tools/cargo-machete/9.9.1/bin"
    printf '#!/bin/sh\ncase "$*" in *--version*) echo "9.9.1"; exit 0 ;; esac\necho "selected-machete-9.9.1" >&2\nexit 1\n' >"$OUTSIDE/mk-tools/cargo-machete/9.9.1/bin/cargo-machete"
    printf '#!/bin/sh\ncase "$*" in *--version*) echo "9.9.9"; exit 0 ;; esac\necho "selected-machete-9.9.9" >&2\nexit 1\n' >"$OUTSIDE/shadow-bin/cargo-machete"
    chmod +x "$OUTSIDE/mk-tools/cargo-machete/9.9.1/bin/cargo-machete" "$OUTSIDE/shadow-bin/cargo-machete"
    perl -pi -e 's/cargo-machete@[^ )]+/cargo-machete\@9.9.1/' mk.versions
    expect_fail_cmd "selected-machete-9.9.1" "machete: MK_TOOLS_DIR cargo subcommand wins over CARGO_HOME/bin and shadow PATH" \
        env -u _MK_BASE_PATH MK_TOOLS_DIR="$OUTSIDE/mk-tools" PATH="$OUTSIDE/shadow-bin:$PATH" ./mk machete
}

test_hygiene_gates() {
    perl -pi -e 's/checkout@[0-9a-f]{40}/checkout\@v7/' .github/workflows/ci.yml
    expect_fail actions "unpinned" "action not pinned to a commit SHA"

    printf '\necho $1\n' >>scripts/adopt.sh
    expect_fail shell "SC2086" "unquoted variable in a shell script"

    echo "// change" >>"$LIB"
    git commit -qam "Update the library"
    expect_fail commits "not a conventional commit" "commit message outside Conventional Commits"

    printf '# comment only\n' >"$OUTSIDE/empty_msg"
    expect_fail_cmd "not a conventional commit" "commits: comment-only commit-msg file" ./mk commits "$OUTSIDE/empty_msg"

    append_lib 'fn bad( ){}'
    expect_fail fmt "Diff in" "unformatted code"

    printf '\n[workspace.metadata.x]\nkey=1\n' >>Cargo.toml
    expect_fail tombi "not formatted" "unformatted TOML"

    append_lib "// $typo"
    expect_fail typos "$typo" "misspelling"
}

test_rust_lint_gates() {
    append_lib '/// First byte.
#[must_use]
pub fn first(v: &[u8]) -> u8 {
    *v.first().unwrap()
}'
    expect_fail lint "unwrap_used" "unwrap()"

    append_lib '/// Nothing.
pub fn nothing() {
    unsafe {}
}'
    expect_fail lint 'usage of an `unsafe` block' "unsafe block"

    append_lib '#[allow(dead_code)]
fn unused() {}'
    expect_fail lint "allow_attributes" "#[allow] instead of #[expect(.., reason)]"

    append_lib '/// Prints a greeting.
pub fn greet() {
    println!("hi");
}'
    expect_fail lint "print_stdout" "println! in a library"

    perl -0pi -e 's/\[lints\]\nworkspace = true\n//' "$BIN_TOML"
    expect_fail lints-inherit "missing" "crate not inheriting workspace lints"

    perl -pi -e 's/assert_eq!\(add\(2, 2\), 4,/assert_eq!(add(2, 2), 5,/' "$LIB"
    expect_fail test "FAILED" "failing unit test"
}

test_doc_and_supply_gates() {
    perl -pi -e 's|^/// Adds two|/// See [`nope`]. Adds two|' "$LIB"
    expect_fail doc "unresolved link" "broken intra-doc link"

    perl -pi -e 's|^/// Adds two|/// Adds `two|' "$LIB"
    expect_fail doc "unescaped backtick" "unbalanced backtick in docs"

    perl -pi -e 's/assert_eq!\(total, 6,/assert_eq!(total, 7,/' crates/sample-lib/README.md
    expect_fail test "README.md" "failing README example"

    perl -pi -e 's/^license\.workspace = true/license = "GPL-3.0-only"/' "$LIB_TOML"
    expect_fail deny "GPL-3.0-only" "license outside the allow-list"

    cat >>Cargo.lock <<'EOF'

[[package]]
name = "smallvec"
version = "1.6.0"
source = "registry+https://github.com/rust-lang/crates.io-index"
EOF
    expect_fail audit "RUSTSEC-2021-0003" "dependency with a known advisory"

    printf '\n[dependencies]\nitoa = "1"\n' >>"$LIB_TOML"
    expect_fail machete "itoa" "unused dependency"
}

test_msrv_and_echoes() {
    rustup run 1.85 true 2>/dev/null || rustup toolchain install 1.85 --profile minimal --no-self-update >&2
    local even_fn=$'/// Whether `n` is even.\n#[must_use]\npub const fn even(n: u32) -> bool {\n    n.is_multiple_of(2)\n}'
    perl -pi -e 's/^rust-version = .*/rust-version = "1.85"/' Cargo.toml
    append_lib "$even_fn"
    expect_fail msrv "is_multiple_of" "API newer than rust-version"

    perl -pi -e 's/^rust-version = .*/rust-version = "1.85"/' Cargo.toml
    append_lib "$even_fn"
    expect_fail_cmd "is_multiple_of" "msrv: still fails inside tier when rust-version differs from active rustc" \
        env MK_NESTED=1 MK_LINT_PASSED=1 ./mk msrv

    expect_rc_and_output 78 "already verified by lint on rustc" \
        "msrv: skips inside tier when lint already passed on matching rustc" \
        env MK_NESTED=1 MK_LINT_PASSED=1 ./mk msrv

    append_lib "${checksum_fn/fn checksum/fn checksum_a}"
    append_lib "${checksum_fn/fn checksum/fn checksum_b}"
    expect_fail echoes "checksum_b" "duplicated function"

    mkdir -p "$OUTSIDE/helper/src"
    printf '[package]\nname = "helper"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$OUTSIDE/helper/Cargo.toml"
    printf '//! Helper.\n\n%s\n' "$checksum_fn" >"$OUTSIDE/helper/src/lib.rs"
    printf '\n[dependencies]\nhelper = { path = "%s" }\n' "$OUTSIDE/helper" >>"$LIB_TOML"
    append_lib "${checksum_fn/fn checksum/fn local_checksum}"
    expect_fail echoes "helper::checksum" "re-implementing a dependency's API"

    perl -pi -e 's/^fail-on-findings = true/fail-on-findings = false/' .echoes.toml
    expect_fail echoes "fail-on-findings" "weakened .echoes.toml"
}

test_refquiem() {
    append_lib $'/// Removes `right` from `left`, saturating at zero.\n#[must_use]\npub const fn subtract(left: usize, right: usize) -> usize {\n    left.saturating_sub(right)\n}'
    git commit -qam "add subtract" && git checkout -q base -- "$LIB" && git commit -qam "drop subtract"
    echo 'Call `subtract` to take away.' >>README.md
    expect_fail refquiem "sample_lib::subtract" "mention of a deleted item"

    echo 'Call `sample_lib::add` to sum.' >>README.md && git add README.md && git commit -qm "docs: mention sample_lib::add"
    perl -pi -e 's/pub const fn add\(left: usize, right: usize\) -> usize/pub const fn add(left: usize, right: usize, extra: usize) -> usize/' "$LIB"
    MK_BASE=HEAD expect_fail refquiem "signature changed" "untouched mention of an item whose signature changed"

    perl -pi -e 's/^level = "deny"/level = "warn"/' .refquiem.toml
    expect_fail refquiem 'level = "deny"' "weakened .refquiem.toml"
}

test_semver_wasm_ratchet() {
    perl -pi -e 's/version = "0\.1\.0"/version = "1.0.0"/g' Cargo.toml
    cargo update --workspace --offline --quiet
    append_lib "$untested_fn"
    git commit -qam "add double" && git tag v1.0.0 && git checkout -q base -- "$LIB" && git commit -qam "drop double"
    expect_fail semver "function_missing" "public fn removed without a major bump"

    printf 'targets = ["wasm32-unknown-unknown"]\n' >>rust-toolchain.toml
    append_lib 'pub use std::os::unix::ffi::OsStrExt;'
    expect_fail wasm "unix" "code that does not build for wasm32"

    perl -pi -e 's/^COVERAGE_FAIL_UNDER_LINES=.*/COVERAGE_FAIL_UNDER_LINES="1"/' mk.local
    expect_fail ratchet "went down" "coverage floor lowered"
    perl -pi -e 's/^redundant_pub_crate = "allow"/redundant_pub_crate = "allow"\nmissing_docs = "allow"/' Cargo.toml
    expect_fail ratchet "lint allow count went up" "new lint allow added to Cargo.toml"
    perl -pi -e 's/^COVERAGE_FAIL_UNDER_LINES=.*/COVERAGE_FAIL_UNDER_LINES="100"\nECHOES_MAX_APPROXIMATE=0/' mk.local
    git commit -qam "baseline echoes ratchet"
    perl -pi -e 's/^ECHOES_MAX_APPROXIMATE=.*/ECHOES_MAX_APPROXIMATE=5/' mk.local
    MK_BASE=HEAD expect_fail ratchet "went up" "echoes ratchet raised"
    printf 'ECHOES_MAX_APPROXIMATE=5\n' >>mk.local
    expect_fail ratchet "went up" "echoes ratchet raised above implicit 0 baseline"
    perl -pi -e 's/^redundant_pub_crate = "allow"/# placeholder = "allow"\nredundant_pub_crate = "allow"/' Cargo.toml
    git commit -qam "chore: add commented allow"
    perl -pi -e 's/^# placeholder = "allow"/missing_docs = "allow"/' Cargo.toml
    MK_BASE=HEAD expect_fail ratchet "lint allow count went up" "commented allow replaced by active lint allow"
}

test_tiers_and_boundaries() {
    append_lib "// $typo"
    expect_fail ci "FAIL  typos" "ci tier propagates a failing gate"

    printf '\n%s\n' "$typo" >>docs/GATES.md
    expect_fail ci-fast "docs/config-only diff against base" "ci-fast skips Rust compilation gates on docs-only diff and catches docs typo"

    local single_doc="$OUTSIDE/single-doc"
    mkdir -p "$single_doc/src"
    cat >"$single_doc/Cargo.toml" <<'EOF'
[package]
name = "single-doc"
version = "0.1.0"
edition = "2024"
rust-version = "1.100.0"
license = "AGPL-3.0-or-later"

[lints.clippy]
[lints.rust]
[lints.rustdoc]
broken_intra_doc_links = "deny"
EOF
    printf '#![doc = include_str!("../README.md")]\n' >"$single_doc/src/lib.rs"
    printf '# single-doc\n' >"$single_doc/README.md"
    cp mk mk.versions rust-toolchain.toml .tombi.toml .typos.toml .echoes.toml .refquiem.toml deny.toml "$single_doc/"
    cp -R .mk "$single_doc/.mk"
    (cd "$single_doc" || return 1; cargo generate-lockfile --offline --quiet; git init -q; git add -A; git commit -qm "chore: init"; git tag base; printf '\nSee [`nope`].\n' >>README.md)
    expect_fail_cmd "unresolved link" "ci-fast: root README.md broken link not skipped in single-crate repo" \
        bash -c 'cd "$1" && ./mk ci-fast' _ "$single_doc"

    printf '\n[workspace.metadata.x]\nkey=1\n' >>Cargo.toml
    expect_fail toml "not formatted" "toml alias invokes tombi"
    printf '\nSee `AGENTS.md`.\n' >>README.md
    expect_fail local:docs_boundary "must not reference agent files" "human doc referencing AGENTS.md"
}

run_tools_and_ci_suite() {
    test_tools_isolation
    test_hygiene_gates
    test_rust_lint_gates
    test_doc_and_supply_gates
    test_msrv_and_echoes
    test_refquiem
    test_semver_wasm_ratchet
    test_tiers_and_boundaries
}
