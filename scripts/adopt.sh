#!/usr/bin/env bash
# Adopt the rusti-graben gates in an existing Rust repository, or bring an
# adopted one up to date with the template.
#
#   scripts/adopt.sh <repo>              # dry run: print what would change
#   DRY_RUN=0 scripts/adopt.sh <repo>    # apply
#
# Idempotent. The standard runner (mk, mk.versions, .mk/*, the setup action) is
# synced to the template's; repository-specific settings live in mk.local, which
# is never overwritten. Any other existing file is kept and its diff against the
# template printed for a manual merge.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$(cd "${1:-.}" && pwd)"
DRY_RUN="${DRY_RUN:-1}"
ADOPT_MUTANTS="${ADOPT_MUTANTS:-1}"
ADOPT_ECHOES="${ADOPT_ECHOES:-1}"
ADOPT_REFQUIEM="${ADOPT_REFQUIEM:-1}"
ADOPT_WORKFLOWS="${ADOPT_WORKFLOWS:-1}"

STANDARD=(
    mk
    mk.versions
    .mk/catalog.sh
    .mk/core.sh
    .mk/gates.sh
    .mk/meta.py
    .mk/mutants.sh
    .mk/mutants_plan.sh
    .mk/nightly.sh
    .mk/tier.sh
    .mk/tools.sh
    .github/actions/setup/action.yml
)
MARKER="rusti-graben standard runner"
FILES=(
    rust-toolchain.toml rustfmt.toml clippy.toml deny.toml
    .config/nextest.toml bacon.toml .editorconfig .vscode/settings.json
    .tombi.toml .typos.toml prek.toml CLAUDE.md
    .github/PULL_REQUEST_TEMPLATE.md .github/dependabot.yml renovate.json
)
[ "$ADOPT_MUTANTS" = 1 ] && FILES+=(.cargo/mutants.toml)
[ "$ADOPT_ECHOES" = 1 ] && FILES+=(.echoes.toml)
[ "$ADOPT_REFQUIEM" = 1 ] && FILES+=(.refquiem.toml)
[ "$ADOPT_WORKFLOWS" = 1 ] && FILES+=(.github/workflows/ci.yml .github/workflows/nightly.yml .github/workflows/release.yml)
GITIGNORE_LINES=(lcov.info 'mutants.out*/')
CARGO_MAKE_VERSION="0.37.24"

changes=0
layout="single"

act() {
    local what="$1"
    shift
    changes=$((changes + 1))
    if [ "$DRY_RUN" = 0 ]; then
        "$@"
        echo "    $what"
    else
        echo "    would: $what"
    fi
}

