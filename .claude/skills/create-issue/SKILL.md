---
name: create-issue
description: Create a GitHub issue with a well-formed title and body. Use when asked to "create an issue", "open an issue", "file an issue", or "add a GitHub issue".
---

This skill creates a single GitHub issue via `gh issue create`. Follow all steps in order.

## Steps

### 1. Determine title and labels

The title should be concise (under 70 characters) and describe the problem or work item.
Ask the user if the title is unclear. Apply any labels the user specifies.

### 2. Draft the body

Use this structure:

```
## Summary
<1-3 bullet points: what the issue is and why it matters>

## Details
<additional context, file paths, line numbers, reproduction steps, or acceptance criteria>
<omit this section if there is nothing to add beyond the summary>
```

**Formatting rules -- enforced, no exceptions:**
- Do NOT use markdown tables anywhere in the body. Use bullet lists or plain `file:line`
  lines instead.
- Do not use emdashes (--). Use a double-hyphen ( -- ) or rephrase.
- Keep lines under 100 characters.

### 3. Create the issue

Pass the body via HEREDOC to preserve formatting:

```bash
gh issue create --title "<title>" --label "<label>" --body "$(cat <<'EOF'
## Summary
- <point>

## Details
<details if needed>
EOF
)"
```

Omit `--label` if no label was specified. To apply multiple labels use a comma-separated
list: `--label "bug,refactor"`.

### 4. Report back

Print the new issue URL. If the user asked for multiple issues, repeat steps 1-3 for each
one, then print all URLs together at the end.

## Common mistakes to avoid

- Do NOT use markdown tables in the issue body.
- Do NOT put everything in the title -- use the body for details.
- Do NOT skip the HEREDOC; inline strings mangle newlines.
