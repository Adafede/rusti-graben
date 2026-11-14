#!/usr/bin/env bash
# Adopt the rusti-graben gates in an existing Rust repository, or bring an
# adopted one up to date with the template.
#
#   scripts/adopt.sh <repo>              # dry run: print what would change
#   DRY_RUN=0 scripts/adopt.sh <repo>    # apply
#
# Idempotent. The standard runner (mk, mk.versions, the setup action) is synced
# to the template's; repository-specific settings live in mk.local, which is
# never overwritten. Any other existing file is kept and its diff against the
# template printed for a manual merge. Every gate stays on; legacy noise is
# recorded as described in docs/ADOPTING.md.
# `sh -c` snippets are single-quoted on purpose: "$1" expands in the subshell.
# shellcheck disable=SC2016
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$(cd "${1:-.}" && pwd)"
DRY_RUN="${DRY_RUN:-1}"
ADOPT_MUTANTS="${ADOPT_MUTANTS:-1}"
ADOPT_ECHOES="${ADOPT_ECHOES:-1}"
ADOPT_REFQUIEM="${ADOPT_REFQUIEM:-1}"
ADOPT_WORKFLOWS="${ADOPT_WORKFLOWS:-1}"

# Standard: always synced to the template (they hold no repository settings).
STANDARD=(mk mk.versions .github/actions/setup/action.yml)
MARKER="rusti-graben standard runner"
# Copied when missing. Template-only files (selftest, sample crates) are skipped;
# AGENTS.md and docs/DEBT.md are seeded with template-specific lines stripped.
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

[ -f "$TARGET_DIR/Cargo.toml" ] || { echo "ERROR: $TARGET_DIR has no Cargo.toml" >&2; exit 1; }
[ "$TARGET_DIR" != "$TEMPLATE_DIR" ] || { echo "ERROR: target is the template itself" >&2; exit 1; }

