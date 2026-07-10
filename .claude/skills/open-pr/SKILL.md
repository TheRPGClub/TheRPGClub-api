---
name: open-pr
description: Open a pull request following the full CLAUDE.md PR ceremony: lint, build body with one Closes #X per line, create PR, then verify closing-issue linkage. Use when asked to "open a PR", "create PR", or "submit PR for issue #N".
---

This skill encodes the mandatory PR ceremony for this repo. Run it every time a PR needs to be opened -- do not skip steps.

This is the Rails/RuboCop copy of this skill, scoped to this repo (the API). It overrides the generic version for any work done here -- no translation guessing required.

## Steps (always run in order)

### 1. Lint

```bash
bin/rubocop -A
```

If offenses remain after auto-correct, fix them by hand. The fixes must be committed to the branch as part of the PR.

### 2. Confirm branch

The PR must be opened from a feature or fix branch, never from `main`. Verify the current branch:

```bash
git branch --show-current
```

If on `main`, stop and tell the user.

### 3. Build the PR body

Each issue being closed must get its own `Closes #X` line. Comma-separated closes on a single line are **not** reliably picked up by GitHub.

Format:
```
## Summary
<1-3 bullet points describing what changed and why>

## Test plan
<bulleted checklist of how to verify the change>

Closes #N
Closes #M

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Pass the body via HEREDOC to preserve formatting:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
- <point 1>

## Test plan
- [ ] <step>

Closes #N

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 4. Verify closing-issue linkage

After the PR is created, capture the PR number from the `gh pr create` output and verify:

```bash
gh pr view <N> --json closingIssuesReferences
```

Expected output contains each linked issue number. If an issue is missing, GitHub did not pick up the `Closes` line -- check formatting and update the PR body.

Report the linkage result to the user, then give the PR URL.

## Common mistakes to avoid

- Do NOT put multiple issue numbers on one `Closes` line (`Closes #1, #2` is unreliable).
- Do NOT skip the linkage verification step.
- Do NOT open the PR before RuboCop is clean.
- Do NOT open a PR from `main`.
