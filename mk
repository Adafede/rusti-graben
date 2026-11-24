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

intersect_mutants_scope() {
    local pkg m keep
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if [ "${#MUTANTS_PACKAGES[@]}" -eq 0 ]; then
            printf '%s\n' "$pkg"
            continue
        fi
        keep=0
        for m in "${MUTANTS_PACKAGES[@]}"; do
            if [ "$pkg" = "$m" ]; then
                keep=1
                break
            fi
        done
        [ "$keep" = 0 ] || printf '%s\n' "$pkg"
    done
}

scoped_packages_for_mutants() {
    local mode="$1" base="${2:-}"
    case "$mode" in
        changed) changed_rust_packages "$base" | intersect_mutants_scope ;;
        affected) affected_packages "$base" | intersect_mutants_scope ;;
        full) workspace_packages | intersect_mutants_scope ;;
        *) die "unknown scope mode '$mode'" ;;
    esac
}

# --- mutation testing -------------------------------------------------------

# cargo-mutants rebuilds a crate once per mutant, in scratch copies, for hours.
# Unbounded, that wedged developer machines (twice, once at --jobs 2) and cost a
# CI runner its connection to GitHub (lotus-explore-rs, 2026-11-01). So every
# run is bounded by construction, whatever the caller passes:
# - concurrency: MUTANTS_JOBS mutants at once (default 1 locally, half the cores
#   on CI), with --jobserver-tasks capped to match so rustc never fans out to NCPUS;
#   --in-place (or MUTANTS_IN_PLACE=1) omits --jobs because cargo-mutants rejects both;
# - size & cache: debuginfo off (debug=0), --gitignore=true by default, and for
#   out-of-place jobs == 1 a persistent CARGO_TARGET_DIR (.../target/mutants) guarded
#   by an atomic mkdir lockdir (jobs > 1 unsets CARGO_TARGET_DIR for isolation);
# - priority: nice 19, so the desktop stays responsive;
# - a watchdog: it refuses to start, and stops a running mutation run with
#   SIGINT (so cargo-mutants removes its scratch copies), when available memory
#   or free disk falls below a floor, rather than let the machine swap itself to
#   a halt. Floors: MUTANTS_MIN_FREE_MEM_PCT (default 15) and
#   MUTANTS_MIN_FREE_DISK_GB (default 10), on the repository's and TMPDIR's volumes.
MUTANTS_MIN_FREE_MEM_PCT="${MUTANTS_MIN_FREE_MEM_PCT:-15}"
MUTANTS_MIN_FREE_DISK_GB="${MUTANTS_MIN_FREE_DISK_GB:-10}"
_MK_MUTANTS_PID=""
_MK_MUTANTS_LOCK=""
_MK_MUTANTS_ABORTED=0
_MK_DIFF_TMP=""

cleanup_mutants_trap() {
    _MK_MUTANTS_ABORTED=1
    if [ -n "$_MK_MUTANTS_PID" ]; then
        kill -INT -- "-$_MK_MUTANTS_PID" 2>/dev/null || true
    fi
}

cleanup_diff_tmp() {
    if [ -n "$_MK_DIFF_TMP" ]; then
        rm -f "$_MK_DIFF_TMP"
    fi
}

cores() { getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2; }

# Available memory as a whole percentage, or nothing where it cannot be read.
# macOS: the kernel's own availability level, the figure jetsam acts on, read
# as 0 once the kernel reports critical pressure.
free_mem_pct() {
    if [ -r /proc/meminfo ]; then
        awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { if (t) print int(a * 100 / t) }' /proc/meminfo
    elif [ "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" = 4 ]; then
        echo 0
    else
        sysctl -n kern.memorystatus_level 2>/dev/null || true
    fi
}

free_disk_gb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print int($4 / 1048576) }'; }

# Why the machine is below a floor, or nothing when it is not.
mutants_starved() {
    local mem disk dir
    mem="$(free_mem_pct)"
    if [ -n "$mem" ] && [ "$mem" -lt "$MUTANTS_MIN_FREE_MEM_PCT" ]; then
        echo "available memory ${mem}% < ${MUTANTS_MIN_FREE_MEM_PCT}% (MUTANTS_MIN_FREE_MEM_PCT)"
        return
    fi
    for dir in "$ROOT_DIR" "${TMPDIR:-/tmp}"; do
        disk="$(free_disk_gb "$dir")"
        if [ -n "$disk" ] && [ "$disk" -lt "$MUTANTS_MIN_FREE_DISK_GB" ]; then
            echo "free disk ${disk} GB on $dir < ${MUTANTS_MIN_FREE_DISK_GB} GB (MUTANTS_MIN_FREE_DISK_GB)"
            return
        fi
    done
}