changes=0
act() { # act <description> <command...>: run it when applying, report it either way.
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

# copy_file <src> <dest>: creates parent directories; keeps the executable bit.
copy_file() { mkdir -p "$(dirname "$2")" && cp "$1" "$2"; }
seed_agents() {
    grep -Ev 'scripts/adopt\.sh|tests/gate_selftest\.sh|crates/sample-|selftest|Template-only|\.agents/PLAYBOOK\.md' \
        "$TEMPLATE_DIR/AGENTS.md" >AGENTS.md
}
seed_debt() {
    mkdir -p docs && sed -e '/@Adafede/d' -e '/sample-bin/d' -e '/^## Ratchet Floors/,$d' \
        "$TEMPLATE_DIR/docs/DEBT.md" >docs/DEBT.md
}
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

cd "$TARGET_DIR"
root=Cargo.toml
if grep -q '^\[workspace\]' "$root"; then layout=workspace; else layout=single; fi
echo "==> $TARGET_DIR ($layout crate layout, DRY_RUN=$DRY_RUN)"

echo "==> Standard runner"
if [ -e mk ] && ! grep -q "$MARKER" mk; then
    if grep -q 'cargo make' mk; then
        echo "    mk wraps cargo-make: the standard mk replaces it and runs every other task through cargo-make"
    else
        echo "ERROR: mk is this repository's own runner; port its tasks to mk.local first" >&2
        exit 1
    fi
fi
for f in "${STANDARD[@]}"; do
    if [ ! -e "$f" ]; then
        act "add $f" copy_file "$TEMPLATE_DIR/$f" "$f"
    elif ! diff -q "$f" "$TEMPLATE_DIR/$f" >/dev/null; then
        act "sync $f with the template" copy_file "$TEMPLATE_DIR/$f" "$f"
    fi
done
if [ ! -e mk.local ]; then
    # The template's documented keys, without its own coverage floor.
    act "add mk.local" sh -c 'sed "/^# Ratchet:/,\$d" "$1" >mk.local' _ "$TEMPLATE_DIR/mk.local"
    if [ -f Makefile.toml ]; then
        act "pin cargo-make in mk.local" sh -c 'printf "LOCAL_CARGO_TOOLS=(cargo-make@%s)\n" "$1" >>mk.local' _ "$CARGO_MAKE_VERSION"
        echo "    TODO: list this repository's own cargo-make gates in mk.local (LOCAL_CI_GATES, LOCAL_OVERRIDES)"
    fi
fi

echo "==> Gate files"
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

echo "==> deny.toml: allow this project's own license, not the template's"
own="$(sed -n 's/^license *= *"\([^"]*\)".*/\1/p' "$root" | head -1)"
if [ -z "$own" ]; then
    own="$(cargo metadata --no-deps --format-version 1 2>/dev/null | grep -o '"license":"[^"]*"' | cut -d'"' -f4 | sort -u | head -1 || true)"
fi
deny_src=deny.toml
[ -e "$deny_src" ] || deny_src="$TEMPLATE_DIR/deny.toml"
# Only for the template's deny.toml (just copied, or about to be in a dry run).
if grep -q "own license (scripts/adopt.sh replaces it)" "$deny_src" 2>/dev/null; then
    if [ -z "$own" ] || [[ "$own" == *" "* ]] || grep -v 'own license (scripts/adopt.sh replaces it)' "$deny_src" | grep -qF "\"$own\""; then
        # No single license, an expression, or already in the allow-list: drop the template entry.
        act "drop the template's own-license entry" drop_deny_placeholder
    else
        act "allow $own (this project's license)" set_deny_placeholder "$own"
    fi
fi

echo "==> Lints"
lint_block="$(awk '/^\[workspace\.lints\./{p=1} p' "$TEMPLATE_DIR/Cargo.toml")"
rustdoc_block="$(awk '/^\[workspace\.lints\.rustdoc\]/{p=1} p' "$TEMPLATE_DIR/Cargo.toml")"
if grep -Eq '^\[(workspace\.)?lints\.' "$root"; then
    if ! grep -Eq '^\[(workspace\.)?lints\.rustdoc\]' "$root"; then
        if [ "$layout" = workspace ]; then
            act "add [workspace.lints.rustdoc] to Cargo.toml" sh -c 'printf "\n%s\n" "$1" >>Cargo.toml' _ "$rustdoc_block"
        else
            act "add [lints.rustdoc] to Cargo.toml" sh -c 'printf "\n%s\n" "$1" | sed "s/^\[workspace\.lints\./[lints./" >>Cargo.toml' _ "$rustdoc_block"
        fi
    else
        echo "    keep the existing lint tables; compare with the template's:"
        printf '%s\n' "$lint_block" | sed 's/^/      /'
    fi
elif [ "$layout" = workspace ]; then
    act "add [workspace.lints.*] to Cargo.toml" sh -c 'printf "\n%s\n" "$1" >>Cargo.toml' _ "$lint_block"
else
    act "add [lints.*] to Cargo.toml" sh -c 'printf "\n%s\n" "$1" | sed "s/^\[workspace\.lints\./[lints./" >>Cargo.toml' _ "$lint_block"
fi
if [ "$layout" = workspace ]; then
    while IFS= read -r manifest; do
        [ -n "$manifest" ] || continue
        if ! awk '/^\[lints\]/{s=1;next} /^\[/{s=0} s && /^workspace *= *true/{f=1} END{exit !f}' "$manifest"; then
            act "make ${manifest#"$TARGET_DIR"/} inherit workspace lints" sh -c 'printf "\n[lints]\nworkspace = true\n" >>"$1"' _ "$manifest"
        fi
    done < <(cargo metadata --no-deps --format-version 1 | grep -o '"manifest_path":"[^"]*"' | cut -d'"' -f4)
fi

echo "==> .gitignore"
for line in "${GITIGNORE_LINES[@]}"; do
    grep -qxF "$line" .gitignore 2>/dev/null || act "ignore $line" append_gitignore "$line"
done

echo "==> $changes change(s)$([ "$DRY_RUN" = 1 ] && echo ' planned; rerun with DRY_RUN=0 to apply')"
if [ "$DRY_RUN" = 0 ]; then
    grep -q '^rust-version' "$root" || cargo metadata --no-deps --format-version 1 2>/dev/null | grep -q '"rust_version":"' || echo "    TODO: set rust-version in Cargo.toml (the msrv gate requires it)"
    cat <<'EOF'
==> Next, in the adopted repository:
    ./mk setup                 # pinned toolchains and tools (needs cargo-binstall)
    ./mk coverage-baseline     # set the coverage floor to today's value
    ./mk ci                    # fix or record each finding (docs/ADOPTING.md)
    prek install               # optional: run ./mk in git hooks
EOF
fi
