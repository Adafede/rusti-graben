#!/usr/bin/env bash
# rusti-graben standard runner. Identical in every repository: scripts/adopt.sh
# keeps it in sync, so edit it in the template, never here. Repository-specific
# gates, overrides and tools go in mk.local.
#
# Single entrypoint for every gate. CI calls exactly these tasks.
# A gate either runs and can fail, or is skipped because it cannot apply
# (printed with a reason). A missing tool, or one at the wrong version, is a failure.
set -euo pipefail

if [ -n "${NO_COLOR:-}" ] || [ "${CI:-}" = 1 ]; then
    export CARGO_TERM_COLOR=never
    export NO_COLOR=1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"
export _MK_BASE_PATH="${_MK_BASE_PATH:-$PATH}"
# shellcheck source=mk.versions
. ./mk.versions

# Repository-specific settings (see the template's mk.local for every key).
LOCAL_CI_GATES=()       # cargo-make tasks added to ./mk ci
LOCAL_NIGHTLY_GATES=()  # cargo-make tasks added to ./mk ci-nightly
LOCAL_OVERRIDES=()      # standard gates this repository runs as its own cargo-make task
LOCAL_SETUP=()          # cargo-make tasks ./mk setup runs in every tier (installs mk cannot pin)
LOCAL_CARGO_TOOLS=()    # extra crate@version tools, pinned like mk.versions
LOCAL_SYSTEM_PACKAGES=() # apt packages ./mk setup installs on CI (Linux runners)
MIRI_PACKAGES=()        # crates miri tests (default: the whole workspace)
MUTANTS_PACKAGES=()     # crates cargo-mutants mutates (default: the whole workspace)
COVERAGE_FAIL_UNDER_LINES=100
ECHOES_MAX_APPROXIMATE=0 # legacy approximate duplicate blocks (ratchet: only down)
ECHOES_MAX_REUSE=0       # legacy dependency-reuse opportunities (ratchet: only down)
MK_TOOLS_DIR="${MK_TOOLS_DIR:-${CARGO_HOME:-$HOME/.cargo}/mk-tools}"
# shellcheck source=mk.local
if [ -f mk.local ]; then . ./mk.local; fi
# shellcheck source=.mk/catalog.sh
. "$ROOT_DIR/.mk/catalog.sh"
# shellcheck source=.mk/core.sh
. "$ROOT_DIR/.mk/core.sh"
# shellcheck source=.mk/tools.sh
. "$ROOT_DIR/.mk/tools.sh"
# shellcheck source=.mk/mutants.sh
. "$ROOT_DIR/.mk/mutants.sh"

refresh_tool_path

cmd="$(normalize_cmd_alias "${1:-ci}")"
shift || true

cargo_make() {
    if declare -F "task_$1" >/dev/null; then
        local task="task_$1"
        shift
        "$task" "$@"
        return
    fi
    [ -f Makefile.toml ] || die "no Makefile.toml or task_$1 function for local task '$1'"
    need cargo-make
    cargo make --no-workspace "$@"
}

# --- tiers ------------------------------------------------------------------

# Runs every gate as its own process (so `set -e` holds inside each), keeps
# going after a failure, then prints a ran/skipped/failed table.
run_tier() {
    local tier="$1" gate rc start desc hint skip_rust=0 lint_passed=0
    shift
    if [ "$tier" = ci ] || [ "$tier" = ci-fast ] || [ "$tier" = ci-core ]; then
        if docs_or_meta_only_diff; then skip_rust=1; fi
    fi
    local -a report=()
    local failed=0
    for gate in "$@"; do
        desc="$(gate_desc "$gate")"
        if [ -n "$desc" ]; then
            echo "--- $gate ($desc) ---"
        else
            echo "--- $gate ---"
        fi
        if [ "$skip_rust" = 1 ] && is_rust_compile_gate "$gate"; then
            echo "[skip] $gate: docs/config-only diff against $(base_ref)"
            report+=("SKIP  $gate")
            continue
        fi
        start=$SECONDS
        rc=0
        MK_NESTED=1 MK_LINT_PASSED="$lint_passed" "$0" "$gate" || rc=$?
        case "$rc" in
            0)
                if [ "$gate" = lint ]; then lint_passed=1; fi
                report+=("PASS  $gate ($((SECONDS - start))s)")
                ;;
            "$(skip_rc)") report+=("SKIP  $gate") ;;
            *)
                hint="$(gate_hint "$gate")"
                if [ -n "$hint" ]; then echo "hint ($gate): $hint" >&2; fi
                report+=("FAIL  $gate (exit $rc)")
                failed=1
                ;;
        esac
    done
    echo "=== $tier summary ==="
    printf '%s\n' "${report[@]}"
    [ "$failed" = 0 ] || die "$tier failed"
    echo "==> $tier passed"
}

