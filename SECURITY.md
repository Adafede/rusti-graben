# Security Policy

## Scope

Security issues in `rusti-graben` include flaws in:

- [`mk`](./mk), [`mk.versions`](./mk.versions), and [`scripts/adopt.sh`](./scripts/adopt.sh) (such as unsafe shell quoting, command injection, or silent gate bypasses)
- [`.github/actions/setup/action.yml`](./.github/actions/setup/action.yml) and repository workflows in [`.github/workflows/`](./.github/workflows/)

## Reporting a Vulnerability

Please do not report security vulnerabilities in public GitHub issues.

1. Open a private report via [GitHub Security Advisories](https://github.com/Adafede/rusti-graben/security/advisories/new).
2. Include the affected file, reproduction steps or proof-of-concept command, and the expected versus observed gate or workflow behavior.
3. If private advisories are unavailable, contact the repository maintainers listed in [`CODEOWNERS`](./CODEOWNERS).
