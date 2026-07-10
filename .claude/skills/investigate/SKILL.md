---
name: investigate
description: Investigate an error reported in a GitHub issue, trace it through the codebase, and rewrite the issue with findings. Use when asked to "/investigate N", "investigate issue #N", or "dig into issue #N".
---

This skill takes a GitHub issue number, reads the reported error or problem, investigates the
codebase to find root causes and relevant context, then rewrites the issue body with structured
findings so it is ready to implement.

The issue number is passed as the skill argument (e.g. `/investigate 123`).

This is the Rails copy of this skill, scoped to this repo (the API). It overrides the generic
version for any work done here -- no translation guessing required.

## Steps (always run in order)

### 1. Fetch the issue

```bash
gh issue view <N> --json number,title,body,labels,state,comments
```

Read the full body and all comments. Extract:
- The reported error message (exact text, stack traces, log lines)
- Steps to reproduce (if any)
- Files or commands mentioned
- Any prior analysis already in comments

If the issue is closed or does not exist, stop and report that to the user.

### 2. Identify search targets

From the error message and issue text, extract concrete search terms:
- Method names, class/module names mentioned in stack traces
- Error string literals / exception class names
- Route names, controller actions, job names
- File paths mentioned (`app/...`, `lib/...`, `db/...`)

### 3. Trace the code

Using targeted greps and narrow file reads, trace the code path related to the error.
Do NOT read entire large files -- use grep, then read only the relevant line ranges.

For each relevant finding, record:
- File path and line number(s)
- What the code does
- Why it is relevant to the reported error

Look for:
- The exact controller action, service, or model method where the error likely originates
- Any data flow leading to that point (params, upstream callers, DB queries)
- Error handling gaps or incorrect assumptions
- Related code that may be affected

```bash
grep -rn "<term>" app/ lib/ spec/ --include="*.rb"
```

### 4. Check git history for context

If the error involves a specific method or file, check recent changes:

```bash
git log --oneline -20 -- <file>
```

This may surface a recent commit that introduced the regression.

### 5. Formulate findings

Based on the investigation, produce:

- **Root cause**: one or two sentences describing exactly why the error occurs
- **Code location**: file:line where the fix needs to happen
- **Reproduction path**: the exact sequence of events that triggers it
- **Suggested fix**: a concrete, scoped description of what to change (not implementation -- just direction)
- **Related files**: any other files that will need to be touched

If the root cause is unclear after investigation, document what was ruled out and what
still needs to be determined.

### 6. Rewrite the issue

Update the issue body using `gh issue edit`. Preserve the original report in a collapsed
`<details>` block. Structure the new body as:

```
## Summary
- <1-3 bullets: what the bug is and why it matters>

## Root Cause
<One paragraph: exactly why the error occurs, with file:line references>

## Reproduction Path
1. <step>
2. <step>
...

## Code Location
- `<file>:<line>` -- <what is wrong here>
- `<file>:<line>` -- <any related location>

## Suggested Fix
<Concrete description of what to change, scoped to the root cause.
Not a full implementation -- just enough for /implement to take over.>

## Original Report
<details>
<summary>Original issue body</summary>

<original body text here>

</details>
```

**Formatting rules -- enforced, no exceptions:**
- Do NOT use markdown tables. Use bullet lists or plain `file:line` references.
- Do not use emdashes. Use a double-hyphen ( -- ) or rephrase.
- Keep lines under 100 characters.

Apply the edit:

```bash
gh issue edit <N> --body "$(cat <<'EOF'
<rewritten body>
EOF
)"
```

### 7. Add an investigation comment

Post a brief comment summarizing the findings so the history is preserved:

```bash
gh issue comment <N> --body "$(cat <<'EOF'
**Investigation complete.**

Root cause: <one sentence>
Fix location: `<file>:<line>`

Issue body updated with full findings.
EOF
)"
```

### 8. Report back

Print the issue URL and a one-line summary of the root cause.

## Common mistakes to avoid

- Do NOT rewrite the issue without doing real codebase investigation first.
- Do NOT guess at root causes -- trace the actual code path.
- Do NOT lose the original report -- always wrap it in `<details>`.
- Do NOT use markdown tables in the issue body.
- Do NOT put multiple concerns in one root cause -- if there are multiple bugs, say so clearly.
- Do NOT read entire large files -- always grep first, then read targeted line ranges.
