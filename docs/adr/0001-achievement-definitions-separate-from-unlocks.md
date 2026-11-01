# Achievement definitions are stored separately from Unlocks

Achievements and Achievement Sets are shared, provider-scoped rows; a member's Unlocks are a separate table keyed by member and Achievement, with a cached per-member progress row per set. xergasa (the single-user codebase this hub is ported from) stores `unlocked`/`unlocked_at` on the achievement row itself; that cannot represent many members, so the port deliberately departs from it rather than copying the schema.

## Consequences

- Rarity and definitions are refreshed whenever any member's sync touches the set, not once per member.
- Unlinking a Linked Account deletes only that member's Unlocks and progress; definitions stay.