# A standard gate this repository implements itself: `gate` or `gate=task`.
for override in "${LOCAL_OVERRIDES[@]}"; do
    case "${override%%=*}" in
        # Overriding them would bypass run_mutants' limits and watchdog.
        mutants | mutants-diff | mutants-affected)
            die "LOCAL_OVERRIDES cannot replace ${override%%=*}: scope it with MUTANTS_PACKAGES, configure it in .cargo/mutants.toml" ;;
    esac
    if [ "${override%%=*}" = "$cmd" ]; then
        echo "($cmd: this repository's own task '${override#*=}', see LOCAL_OVERRIDES in mk.local)"
        cargo_make "${override#*=}" "$@"
        exit 0
    fi
done

case "$cmd" in
    -h | --help | help) print_help ;;
    --list | --list-all-steps) print_task_list ${LOCAL_CI_GATES[@]+"${LOCAL_CI_GATES[@]}"} ${LOCAL_NIGHTLY_GATES[@]+"${LOCAL_NIGHTLY_GATES[@]}"} ;;
    check)
        "$0" fmt
        "$0" tombi
        "$0" typos
        "$0" lint "$@"
        ;;
    check-changed)
        "$0" fmt
        "$0" tombi
        "$0" typos
        if base="$(base_ref)"; then
            pkgs=()
            while IFS= read -r p; do [ -n "$p" ] && pkgs+=("$p"); done < <(affected_packages "$base")
            if [ "${#pkgs[@]}" -eq 0 ]; then
                echo "[skip] lint: no affected Rust packages against $base"
            else
                "$0" lint "${pkgs[@]/#/--package=}" "$@"
            fi
        else
            "$0" lint "$@"
        fi
        ;;
    fix)
        cargo fmt
        require tombi "$TOMBI_VERSION"
        tombi format
        need typos-cli
        typos --write-changes || true
        cargo clippy --workspace --all-targets --all-features --locked --fix --allow-dirty --allow-staged -- -D warnings
        ;;
    test-fast)
        scope=(--workspace)
        if has_pkg_flag "$@"; then scope=(); fi
        if command -v cargo-nextest >/dev/null 2>&1; then
            cargo nextest run ${scope[@]+"${scope[@]}"} --all-features --locked --no-tests=pass "$@"
        else
            cargo test ${scope[@]+"${scope[@]}"} --lib --bins --tests --all-features --locked "$@"
        fi
        ;;
    test-changed)
        if base="$(base_ref)"; then
            pkgs=()
            while IFS= read -r p; do [ -n "$p" ] && pkgs+=("$p"); done < <(affected_packages "$base")
            if [ "${#pkgs[@]}" -eq 0 ]; then
                skip "no affected Rust packages against $base"
            fi
            "$0" test-fast "${pkgs[@]/#/--package=}" "$@"
        else
            "$0" test-fast "$@"
        fi
        ;;
    watch)
        if command -v bacon >/dev/null 2>&1; then
            bacon "${1:-check}"
        elif command -v cargo-watch >/dev/null 2>&1; then
            cargo watch -s "./mk ${1:-check}"
        else
            die "install bacon (cargo binstall bacon) or cargo-watch to use ./mk watch"
        fi
        ;;
    bench)
        cargo bench --workspace --all-features --locked --no-run "$@"
        ;;
    udeps)
        command -v cargo-udeps >/dev/null 2>&1 || skip "cargo-udeps not installed (./mk machete covers unused deps in ci)"
        cargo "+$RUST_NIGHTLY" udeps --workspace --all-targets --all-features --locked
        ;;
    setup) cmd_setup "$@" ;;
    tools) cmd_tools ;;
    actions)
        [ -d .github ] || skip "no .github directory"
        need zizmor
        zizmor --offline .github
        ;;
    shell)
        require shellcheck "$SHELLCHECK_VERSION"
        # Every tracked shell script, found by extension or shebang.
        scripts=()
        while IFS= read -r f; do
            case "$f" in
                *.sh) scripts+=("$f") ;;
                *) if head -n1 "$f" 2>/dev/null | grep -Eq '^#!.*[/ ](bash|sh)\b'; then scripts+=("$f"); fi ;;
            esac
        done < <(git ls-files)
        [ "${#scripts[@]}" -gt 0 ] || skip "no shell scripts"
        shellcheck --external-sources --severity=style "${scripts[@]}"
        ;;
    ratchet)
        # The ratchets in mk.local and Cargo.toml may only tighten relative to the base branch:
        # the coverage floor goes up, the echoes legacy counts and Cargo.toml allow lines go down.
        [[ "$COVERAGE_FAIL_UNDER_LINES" =~ ^[0-9]+$ ]] && [ "$COVERAGE_FAIL_UNDER_LINES" -le 100 ] ||
            die "COVERAGE_FAIL_UNDER_LINES must be an integer 0..=100, got '$COVERAGE_FAIL_UNDER_LINES'"
        for key in ECHOES_MAX_APPROXIMATE ECHOES_MAX_REUSE; do
            [[ "${!key}" =~ ^[0-9]+$ ]] || die "$key must be a non-negative integer, got '${!key}'"
        done
        base="$(base_ref)" || skip "no base branch to compare with (set MK_BASE)"
        mb="$(git merge-base "$base" HEAD)"
        count_allows() {
            awk '/^\[(workspace\.)?lints\./{s=1;next} /^\[/{s=0} s && $0 !~ /^[[:space:]]*#/ && /= *"allow"/{c++} END{print c+0}'
        }
        base_cargo="$(git show "$mb:Cargo.toml" 2>/dev/null || true)"
        if grep -Eq '^\[(workspace\.)?lints\.' <<<"$base_cargo"; then
            old_allows="$(count_allows <<<"$base_cargo")"
            new_allows="$(count_allows <Cargo.toml)"
            if [ "$new_allows" -gt "$old_allows" ]; then
                die "Cargo.toml lint allow count went up from $old_allows to $new_allows (use #[expect(.., reason)] at the site)"
            fi
        fi
        base_local="$(git show "$mb:mk.local" 2>/dev/null || true)"
        old_value() { sed -n "s/^$1=\"*\([0-9][0-9]*\)\"*.*/\1/p" <<<"$base_local" | head -1; }
        old="$(old_value COVERAGE_FAIL_UNDER_LINES)"
        if [ -z "$old" ] && git cat-file -e "$mb:mk" 2>/dev/null; then
            old=100
        fi
        if [ -n "$old" ] && [ "$COVERAGE_FAIL_UNDER_LINES" -lt "$old" ]; then
            die "COVERAGE_FAIL_UNDER_LINES went down from $old to $COVERAGE_FAIL_UNDER_LINES"
        fi
        for key in ECHOES_MAX_APPROXIMATE ECHOES_MAX_REUSE; do
            old="$(old_value "$key")"
            if [ -z "$old" ] && git cat-file -e "$mb:.echoes.toml" 2>/dev/null; then
                old=0
            fi
            if [ -n "$old" ] && [ "${!key}" -gt "$old" ]; then
                die "$key went up from $old to ${!key}"
            fi
        done
        ;;
    commits)
        conv_re="$(conventional_regex)"
        if [ $# -gt 0 ] && [ -f "$1" ]; then
            subject="$(grep -v '^#' "$1" | head -1 || true)"
            grep -Eq "$conv_re" <<<"$subject" || die "not a conventional commit: $subject"
            exit 0
        fi
        base="$(base_ref)" || skip "no base branch to compare with (set MK_BASE)"
        bad=0
        while IFS= read -r subject; do
            if ! grep -Eq "$conv_re" <<<"$subject"; then
                echo "not a conventional commit: $subject"
                bad=1
            fi
        done < <(git log --no-merges --format=%s "$(git merge-base "$base" HEAD)..HEAD")
        [ "$bad" = 0 ]
        ;;
    # Workspace members only: --all would also check (and `cargo fmt --all` rewrite)
    # path dependencies that live in other repositories.
    fmt) cargo fmt -- --check ;;
    tombi)
        require tombi "$TOMBI_VERSION"
        tombi format --check
        # Also fails on a config tombi cannot parse (format only warns and uses defaults).
        tombi lint --error-on-warnings
        ;;
    typos) need typos-cli; typos ;;
    lint)
        scope=(--workspace)
        if has_pkg_flag "$@"; then scope=(); fi
        cargo clippy ${scope[@]+"${scope[@]}"} --all-targets --all-features --locked "$@" -- -D warnings
        ;;
    lints-inherit)
        if ! grep -q '^\[workspace\.lints' Cargo.toml; then
            # Single crate: the lints live in its own manifest.
            for sec in clippy rust rustdoc; do
                grep -q "^\[lints\.$sec\]" Cargo.toml || die "Cargo.toml is missing [lints.$sec]"
            done
            exit 0
        fi
        for sec in clippy rust rustdoc; do
            grep -q "^\[workspace\.lints\.$sec\]" Cargo.toml || die "Cargo.toml is missing [workspace.lints.$sec]"
        done
        # Workspace lints only apply to crates that opt in.
        missing=0
        while IFS= read -r manifest; do
            awk '/^\[lints\]/{s=1;next} /^\[/{s=0} s && /^workspace *= *true/{f=1} END{exit !f}' "$manifest" ||
                { echo "missing '[lints] workspace = true' in $manifest"; missing=1; }
        done < <(workspace_manifests)
        [ "$missing" = 0 ]
        ;;
    test)
        need cargo-nextest
        nextest_args=(--workspace --all-features --locked --no-tests=pass)
        if [ -n "${CI:-}" ] && [ -f .config/nextest.toml ] && grep -Eq '^\[profile\.ci\]' .config/nextest.toml; then
            nextest_args+=(--profile ci)
        fi
        cargo nextest run "${nextest_args[@]}" "$@"
        if has_lib; then
            cargo test --workspace --doc --all-features --locked
        fi
        ;;
    doc) RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps --document-private-items --locked ;;
    deny) need cargo-deny; cargo deny --all-features --locked check ;;
    audit) need cargo-audit; cargo audit --deny warnings ;;
    machete) need cargo-machete; cargo machete ;;
    msrv)
        v="$(msrv)"
        [ -n "$v" ] || die "set rust-version in Cargo.toml"
        if [ "${MK_NESTED:-0}" = 1 ] && [ "${MK_LINT_PASSED:-0}" = 1 ]; then
            active_rustc="$(rustc --version 2>/dev/null | awk '{print $2}')"
            [ "$v" != "$active_rustc" ] || skip "already verified by lint on rustc $v"
        fi
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
        # --no-fail: the counts are judged here, against the ratchet in mk.local.
        # An incomplete analysis still exits non-zero and fails the gate.
        rc=0
        out="$(cargo echoes --all-targets --config .echoes.toml --no-fail "$@" 2>&1)" || rc=$?
        printf '%s\n' "$out"
        [ "$rc" = 0 ] || die "echoes could not complete its analysis (exit $rc)"
        count() { grep -oE "[0-9]+ $1" <<<"$out" | head -1 | cut -d' ' -f1; }
        exact="$(count 'duplicated groups')"
        approximate="$(count 'approximate groups')"
        reuse="$(count 'dependency reuse')"
        [ -n "$exact" ] && [ -n "$approximate" ] && [ -n "$reuse" ] || die "could not read the echoes summary"
        [ "$exact" = 0 ] || die "$exact exact duplicate group(s): delete all but one copy"
        [ "$approximate" -le "$ECHOES_MAX_APPROXIMATE" ] ||
            die "$approximate approximate duplicate groups, more than ECHOES_MAX_APPROXIMATE=$ECHOES_MAX_APPROXIMATE in mk.local"
        [ "$reuse" -le "$ECHOES_MAX_REUSE" ] ||
            die "$reuse dependency reuse opportunities, more than ECHOES_MAX_REUSE=$ECHOES_MAX_REUSE in mk.local"
        if [ "$approximate" -lt "$ECHOES_MAX_APPROXIMATE" ] || [ "$reuse" -lt "$ECHOES_MAX_REUSE" ]; then
            echo "note: lower the echoes ratchet in mk.local to approximate=$approximate reuse=$reuse (./mk echoes-baseline)"
        fi
        ;;
    echoes-baseline)
        # Adoption: record today's legacy echoes counts as the ratchet (exact duplicates stay 0).
        out="$(MK_NESTED=0 "$0" echoes 2>&1 || true)"
        approximate="$(grep -oE '[0-9]+ approximate groups' <<<"$out" | head -1 | cut -d' ' -f1)"
        reuse="$(grep -oE '[0-9]+ dependency reuse' <<<"$out" | head -1 | cut -d' ' -f1)"
        [ -n "$approximate" ] && [ -n "$reuse" ] || die "could not read the echoes summary"
        for kv in "ECHOES_MAX_APPROXIMATE=$approximate" "ECHOES_MAX_REUSE=$reuse"; do
            upsert_kv_line mk.local "${kv%%=*}" "${kv#*=}"
        done
        echo "echoes ratchet: approximate=$approximate reuse=$reuse (mk.local)"
        ;;
    refquiem)
        need refquiem
        [ "$(git rev-parse --is-shallow-repository)" = false ] || die "refquiem needs full git history (fetch-depth: 0)"
        for key in 'scan-commented-code = true' 'level = "deny"'; do
            grep -q "^$key" .refquiem.toml 2>/dev/null || die ".refquiem.toml must set '$key'"
        done
        ! grep -Eq '^since *=' .refquiem.toml || die ".refquiem.toml must not truncate history with 'since'"
        if [ "${GITHUB_ACTIONS:-}" = true ]; then set -- --github "$@"; fi
        cargo refquiem --config .refquiem.toml "$@"
        has_range=0
        for arg in "$@"; do
            case "$arg" in --base | --base=* | --since | --since=*) has_range=1 ;; esac
        done
        if [ "$has_range" = 0 ] && base="$(base_ref)"; then
            mb="$(git merge-base "$base" HEAD)"
            if [ "$mb" != "$(git rev-parse HEAD)" ] || ! git diff --quiet HEAD; then
                cargo refquiem --config .refquiem.toml --base "$mb" "$@"
            fi
        fi
        ;;
    semver)
        need cargo-semver-checks
        has_lib || skip "no library target"
        # Pre-1.0 crates are in development: breaking changes need no version bump.
        if ! has_stable_version; then
            skip "every crate is pre-1.0 (in development), so breaking changes are allowed"
        fi
        base="$(git tag --merged HEAD --no-contains HEAD --list 'v*' --sort=-v:refname | head -1)"
        [ -n "$base" ] || skip "no earlier v* release tag to compare against"
        cargo semver-checks --workspace --all-features --baseline-rev "$base"
        ;;
    wasm)
        has_wasm || skip "no wasm32 target declared in rust-toolchain.toml or Cargo.toml"
        rustup target add wasm32-unknown-unknown
        cargo check --workspace --target wasm32-unknown-unknown --all-features --locked
        ;;
    mutants) cmd_mutants "$@" ;;
    mutants-diff) cmd_mutants_diff "$@" ;;
    mutants-affected) cmd_mutants_affected "$@" ;;
    mutants-plan) cmd_mutants_plan "$@" ;;
    coverage)
        need cargo-llvm-cov
        if command -v cargo-nextest >/dev/null 2>&1; then
            cargo llvm-cov nextest --workspace --all-features --locked --lcov --output-path lcov.info \
                --fail-under-lines "$COVERAGE_FAIL_UNDER_LINES" --no-tests=pass
        else
            cargo llvm-cov --workspace --all-features --locked --lcov --output-path lcov.info \
                --fail-under-lines "$COVERAGE_FAIL_UNDER_LINES"
        fi
        ;;
    coverage-baseline)
        # Adoption or after adding tests: set the floor to today's coverage (rounded down).
        need cargo-llvm-cov
        if command -v cargo-nextest >/dev/null 2>&1; then
            pct="$(cargo llvm-cov nextest --workspace --all-features --locked --summary-only --no-tests=pass | awk '/^TOTAL/{sub(/%/, "", $10); print int($10)}')"
        else
            pct="$(cargo llvm-cov --workspace --all-features --locked --summary-only | awk '/^TOTAL/{sub(/%/, "", $10); print int($10)}')"
        fi
        [ -n "$pct" ] || die "could not read line coverage"
        upsert_kv_line mk.local COVERAGE_FAIL_UNDER_LINES "\"$pct\"" \
            "# Ratchet: may only go up (./mk ratchet). Set with ./mk coverage-baseline."
        echo "COVERAGE_FAIL_UNDER_LINES: $COVERAGE_FAIL_UNDER_LINES -> $pct (the ratchet gate rejects a decrease against the base branch)"
        ;;
    powerset) need cargo-hack; cargo hack --workspace --feature-powerset --no-dev-deps check ;;
    miri)
        # Undefined behaviour, not sandboxing: tests may read the clock and the
        # environment. MIRI_PACKAGES in mk.local limits it to the crates where
        # it means something (miri cannot spawn processes or open sockets).
        cargo "+$RUST_NIGHTLY" miri --version >/dev/null 2>&1 || die "miri on $RUST_NIGHTLY is not installed; run ./mk setup nightly"
        export MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation -Zmiri-tree-borrows}"
        if [ "${#MIRI_PACKAGES[@]}" -gt 0 ]; then
            cargo "+$RUST_NIGHTLY" miri test --all-features --locked "${MIRI_PACKAGES[@]/#/--package=}"
        else
            cargo "+$RUST_NIGHTLY" miri test --workspace --all-features --locked
        fi
        ;;
    outdated) need cargo-outdated; cargo outdated --workspace --root-deps-only --exit-code 1 ;;
    ci | ci-core | ci-fast)
        gates=()
        while IFS= read -r g; do [ -n "$g" ] && gates+=("$g"); done < <(tier_gates "$cmd")
        run_tier "$cmd" "${gates[@]}" ${LOCAL_CI_GATES[@]+"${LOCAL_CI_GATES[@]/#/local:}"}
        ;;
    ci-nightly-checks | ci-nightly)
        if idle_scheduled_nightly; then
            echo "note: no commits in the last 24h on scheduled run; running only advisory/freshness gates (audit, outdated)"
            run_tier "$cmd" audit outdated
        else
            gates=()
            while IFS= read -r g; do [ -n "$g" ] && gates+=("$g"); done < <(tier_gates "$cmd")
            run_tier "$cmd" "${gates[@]}" ${LOCAL_NIGHTLY_GATES[@]+"${LOCAL_NIGHTLY_GATES[@]/#/local:}"}
        fi
        ;;
    local:*) cargo_make "${cmd#local:}" "$@" ;;
    ci-release)
        "$0" ci
        if has_publishable; then
            cargo publish --workspace --dry-run --locked
        else
            echo "[skip] publish: every crate sets publish = false"
        fi
        ;;
    selftest)
        [ -x tests/gate_selftest.sh ] || skip "the gate selftest lives in the rusti-graben template only"
        tests/gate_selftest.sh
        ;;
    *)
        # Anything else is a repository task (task_<name> function in mk.local or cargo-make).
        if declare -F "task_$cmd" >/dev/null || [ -f Makefile.toml ]; then
            cargo_make "$cmd" "$@"
            exit 0
        fi
        echo "Usage: ./mk {$(./mk --list | grep -v '^(' | paste -sd'|' -)}"
        exit 1
        ;;
esac
