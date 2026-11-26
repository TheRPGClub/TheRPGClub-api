# TheRPGClub API

## Agent skills

### Issue tracker

Issues and specs live in this repo's GitHub Issues (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Pull requests and versions

Each merge to main versions this repo (spec #510, ADR 0016; `.github/workflows/versioning.yml`), so a pull request title must be typed. The required PR title check refuses anything else.

- **Title:** `type(scope)!: description`, e.g. `feat(api): add the versions read`. `type` is one of `feat`, `fix`, `perf`, `refactor`, `chore`, `docs`, `test`, `ci`. `(scope)` is optional; `description` follows a colon and a space.
- **Bump:** `feat` bumps the minor version; `fix` and `perf` the patch version; `refactor`, `chore`, `docs`, `test` and `ci` make no version.
- **`!` means breaking:** `feat!:` or `fix(api)!:` (any type) bumps the major version, as does a body line starting `BREAKING CHANGE:`. Use it only when the owner asks for a major; majors are deliberate.
- **Patch note:** the PR template's optional `Patch note:` line is one sentence in members' words. Each version becomes a Pending Change, and staff start that change's Patch line from it (else from the title). Leave it empty when members won't notice.
- Versioning does nothing until the repo has a `v*` tag. The shared workflows (`versioning-reusable.yml`, `pr-title-reusable.yml`) and their rules (`script/versioning/`, tested in `spec/versioning/`) live here; the bot and www call them.
