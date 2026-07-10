#!/usr/bin/env python3
"""
Generate .claude/skills/bot-reference/SKILL.md from a local checkout of
TheRPGClub-bot source.

Usage:
    python3 generate.py <bot repo root> <output SKILL.md>
"""

import os
import re
import sys

SLASH_RE = re.compile(r"@Slash\(\s*\{(.*?)\}\s*\)", re.DOTALL)
NAME_RE = re.compile(r'name:\s*"([^"]*)"')
DESC_RE = re.compile(r'description:\s*"([^"]*)"')

# api(Get|GetRaw|Post|Patch|Delete)<T>( `path` | "path" )
CALL_RE = re.compile(
    r"\bapi(Get|GetRaw|Post|Patch|Delete)\b(?:<[^>()]*>)?\(\s*[\r\n]?\s*[`\"]([^`\"]*)[`\"]"
)
TEMPLATE_EXPR_RE = re.compile(r"\$\{[^}]*\}")
ENV_VAR_RE = re.compile(r"process\.env\.([A-Z_][A-Z0-9_]*)")

METHOD_MAP = {
    "Get": "GET",
    "GetRaw": "GET",
    "Post": "POST",
    "Patch": "PATCH",
    "Delete": "DELETE",
}

SKIP_DIRS = {"node_modules", "build", ".git", "dist"}

# Purpose of each top-level src/ directory. Hand-maintained -- update if the
# bot's structure changes in a way that makes these stale.
SRC_DIR_PURPOSE = {
    "commands": "Slash command definitions (DiscordX `@Discord()` / `@Slash()` classes).",
    "events": "Discord gateway event handlers (member join/leave, reactions, presence, etc.).",
    "classes": "Domain model classes -- most read/write the API via RpgClubApiClient.",
    "services": "Cross-cutting services (IGDB client, image handling, Backblaze, GitHub App).",
    "functions": "Standalone helper functions used across commands/classes.",
    "config": "Centralized constants: channel IDs, user IDs, tag IDs, roles, colors, emojis.",
    "db": "Bot-owned Postgres access for data that has NOT been migrated to the API yet.",
    "utilities": "Small generic utility helpers (formatting, parsing, etc.).",
    "scripts": "One-off / operational scripts run via `npm run <script>`, not part of the bot process.",
    "types": "Shared TypeScript type definitions.",
    "tests": "`node --test` test suite (`npm test`).",
    "data": "Static bundled data files (e.g. Pokopia data).",
    "assets": "Static assets (images) bundled with the bot.",
}


def iter_ts_files(root: str, subdir: str = "src"):
    base = os.path.join(root, subdir)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in filenames:
            if fname.endswith(".ts") and not fname.endswith(".d.ts"):
                yield os.path.join(dirpath, fname)


def relpath(root: str, path: str) -> str:
    return os.path.relpath(path, root).replace(os.sep, "/")


def extract_slash_commands(root: str) -> dict[str, list[str]]:
    commands: dict[str, list[str]] = {}
    for path in iter_ts_files(root):
        with open(path, encoding="utf-8", errors="ignore") as f:
            content = f.read()
        matches = SLASH_RE.findall(content)
        if not matches:
            continue
        rel = relpath(root, path)
        for block in matches:
            name_m = NAME_RE.search(block)
            desc_m = DESC_RE.search(block)
            if not name_m:
                continue
            name = name_m.group(1)
            desc = desc_m.group(1) if desc_m else ""
            line = f"/{name}" + (f"  # {desc}" if desc else "")
            commands.setdefault(rel, []).append(line)
    return commands


def extract_api_calls(root: str) -> dict[str, set[str]]:
    """Map "METHOD /path" -> set of relative file paths that call it."""
    calls: dict[str, set[str]] = {}
    client_file = os.path.join(root, "src", "services", "RpgClubApiClient.ts")
    for path in iter_ts_files(root):
        if os.path.abspath(path) == os.path.abspath(client_file):
            continue
        with open(path, encoding="utf-8", errors="ignore") as f:
            content = f.read()
        rel = relpath(root, path)
        for helper, raw_path in CALL_RE.findall(content):
            method = METHOD_MAP[helper]
            normalized = TEMPLATE_EXPR_RE.sub("{id}", raw_path)
            if not normalized.startswith("/"):
                continue
            key = f"{method:<6} {normalized}"
            calls.setdefault(key, set()).add(rel)
    return calls


def extract_env_vars(root: str) -> list[str]:
    names: set[str] = set()
    for path in iter_ts_files(root):
        with open(path, encoding="utf-8", errors="ignore") as f:
            content = f.read()
        names.update(ENV_VAR_RE.findall(content))
    return sorted(names)


def extract_direct_sql_files(root: str) -> list[str]:
    db_dir = os.path.join(root, "src", "db")
    if not os.path.isdir(db_dir):
        return []
    files = []
    for path in iter_ts_files(root, "src/db"):
        rel = relpath(root, path)
        if rel.endswith("/index.ts") or rel.endswith("/types.ts"):
            continue
        files.append(rel)
    return sorted(files)


def extract_config_files(root: str) -> list[str]:
    config_dir = os.path.join(root, "src", "config")
    if not os.path.isdir(config_dir):
        return []
    return sorted(f for f in os.listdir(config_dir) if f.endswith(".ts"))


def extract_src_tree(root: str) -> list[str]:
    src_dir = os.path.join(root, "src")
    if not os.path.isdir(src_dir):
        return []
    dirs = sorted(
        d for d in os.listdir(src_dir)
        if os.path.isdir(os.path.join(src_dir, d)) and d not in SKIP_DIRS
    )
    lines = []
    for d in dirs:
        purpose = SRC_DIR_PURPOSE.get(d, "")
        suffix = f" -- {purpose}" if purpose else ""
        lines.append(f"src/{d}/{suffix}")
    return lines


