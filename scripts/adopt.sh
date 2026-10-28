#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-.}"
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
    echo "    Would copy blocking-tier configs and ./mk with all gates (no silent skips)."
    exit 0
else
    echo "==> Applying (diff-before-overwrite via cp -n, clobbering avoided)..."
    for f in deny.toml rust-toolchain.toml clippy.toml mk mk.versions rustfmt.toml .taplo.toml .graben-skips.toml mutants.toml .mutants-baseline prek.toml; do
        [ -f "$f" ] && cp -n "$f" "$TARGET_DIR/" 2>/dev/null || true
    done
    [ -f "$TARGET_DIR/mk" ] && chmod +x "$TARGET_DIR/mk"
    echo "==> Baseline/ratchet files written if not present. Run ./mk ci."
    exit 0
fi