# run_mutants <cargo-mutants args...>: the only way mk starts cargo-mutants.
run_mutants() {
    need cargo-mutants
    local n jobs threads reason pid rc=0 in_place=0
    local has_in_place_arg=0 has_gitignore=0 has_jobserver_cap=0
    local has_custom_config=0 custom_config="" expect_config=0 arg
    n="$(cores)"
    if [ "${MUTANTS_IN_PLACE:-0}" = 1 ]; then
        in_place=1
    fi
    for arg in "$@"; do
        if [ "$expect_config" = 1 ]; then
            custom_config="$arg"
            expect_config=0
            continue
        fi
        case "$arg" in
            --in-place)
                in_place=1
                has_in_place_arg=1
                ;;
            --gitignore | --gitignore=*) has_gitignore=1 ;;
            --jobserver-tasks | --jobserver-tasks=* | --jobserver=false) has_jobserver_cap=1 ;;
            --no-config) has_custom_config=1 ;;
            --config)
                has_custom_config=1
                expect_config=1
                ;;
            --config=*)
                has_custom_config=1
                custom_config="${arg#--config=}"
                ;;
        esac
    done
    if [ "$has_gitignore" = 0 ]; then
        if [ "$has_custom_config" = 0 ] && [ -f .cargo/mutants.toml ] &&
            grep -Eq '^[[:space:]]*gitignore[[:space:]]*=' .cargo/mutants.toml; then
            has_gitignore=1
        elif [ -n "$custom_config" ] && [ -f "$custom_config" ] &&
            grep -Eq '^[[:space:]]*gitignore[[:space:]]*=' "$custom_config"; then
            has_gitignore=1
        fi
    fi
    if [ "$in_place" = 1 ]; then
        jobs=1
        if [ -n "${CI:-}" ]; then
            threads="$n"
        else
            threads=$((n / 2))
        fi
    elif [ -n "${CI:-}" ]; then
        jobs="${MUTANTS_JOBS:-$((n > 3 ? n / 2 : 1))}"
        threads=$((n / jobs))
    else
        jobs="${MUTANTS_JOBS:-1}"
        threads=$((n / jobs / 2))
    fi
    [ "$threads" -ge 1 ] || threads=1
    if [ -z "${TMPDIR:-}" ]; then
        local tmp_disk
        if [ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ]; then
            export TMPDIR="$RUNNER_TEMP"
        elif tmp_disk="$(free_disk_gb /tmp)" && [ "${tmp_disk:-0}" -lt "$MUTANTS_MIN_FREE_DISK_GB" ]; then
            mkdir -p "$ROOT_DIR/target/tmp"
            export TMPDIR="$ROOT_DIR/target/tmp"
        fi
    fi
    reason="$(mutants_starved)"
    [ -z "$reason" ] || die "not starting cargo-mutants: $reason"
    local -a scope=(--workspace)
    if [ "${#MUTANTS_PACKAGES[@]}" -gt 0 ]; then scope=("${MUTANTS_PACKAGES[@]/#/--package=}"); fi
    # A caller naming its own packages (`./mk mutants -p crate`) replaces the default.
    if has_pkg_flag "$@"; then scope=(); fi
    local -a extra_args=()
    if [ "$has_gitignore" = 0 ]; then extra_args+=(--gitignore=true); fi
    if [ "$in_place" = 1 ]; then
        [ "$has_in_place_arg" = 1 ] || extra_args+=(--in-place)
        [ "$has_jobserver_cap" = 1 ] || extra_args+=(--jobserver-tasks "$threads")
    else
        extra_args+=(--jobs "$jobs")
        [ "$has_jobserver_cap" = 1 ] || extra_args+=(--jobserver-tasks "$((jobs * threads))")
    fi
    local inc="${MUTANTS_INCREMENTAL:-1}"
    case "${RUSTC_WRAPPER:-}${RUSTC_WORKSPACE_WRAPPER:-}" in
        *sccache*) inc=0 ;;
    esac
    local -a env_args=(
        CARGO_BUILD_JOBS="$threads"
        NEXTEST_TEST_THREADS="$threads"
        CARGO_INCREMENTAL="$inc"
        CARGO_PROFILE_DEV_DEBUG=0
        CARGO_PROFILE_TEST_DEBUG=0
    )
    local lock_dir=""
    if [ "$in_place" = 0 ] && [ "$jobs" -eq 1 ]; then
        local base_target="${CARGO_TARGET_DIR:-$ROOT_DIR/target}" mutants_target
        base_target="${base_target%/}"
        case "$base_target" in
            /*) ;;
            *) base_target="$ROOT_DIR/$base_target" ;;
        esac
        case "$base_target" in
            */mutants) mutants_target="$base_target" ;;
            *) mutants_target="$base_target/mutants" ;;
        esac
        lock_dir="${mutants_target}.lock"
        mkdir -p "$(dirname "$mutants_target")"
        local waited=0 owner_pid
        while ! mkdir "$lock_dir" 2>/dev/null; do
            owner_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
            if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
                rm -rf "$lock_dir"
                continue
            fi
            if [ "$waited" = 0 ]; then
                echo "mutants: waiting for lock $lock_dir..."
                waited=1
            fi
            sleep 1 || true
        done
        printf '%s\n' "$$" >"$lock_dir/pid"
        env_args+=(CARGO_TARGET_DIR="$mutants_target")
    elif [ "$in_place" = 0 ]; then
        env_args=(-u CARGO_TARGET_DIR "${env_args[@]}")
    fi
    if [ "$in_place" = 1 ]; then
        echo "mutants: in-place, $threads build/test threads, $n cores;" \
            "stops below ${MUTANTS_MIN_FREE_MEM_PCT}% memory or ${MUTANTS_MIN_FREE_DISK_GB} GB disk"
    else
        echo "mutants: $jobs at a time, $threads build/test threads each, $n cores;" \
            "stops below ${MUTANTS_MIN_FREE_MEM_PCT}% memory or ${MUTANTS_MIN_FREE_DISK_GB} GB disk"
    fi
    # Its own process group, so the watchdog and Ctrl-C reach every rustc and test.
    set -m
    env "${env_args[@]}" nice -n 19 cargo mutants ${extra_args[@]+"${extra_args[@]}"} ${scope[@]+"${scope[@]}"} --all-features "$@" &
    pid=$!
    set +m
    _MK_MUTANTS_PID="$pid"
    _MK_MUTANTS_LOCK="$lock_dir"
    _MK_MUTANTS_ABORTED=0
    trap 'cleanup_mutants_trap' INT TERM
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$_MK_MUTANTS_ABORTED" = 1 ]; then
            break
        fi
        reason="$(mutants_starved)"
        if [ -n "$reason" ]; then
            echo "ERROR: stopping cargo-mutants: $reason" >&2
            kill -INT -- "-$pid" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 2 || true
            done
            kill -KILL -- "-$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            [ -z "$lock_dir" ] || rm -rf "$lock_dir"
            _MK_MUTANTS_PID=""
            _MK_MUTANTS_LOCK=""
            exit 1
        fi
        sleep 2 || true
    done
    wait "$pid" || rc=$?
    trap - INT TERM
    [ -z "$lock_dir" ] || rm -rf "$lock_dir"
    _MK_MUTANTS_PID=""
    _MK_MUTANTS_LOCK=""
    return "$rc"
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
    mutants)
        # Exit 2 = missed mutants, 3 = timeouts: both fail. Exclusions live in .cargo/mutants.toml.
        # Extra arguments go to cargo-mutants: `./mk mutants -p crate` runs one crate.
        run_mutants "$@"
        ;;
    mutants-diff)
        # Mutants in code changed against the base branch (and uncommitted changes), on every PR.
        need cargo-mutants
        base="$(base_ref)" || skip "no base branch to compare with (set MK_BASE)"
        pkg_args=()
        if ! has_pkg_flag "$@"; then
            scoped=()
            while IFS= read -r p; do [ -n "$p" ] && scoped+=("$p"); done < <(scoped_packages_for_mutants changed "$base")
            [ "${#scoped[@]}" -gt 0 ] || skip "no Rust changes in mutation scope against $base"
            pkg_args=("${scoped[@]/#/--package=}")
        fi
        _MK_DIFF_TMP="$(mktemp)"
        trap 'cleanup_diff_tmp' EXIT
        write_rust_diff "$base" "$_MK_DIFF_TMP"
        [ -s "$_MK_DIFF_TMP" ] || skip "no Rust changes against $base"
        run_mutants ${pkg_args[@]+"${pkg_args[@]}"} --in-diff "$_MK_DIFF_TMP" "$@"
        ;;
    mutants-affected)
        need cargo-mutants
        if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
            base="$1"
            shift
            git rev-parse -q --verify "$base^{commit}" >/dev/null || die "unknown base ref '$base'"
        else
            base="$(base_ref)" || skip "no base branch to compare with (set MK_BASE)"
        fi
        pkg_args=()
        if ! has_pkg_flag "$@"; then
            scoped=()
            while IFS= read -r p; do [ -n "$p" ] && scoped+=("$p"); done < <(scoped_packages_for_mutants affected "$base")
            [ "${#scoped[@]}" -gt 0 ] || skip "no affected packages in mutation scope against $base"
            pkg_args=("${scoped[@]/#/--package=}")
        fi
        run_mutants ${pkg_args[@]+"${pkg_args[@]}"} "$@"
        ;;
    mutants-plan)
        need cargo-mutants
        command -v python3 >/dev/null || die "python3 is required"
        mode="diff"
        base=""
        has_explicit_base=0
        while [ $# -gt 0 ]; do
            case "$1" in
                --mode)
                    [ $# -ge 2 ] || die "--mode requires a value"
                    mode="$2"
                    shift 2
                    ;;
                --mode=*)
                    mode="${1#--mode=}"
                    shift
                    ;;
                --base)
                    [ $# -ge 2 ] || die "--base requires a value"
                    base="$2"
                    has_explicit_base=1
                    shift 2
                    ;;
                --base=*)
                    base="${1#--base=}"
                    has_explicit_base=1
                    shift
                    ;;
                *) die "unknown mutants-plan argument '$1'" ;;
            esac
        done
        case "$mode" in
            diff | affected | full) ;;
            *) die "invalid --mode '$mode' (expected diff, affected, or full)" ;;
        esac
        emit_plan() {
            python3 "$ROOT_DIR/.mk/meta.py" plan-json "$@"
        }
        if [ "$mode" = diff ] || [ "$mode" = affected ]; then
            if [ "$has_explicit_base" = 1 ]; then
                git rev-parse -q --verify "$base^{commit}" >/dev/null || die "unknown base ref '$base'"
            elif ! base="$(base_ref)"; then
                emit_plan "$mode" 0 0
                exit 0
            fi
        fi
        scoped=()
        case "$mode" in
            diff)
                while IFS= read -r p; do [ -n "$p" ] && scoped+=("$p"); done < <(scoped_packages_for_mutants changed "$base")
                ;;
            affected)
                while IFS= read -r p; do [ -n "$p" ] && scoped+=("$p"); done < <(scoped_packages_for_mutants affected "$base")
                ;;
            full)
                while IFS= read -r p; do [ -n "$p" ] && scoped+=("$p"); done < <(scoped_packages_for_mutants full "")
                ;;
        esac
        if [ "${#scoped[@]}" -eq 0 ]; then
            emit_plan "$mode" 0 0
            exit 0
        fi
        list_cmd=(cargo mutants --list "${scoped[@]/#/--package=}" --all-features)
        if [ "$mode" = diff ]; then
            _MK_DIFF_TMP="$(mktemp)"
            trap 'cleanup_diff_tmp' EXIT
            write_rust_diff "$base" "$_MK_DIFF_TMP"
            if [ ! -s "$_MK_DIFF_TMP" ]; then
                emit_plan "$mode" 0 0
                exit 0
            fi
            list_cmd+=(--in-diff "$_MK_DIFF_TMP")
        fi
        list_out="$("${list_cmd[@]}")"
        mutants="$(awk 'NF{c++} END{print c+0}' <<<"$list_out")"
        if [ "$mode" = diff ]; then
            target="${MUTANTS_TARGET_PER_SHARD:-150}"
            max_shards="${MUTANTS_MAX_SHARDS:-4}"
        else
            target="${MUTANTS_TARGET_PER_SHARD:-250}"
            max_shards="${MUTANTS_MAX_SHARDS:-8}"
        fi
        [[ "$target" =~ ^[1-9][0-9]*$ ]] || die "MUTANTS_TARGET_PER_SHARD must be a positive integer, got '$target'"
        [[ "$max_shards" =~ ^[1-9][0-9]*$ ]] || die "MUTANTS_MAX_SHARDS must be a positive integer, got '$max_shards'"
        shards="$(python3 "$ROOT_DIR/.mk/meta.py" shards "$mutants" "$target" "$max_shards")"
        emit_plan "$mode" "$mutants" "$shards" "${scoped[@]}"
        ;;
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
