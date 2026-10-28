#!/usr/bin/env bash
set -eo pipefail

TARGET_DIR="${1:-.}"
DRY_RUN="${DRY_RUN:-1}"
WITH_MUTANTS="${WITH_MUTANTS:-0}"
WITH_COVERAGE="${WITH_COVERAGE:-0}"
WITH_SEMVER="${WITH_SEMVER:-0}"
WITH_WASM="${WITH_WASM:-0}"
WITH_PREK="${WITH_PREK:-0}"

echo "==> Analyzing repository structure at: $TARGET_DIR"
if [ -f "$TARGET_DIR/Cargo.toml" ] && grep -q "\[workspace\]" "$TARGET_DIR/Cargo.toml"; then
    echo "    Detected: Cargo Workspace"
else
    echo "    Detected: Single Crate / Package"
fi

# Layout detection (best effort)
if [ -f "$TARGET_DIR/Cargo.toml" ]; then
    grep -q '\[lib\]' "$TARGET_DIR/Cargo.toml" && echo "    Detected: has [lib]" || true
    grep -q '\[\[bin\]\]' "$TARGET_DIR/Cargo.toml" && echo "    Detected: has [[bin]]" || true
    grep -q 'wasm' "$TARGET_DIR/Cargo.toml" && echo "    Detected: wasm references" || true
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> DRY-RUN mode active. Set DRY_RUN=0 to apply changes."
    echo "    Would apply: deny.toml, rust-toolchain.toml, clippy.toml, ./mk runner"
    echo "    Opt-ins: --with mutants=$WITH_MUTANTS coverage=$WITH_COVERAGE semver=$WITH_SEMVER wasm=$WITH_WASM prek=$WITH_PREK"
    echo "    Diff-before-overwrite: will not clobber existing files silently (cp -n)"
    echo "    Ratchet: clippy/coverage/mutation thresholds tracked separately (see docs)"
    exit 0
else
    echo "==> Applying hygiene files (diff-before-overwrite via cp -n)..."
    [ -f deny.toml ] && cp -n deny.toml "$TARGET_DIR/deny.toml" || true
    [ -f rust-toolchain.toml ] && cp -n rust-toolchain.toml "$TARGET_DIR/rust-toolchain.toml" || true
    [ -f clippy.toml ] && cp -n clippy.toml "$TARGET_DIR/clippy.toml" || true
    [ -f mk ] && cp mk "$TARGET_DIR/mk" && chmod +x "$TARGET_DIR/mk" || true
    [ "$WITH_MUTANTS" = "1" ] && [ -f mutants.toml ] && cp -n mutants.toml "$TARGET_DIR/mutants.toml" || true
    [ "$WITH_COVERAGE" = "1" ] && [ -f codecov.yml ] && cp -n codecov.yml "$TARGET_DIR/codecov.yml" || true
    [ "$WITH_PREK" = "1" ] && [ -f prek.toml ] && cp -n prek.toml "$TARGET_DIR/prek.toml" || true
    echo "==> Adoption complete! Run ./mk ci to verify."
    exit 0
fi
