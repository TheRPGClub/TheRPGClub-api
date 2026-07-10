---
name: learn-issue
description: Walk through implementing a GitHub issue in this repo step by step, teaching Ruby and Rails concepts along the way instead of just writing the code for you. Use when asked to "teach me issue #N", "walk me through issue #N", "help me learn by implementing #N", or "pair with me on issue #N".
---

This skill implements a GitHub issue the same way `implement` does, but slower and out loud. The goal is not a fast PR -- it's for the user to come out the other end understanding more Ruby and more of this Rails codebase than they did going in. Default to explaining and asking, not doing everything for them.

If the user just wants the issue shipped with no teaching, tell them to use `/implement <N>` instead and stop here.

The issue number is passed as the skill argument (e.g. `/learn-issue 717`).

## Ground rules for the whole session

- Narrate *why*, not just *what*. Every command or file you touch, say in one sentence why it's the right one.
- Prefer asking "want to try writing this part yourself?" over writing it for the user. If they say yes, wait for their attempt before showing your own version. If they say no or seem stuck, write it and explain it line by line.
- When you use a Ruby idiom that isn't obvious to someone new to the language (blocks, symbols, `&:method_name`, `tap`, keyword args, `||=`, module `include`/`extend`), pause and explain it briefly in place, using the actual line you just wrote as the example -- not a generic tutorial snippet.
- When you touch a Rails concept (routes, controller filters, ActiveRecord associations/scopes, serializers, migrations, RSpec `let`/`before`/`described_class`), explain how it fits into the request/response or test lifecycle, grounded in this repo's actual files.
- Keep explanations short (2-5 sentences). This is pairing, not a lecture -- check understanding before moving on rather than dumping paragraphs.

## Steps (always run in order)

### 1. Fetch and explain the issue

```bash
gh issue view <N> --json number,title,body,labels,state
```

Read the body. Before touching any code, restate the issue in plain English: what behavior changes, for whom, and why. If it's closed or doesn't exist, stop and say so.

If the issue mentions "Depends on issue #X" or "Blocked by #X", check it:

```bash
gh issue view <X> --json state,title
```

If that dependency is still open, stop and report it.

### 2. Tour the relevant code before writing anything

Find the files this issue will touch (routes, controller, model, serializer, spec) using `grep`/`find` -- not a rewrite, just a look. For each file you land on, briefly explain:
- What role it plays in Rails' request lifecycle (e.g. "this controller action gets hit after the route in `config/routes.rb` matches, and RSpec hits it directly in request specs without going through a browser").
- Any pattern already used nearby that the fix should follow (e.g. existing serializer conventions, existing scope naming).

Ask the user if they want to look at any file themselves first before you explain it.

### 3. Branch

Delegate to the `new-branch` skill using this issue's number. Do this before writing code, same as `implement` does -- explain briefly why (isolates the change, keeps `main` deployable).

### 4. Plan the change out loud

Sketch the shape of the fix in 3-6 bullet points: which files change and what each change does. Confirm with the user that the plan matches their understanding of the issue before writing code. This is the point to catch a misunderstood issue, not after code is written.

### 5. Implement, teaching as you go

For each piece of the plan:
1. Offer the user the chance to write it first ("want to take a shot at the model scope, or should I?").
2. If they write it: read their attempt, tell them plainly whether it's correct, and why -- point at the specific line, don't just say "looks good." If it's wrong, explain the bug the way you'd explain it to a colleague, not a checklist of rules.
3. If you write it: explain each non-trivial line as you go, tying it back to a Ruby/Rails concept from the ground rules above.

Stay inside the issue's scope -- no drive-by refactors, no speculative error handling, no comments unless the WHY is non-obvious. Follow the Omakase Ruby style already enforced by `.rubocop.yml`; if the user's code violates it, that's a good moment to explain the specific rule rather than silently auto-correcting it.

### 6. Lint together

```bash
bin/rubocop
```

If there are offenses, don't just run `-A` silently -- show the user the offense message and explain what it's telling them before fixing it (auto-correct is fine once they've seen it once or twice).

### 7. Test together

```bash
bundle exec rspec
```

If the change touches the database schema, run `bin/rails db:test:prepare` first so the test DB matches `db/structure.sql` -- explain briefly why RSpec needs this (the test DB schema is generated from `db/structure.sql`, not inferred from models).

If a spec fails, walk through the failure output with the user before fixing it: what RSpec is asserting, what actually happened, and where the mismatch traces back to in the implementation.

### 8. Commit and open the PR

Once RuboCop and RSpec both pass, run the same ceremony `implement` uses:

```bash
git add <changed files>
git commit -m "$(cat <<'EOF'
<type>: <short description matching issue title>

Closes #N

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git push -u origin HEAD
```

Then delegate to the `open-pr` skill, linking issue #N. Explain briefly what `Closes #N` does (auto-closes the issue when the PR merges).

### 9. Recap

Close with a short list of the Ruby/Rails concepts touched during this issue (e.g. "today: ActiveRecord scopes, RSpec `let!`, and the `&:` shorthand"). This is the one place a slightly longer summary is worth it -- it's the takeaway.

## Common mistakes to avoid

- Do NOT silently write the whole solution before the user has had a chance to try any of it.
- Do NOT explain Ruby/Rails concepts in the abstract -- always anchor to the actual line of code in front of you.
- Do NOT skip the plan-confirmation step (4) -- catching a misread issue there is much cheaper than after code is written.
- Do NOT implement more than the issue describes, even if the tour in step 2 turns up other rough code nearby.
- Do NOT open a PR if RuboCop or RSpec fails.
- Do NOT commit directly to `main`.
