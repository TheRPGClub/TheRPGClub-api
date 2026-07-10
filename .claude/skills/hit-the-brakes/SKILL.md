---
name: hit-the-brakes
description: Stop current development, commit all in-progress work as WIP, push to a branch, and open a draft PR. Use when running low on tokens mid-task, when asked to "hit the brakes", "save progress", "pause work", or "WIP PR".
---

This skill preserves in-progress work so a future session can pick it up cleanly. It is designed to run fast -- the goal is to save state, not finish the task.

## Steps (always run in order)

### 1. Check current branch

```bash
git branch --show-current
```

If on `main`, create a branch first:

```bash
git checkout -b <appropriate-branch-name>
```

Derive the branch name from recent git log or current work context. Use the same naming conventions as the `new-branch` skill (`feat/`, `fix/`, `refactor/`, etc.).

### 2. Stage and commit all in-progress changes

```bash
git status
```

Stage everything modified or untracked (excluding files in .gitignore):

```bash
git add -A
```

Commit with a WIP prefix so future sessions recognize this is incomplete:

```bash
git commit -m "$(cat <<'EOF'
wip: <short description of what is partially done>

Work in progress -- paused mid-task due to token limit. See PR description for
what has been done and what remains.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

If there is nothing to commit (tree is already clean), skip this step.

### 3. Push to remote

```bash
git push -u origin <branch-name>
```

### 4. Run lint (best-effort)

```bash
npm run lint 2>&1 | tail -20
```

Do NOT block on lint failures here -- this is an emergency save. Note any failures in the PR description instead.

### 5. Open a draft PR

Open the PR as a **draft** to signal it is not ready for merge. Build the PR body with:
- What was completed
- What still needs to be done (the remaining work list)
- Any lint failures or known issues to address

```bash
gh pr create --draft --title "wip: <short description>" --body "$(cat <<'EOF'
## Status

Work in progress -- paused mid-task.

## What was completed
- <bullet each finished piece>

## What still needs to be done
- <bullet each remaining piece>

## Known issues
- <lint failures or anything broken>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

If there are issue numbers being worked on, add one `Closes #N` line per issue after the known issues section.

### 6. Report to user

Give the user:
- The branch name
- The PR URL
- A short bullet list of what is done vs. what remains

## Common mistakes to avoid

- Do NOT open a non-draft PR -- this work is incomplete.
- Do NOT spend time fixing lint errors -- note them and move on.
- Do NOT skip the "what still needs to be done" section -- it is the whole point.
- Do NOT refuse to commit because the code is incomplete -- that is expected.
