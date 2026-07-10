#!/usr/bin/env bash
# Refresh .claude/skills/bot-reference/SKILL.md from a fresh checkout of
# TheRPGClub-bot source.
# Requires: gh CLI (authenticated), git, python3
#
# Usage (from repo root):
#   bash .claude/skills/bot-reference/refresh.sh

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_TMP="$(mktemp -d /tmp/rpgclub_bot_src_XXXXXX)"
trap 'rm -rf "$BOT_TMP"' EXIT

echo "Cloning TheRPGClub-bot (shallow)..."
gh repo clone TheRPGClub/TheRPGClub-bot "$BOT_TMP" -- --depth 1 --quiet

echo "Generating SKILL.md..."
python3 "$SKILL_DIR/generate.py" "$BOT_TMP" "$SKILL_DIR/SKILL.md"

echo "Done. Review the diff with: git diff .claude/skills/bot-reference/SKILL.md"