def build_skill(root: str) -> str:
    commands = extract_slash_commands(root)
    calls = extract_api_calls(root)
    env_vars = extract_env_vars(root)
    direct_sql_files = extract_direct_sql_files(root)
    config_files = extract_config_files(root)
    src_tree = extract_src_tree(root)

    call_lines = []
    for key in sorted(calls):
        files = ", ".join(f"`{f}`" for f in sorted(calls[key]))
        call_lines.append(f"{key}  <- {files}")
    calls_body = "\n".join(call_lines)

    command_sections = []
    for rel in sorted(commands):
        block = "\n".join(commands[rel])
        command_sections.append(f"### `{rel}`\n\n```\n{block}\n```")
    commands_body = "\n\n".join(command_sections)

    env_body = "\n".join(f"- `{v}`" for v in env_vars)
    sql_body = "\n".join(f"- `{f}`" for f in direct_sql_files) or "(none found)"
    config_body = "\n".join(f"- `src/config/{f}`" for f in config_files)
    tree_body = "\n".join(src_tree)

    return f"""\
---
name: bot-reference
description: >
  Reference for TheRPGClub-bot's codebase -- structure, conventions, config, environment
  variables, and which API endpoints it calls from where. Use when writing or reviewing API
  code and you need context on how the bot consumes or would be affected by a change. This
  is a read-only reference skill -- it does not perform actions.
---

TheRPGClub-bot is a Discord bot (TypeScript, Node.js ESM, Discord.js v14, DiscordX) that
powers GameDB lookups, Monthly Games (GOTM/NR-GOTM) workflows, member profiles, backlog and
collection tracking, and various community utilities for the RPG Club Discord server. This
API is its primary data store; a shrinking set of features still use a bot-owned Postgres
database directly (see "Data not yet migrated to the API" below).

Repo: https://github.com/TheRPGClub/TheRPGClub-bot

## Directory structure (src/)

```
{tree_body}
```

## Configuration conventions

Discord channel IDs, user IDs, tag IDs, and similar constants are centralized under
`src/config/` rather than inlined at call sites:

{config_body}

## Data not yet migrated to the API

Most bot features read/write through the API client (see below). A few domains still query
a bot-owned Postgres database directly via `src/db/sql/`:

{sql_body}

If an issue mentions migrating one of these to the API, expect a matching endpoint to be
added here first, then the bot's `src/db/sql/*.sql.ts` file for it to be retired.

## Environment variables the bot reads

Generated from `process.env.*` usage across `src/`. Not all are required in every
environment; `RPGCLUB_API_BASE_URL` and `RPGCLUB_BOT_API_TOKEN` are what the bot uses to
authenticate to this API.

{env_body}

## Running and testing the bot locally

- `npm run dev` -- run with ts-node (no build step)
- `npm run compile` -- `tsc --noEmit`, type-check only
- `npm run lint` -- ESLint
- `npm test` -- `node --test` over `src/tests/*.test.ts`
- `bash .claude/skills/run-rpgclubbot/smoke.sh` (bot repo only) -- type-check + lint + tests

The bot cannot connect to Discord or a live Postgres instance in most dev/agent sandboxes.

## Self-update

When asked to refresh this reference or when the bot's code may have changed:

```bash
bash .claude/skills/bot-reference/refresh.sh
```

Then commit and push the updated `SKILL.md`:

```bash
git add .claude/skills/bot-reference/SKILL.md
git commit -m "chore: refresh bot-reference skill from latest bot source"
git push
```

---

## API endpoints called by the bot

The important part when changing an endpoint here: this tells you which bot files call it,
so you know the blast radius before you touch its shape or behavior. Path parameters
(`${{...}}` template expressions) are normalized to `{{id}}`; a few entries where a template
literal starts with a variable rather than a literal path segment may render oddly -- treat
those as approximate and check the source file directly.

```
{calls_body}
```

## Client helpers (bot: src/services/RpgClubApiClient.ts)

```ts
apiGet<T>(path, config?)          // GET; returns T | null (null on 404)
apiGetRaw<T>(path, config?)       // GET; returns full metadata, never throws on 4xx/5xx
apiPost<T>(path, body?, config?)  // POST; returns T | null (null on 404)
apiPatch<T>(path, body?, config?) // PATCH; returns T | null (null on 404)
apiDelete<T>(path, config?)       // DELETE; returns T | null (null on 404)
```

404 is treated as "not found" (`null`), not an error -- every other non-2xx status throws.
Write calls send `{{ data: {{ <attributes> }} }}` and expect the same envelope shape back
that this API returns (`{{ data: ... }}`, `{{ data: [...], meta: {{...}} }}`, or
`{{ deleted: true }}`). Changing those envelopes here breaks the bot without a bot-side
release.

## Bot slash commands

Grouped by the bot source file that defines them.

{commands_body}

---

## Source references

- Bot repo: https://github.com/TheRPGClub/TheRPGClub-bot
- Bot README: `README.md`
- Bot API client: `src/services/RpgClubApiClient.ts`
- Bot commands: `src/commands/`, `src/events/`
- Bot-owned SQL (not yet migrated): `src/db/sql/`
"""


def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <bot repo root> <output SKILL.md>", file=sys.stderr)
        sys.exit(1)

    bot_root, output_path = sys.argv[1], sys.argv[2]

    content = build_skill(bot_root)

    with open(output_path, "w") as f:
        f.write(content)

    print(f"Written: {output_path}")


if __name__ == "__main__":
    main()
