# Adopting rusti-graben

To port the `rusti-graben` baseline to an existing Rust project without breaking builds on day one:

1. Copy `scripts/adopt.sh` into your target repository.
2. Run a dry-run analysis:
   ```bash
   DRY_RUN=1 ./scripts/adopt.sh /path/to/repo
   ```
3. Apply the baseline files (opt-ins available):
   ```bash
   WITH_MUTANTS=1 WITH_COVERAGE=1 WITH_PREK=1 DRY_RUN=0 ./scripts/adopt.sh /path/to/repo
   ```
4. Run `./mk ci` and introduce any legacy allowlists incrementally.

Notes:
- `./mk` is the single source of truth. Prek/hooks must only call `./mk <task>`.
- Never clobber existing config silently (adopt uses diff-before-overwrite via `cp -n`).
- See `./mk --help` or run `./mk` for available tasks. To list tasks programmatically, use `./mk --list-all-steps` if available in your setup (do not duplicate the task list in prose).
