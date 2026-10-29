#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-.}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN="${DRY_RUN:-1}"

echo "==> Analyzing repository structure at: $TARGET_DIR"
if [ -f "$TARGET_DIR/Cargo.toml" ] && grep -q "\[workspace\]" "$TARGET_DIR/Cargo.toml"; then
    echo "    Detected: Cargo Workspace"
else
    echo "    Detected: Single Crate / Package"
fi

echo "==> Migration checklist (blocking gates copied by default):"
echo "    [ ] Show diff before overwrite; write baseline/ratchet files"
echo "    [ ] Merge [workspace.lints.*] or create tracked allowlist"
echo "    [ ] Ensure every crate has [lints] workspace = true"
echo "    [ ] Run ./mk ci and fail hard on missing tools"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> DRY-RUN mode active. Set DRY_RUN=0 to apply changes."
    echo "    Would copy ./mk, mk.versions and gate configs that are missing; show diffs for existing ones."
    exit 0
else
    echo "==> Applying (existing files are kept; their diff against the template is shown)..."
    for f in mk mk.versions deny.toml rust-toolchain.toml clippy.toml rustfmt.toml .tombi.toml .typos.toml mutants.toml prek.toml; do
        if [ -e "$TARGET_DIR/$f" ]; then
            echo "    keep $f (differs from template:)"
            diff -u "$TARGET_DIR/$f" "$TEMPLATE_DIR/$f" || true
        else
            cp "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
            echo "    added $f"
        fi
    done
    chmod +x "$TARGET_DIR/mk"
    echo "==> Next: ./mk setup && ./mk ci. Record legacy noise as #[expect(.., reason)], mutants.toml exclusions or a lower COVERAGE_FAIL_UNDER_LINES; never by removing a gate."
    exit 0
fi