copy_file() { mkdir -p "$(dirname "$2")" && cp "$1" "$2"; }
seed_agents() {
    grep -Ev 'scripts/adopt\.sh|tests/gate_selftest\.sh|tests/selftest/|crates/sample-|selftest|Template-only|\.agents/PLAYBOOK\.md' \
        "$TEMPLATE_DIR/AGENTS.md" >AGENTS.md
}
seed_debt() {
    mkdir -p docs && sed -e '/@Adafede/d' -e '/sample-bin/d' -e '/^## Ratchet Floors/,$d' \
        "$TEMPLATE_DIR/docs/DEBT.md" >docs/DEBT.md
}
write_mk_local() { sed "/^# Ratchet:/,\$d" "$TEMPLATE_DIR/mk.local" >mk.local; }
append_cargo_make_pin() { printf "LOCAL_CARGO_TOOLS=(cargo-make@%s)\n" "$CARGO_MAKE_VERSION" >>mk.local; }
append_toml_block() { printf '\n%s\n' "$1" >>"$2"; }
append_workspace_lint_inherit() { printf '\n[lints]\nworkspace = true\n' >>"$1"; }
drop_deny_placeholder() {
    sed -i.bak '/own license (scripts\/adopt.sh replaces it)/d' deny.toml
    rm -f deny.toml.bak
}
set_deny_placeholder() {
    sed -i.bak "s|^  \"[^\"]*\", *# this project's own license (scripts/adopt.sh replaces it)|  \"$1\",  # this project's own license|" deny.toml
    rm -f deny.toml.bak
}
append_gitignore() {
    [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && printf '\n' >>.gitignore
    printf '%s\n' "$1" >>.gitignore
}
strip_trailing_blanks() { awk 'NF{last=NR} {lines[NR]=$0} END{for(i=1;i<=last;i++) print lines[i]}'; }
add_debug_profiles() {
    [ -s Cargo.toml ] && [ -n "$(tail -c1 Cargo.toml)" ] && printf '\n' >>Cargo.toml
    printf '\n[profile.dev.package."*"]\ndebug = false\n\n[profile.test.package."*"]\ndebug = false\n' >>Cargo.toml
    if command -v tombi >/dev/null 2>&1; then tombi format Cargo.toml >/dev/null 2>&1 || true; fi
}

validate_target() {
    [ -f "$TARGET_DIR/Cargo.toml" ] || { echo "ERROR: $TARGET_DIR has no Cargo.toml" >&2; exit 1; }
    [ "$TARGET_DIR" != "$TEMPLATE_DIR" ] || { echo "ERROR: target is the template itself" >&2; exit 1; }
}

sync_standard_runner() {
    echo "==> Standard runner"
    if [ -e mk ] && ! grep -q "$MARKER" mk; then
        if grep -q 'cargo make' mk; then
            echo "    mk wraps cargo-make: the standard mk replaces it and runs every other task through cargo-make"
        else
            echo "ERROR: mk is this repository's own runner; port its tasks to mk.local first" >&2
            exit 1
        fi
    fi
    local f
    for f in "${STANDARD[@]}"; do
        if [ ! -e "$f" ]; then
            act "add $f" copy_file "$TEMPLATE_DIR/$f" "$f"
        elif ! diff -q "$f" "$TEMPLATE_DIR/$f" >/dev/null; then
            act "sync $f with the template" copy_file "$TEMPLATE_DIR/$f" "$f"
        fi
    done
    if [ ! -e mk.local ]; then
        act "add mk.local" write_mk_local
        if [ -f Makefile.toml ]; then
            act "pin cargo-make in mk.local" append_cargo_make_pin
            echo "    TODO: list this repository's own cargo-make gates in mk.local (LOCAL_CI_GATES, LOCAL_OVERRIDES)"
        fi
    fi
}

sync_gate_files() {
    echo "==> Gate files"
    local f
    for f in "${FILES[@]}"; do
        if [ -e "$f" ]; then
            if ! diff -q "$f" "$TEMPLATE_DIR/$f" >/dev/null; then
                echo "    keep $f (merge by hand; template diff below)"
                diff -u "$f" "$TEMPLATE_DIR/$f" | sed 's/^/      /' || true
            fi
        else
            act "add $f" copy_file "$TEMPLATE_DIR/$f" "$f"
        fi
    done
    [ -e AGENTS.md ] || act "add AGENTS.md" seed_agents
    [ -e docs/DEBT.md ] || act "add docs/DEBT.md" seed_debt
}

configure_deny_license() {
    echo "==> deny.toml: allow this project's own license, not the template's"
    local own deny_src="deny.toml"
    own="$(sed -n 's/^license *= *"\([^"]*\)".*/\1/p' Cargo.toml | head -1)"
    if [ -z "$own" ]; then
        own="$(python3 -B "$TEMPLATE_DIR/.mk/meta.py" license 2>/dev/null || true)"
    fi
    [ -e "$deny_src" ] || deny_src="$TEMPLATE_DIR/deny.toml"
    if grep -q "own license (scripts/adopt.sh replaces it)" "$deny_src" 2>/dev/null; then
        if [ -z "$own" ] || [[ "$own" == *" "* ]] ||
            grep -v 'own license (scripts/adopt.sh replaces it)' "$deny_src" | grep -qF "\"$own\""; then
            act "drop the template's own-license entry" drop_deny_placeholder
        else
            act "allow $own (this project's license)" set_deny_placeholder "$own"
        fi
    fi
}

configure_lints() {
    echo "==> Lints"
    local lint_block rustdoc_block
    lint_block="$(awk '/^\[workspace\.lints\./{p=1} /^\[/ && !/^\[workspace\.lints\./{p=0} p' "$TEMPLATE_DIR/Cargo.toml" | strip_trailing_blanks)"
    rustdoc_block="$(awk '/^\[workspace\.lints\.rustdoc\]/{p=1} /^\[/ && !/^\[workspace\.lints\.rustdoc\]/{p=0} p' "$TEMPLATE_DIR/Cargo.toml" | strip_trailing_blanks)"
    if grep -Eq '^\[(workspace\.)?lints\.' Cargo.toml; then
        if ! grep -Eq '^\[(workspace\.)?lints\.rustdoc\]' Cargo.toml; then
            if [ "$layout" = workspace ]; then
                act "add [workspace.lints.rustdoc] to Cargo.toml" append_toml_block "$rustdoc_block" Cargo.toml
            else
                act "add [lints.rustdoc] to Cargo.toml" append_toml_block \
                    "$(printf '%s\n' "$rustdoc_block" | sed 's/^\[workspace\.lints\./[lints./')" Cargo.toml
            fi
        else
            echo "    keep the existing lint tables; compare with the template's:"
            printf '%s\n' "$lint_block" | sed 's/^/      /'
        fi
    elif [ "$layout" = workspace ]; then
        act "add [workspace.lints.*] to Cargo.toml" append_toml_block "$lint_block" Cargo.toml
    else
        act "add [lints.*] to Cargo.toml" append_toml_block \
            "$(printf '%s\n' "$lint_block" | sed 's/^\[workspace\.lints\./[lints./')" Cargo.toml
    fi
}

configure_member_lints() {
    [ "$layout" = workspace ] || return 0
    local manifest
    while IFS= read -r manifest; do
        [ -n "$manifest" ] || continue
        if ! awk '/^\[lints\]/{s=1;next} /^\[/{s=0} s && /^workspace *= *true/{f=1} END{exit !f}' "$manifest"; then
            act "make ${manifest#"$TARGET_DIR"/} inherit workspace lints" append_workspace_lint_inherit "$manifest"
        fi
    done < <(python3 -B "$TEMPLATE_DIR/.mk/meta.py" manifests)
}

configure_debug_profiles() {
    if ! grep -Eq '^\[profile\.(dev|test)' Cargo.toml; then
        act "add dev/test dependency debug=false profiles to Cargo.toml" add_debug_profiles
    fi
}

configure_gitignore() {
    echo "==> .gitignore"
    local line
    for line in "${GITIGNORE_LINES[@]}"; do
        grep -qxF "$line" .gitignore 2>/dev/null || act "ignore $line" append_gitignore "$line"
    done
}

print_next_steps() {
    echo "==> $changes change(s)$([ "$DRY_RUN" = 1 ] && echo ' planned; rerun with DRY_RUN=0 to apply')"
    [ "$DRY_RUN" = 0 ] || return 0
    if ! grep -q '^rust-version' Cargo.toml &&
        [ -z "$(python3 -B "$TEMPLATE_DIR/.mk/meta.py" msrv 2>/dev/null || true)" ]; then
        echo "    TODO: set rust-version in Cargo.toml (the msrv gate requires it)"
    fi
    cat <<'EOF'
==> Next, in the adopted repository:
    ./mk setup                 # pinned toolchains and tools (needs cargo-binstall)
    ./mk coverage-baseline     # set the coverage floor to today's value
    ./mk ci                    # fix or record each finding (docs/ADOPTING.md)
    prek install               # optional: run ./mk in git hooks
EOF
}

main() {
    validate_target
    cd "$TARGET_DIR"
    if grep -q '^\[workspace\]' Cargo.toml; then layout=workspace; fi
    echo "==> $TARGET_DIR ($layout crate layout, DRY_RUN=$DRY_RUN)"
    sync_standard_runner
    sync_gate_files
    configure_deny_license
    configure_lints
    configure_member_lints
    configure_debug_profiles
    configure_gitignore
    print_next_steps
}

main "$@"
