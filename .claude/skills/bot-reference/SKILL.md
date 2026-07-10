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
src/assets/ -- Static assets (images) bundled with the bot.
src/classes/ -- Domain model classes -- most read/write the API via RpgClubApiClient.
src/commands/ -- Slash command definitions (DiscordX `@Discord()` / `@Slash()` classes).
src/config/ -- Centralized constants: channel IDs, user IDs, tag IDs, roles, colors, emojis.
src/data/ -- Static bundled data files (e.g. Pokopia data).
src/db/ -- Bot-owned Postgres access for data that has NOT been migrated to the API yet.
src/events/ -- Discord gateway event handlers (member join/leave, reactions, presence, etc.).
src/functions/ -- Standalone helper functions used across commands/classes.
src/scripts/ -- One-off / operational scripts run via `npm run <script>`, not part of the bot process.
src/services/ -- Cross-cutting services (IGDB client, image handling, Backblaze, GitHub App).
src/tests/ -- `node --test` test suite (`npm test`).
src/types/ -- Shared TypeScript type definitions.
src/utilities/ -- Small generic utility helpers (formatting, parsing, etc.).
```

## Configuration conventions

Discord channel IDs, user IDs, tag IDs, and similar constants are centralized under
`src/config/` rather than inlined at call sites:

- `src/config/channels.ts`
- `src/config/colors.ts`
- `src/config/customIdPrefixes.ts`
- `src/config/emojis.ts`
- `src/config/flags.ts`
- `src/config/gamedbCsvPlatformMap.ts`
- `src/config/journalConstants.ts`
- `src/config/nominationChannels.ts`
- `src/config/pagination.ts`
- `src/config/repos.ts`
- `src/config/roles.ts`
- `src/config/standardPlatforms.ts`
- `src/config/tags.ts`
- `src/config/textLimits.ts`
- `src/config/users.ts`

## Data not yet migrated to the API

Most bot features read/write through the API client (see below). A few domains still query
a bot-owned Postgres database directly via `src/db/sql/`:

- `src/db/SqlManager.ts`
- `src/db/postgresClient.ts`
- `src/db/sql/adminWizardSession.sql.ts`
- `src/db/sql/collectionCsvImport.sql.ts`
- `src/db/sql/completionatorImport.sql.ts`
- `src/db/sql/hltbCache.sql.ts`
- `src/db/sql/member.sql.ts`
- `src/db/sql/steamCollectionImport.sql.ts`

If an issue mentions migrating one of these to the API, expect a matching endpoint to be
added here first, then the bot's `src/db/sql/*.sql.ts` file for it to be retired.

## Environment variables the bot reads

Generated from `process.env.*` usage across `src/`. Not all are required in every
environment; `RPGCLUB_API_BASE_URL` and `RPGCLUB_BOT_API_TOKEN` are what the bot uses to
authenticate to this API.

- `ANNOUNCEMENTS_CHANNEL_ID`
- `BACKBLAZE_B2_APPLICATION_KEY`
- `BACKBLAZE_B2_BUCKET_ID`
- `BACKBLAZE_B2_BUCKET_NAME`
- `BACKBLAZE_B2_BUCKET_PUBLIC`
- `BACKBLAZE_B2_KEY_ID`
- `BOT_TOKEN`
- `DOCKER_BACKUP_DIR`
- `DOCKER_BACKUP_ENABLED`
- `DOCKER_BACKUP_EXCLUDE`
- `DOCKER_BACKUP_IMAGE`
- `DOCKER_BACKUP_VOLUMES`
- `GITHUB_APP_ID`
- `GITHUB_APP_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY`
- `GITHUB_REPO_NAME`
- `GITHUB_REPO_OWNER`
- `GOOGLE_API_KEY`
- `IGDB_CLIENT_ID`
- `IGDB_CLIENT_SECRET`
- `PG_CONNECTION_STRING`
- `RICH_PRESENCE_NOW_PLAYING_PROMPTS_ENABLED`
- `RPGCLUB_API_BASE_URL`
- `RPGCLUB_BOT_API_TOKEN`
- `SEARCH_ID`
- `STEAM_API_KEY`
- `STEAM_WEB_API_KEY`

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
(`${...}` template expressions) are normalized to `{id}`; a few entries where a template
literal starts with a variable rather than a literal path segment may render oddly -- treat
those as approximate and check the source file directly.

```
DELETE /api/v1/backlog/{id}  <- `src/classes/UserGameBacklog.ts`
DELETE /api/v1/collections/{id}  <- `src/classes/UserGameCollection.ts`
DELETE /api/v1/completions/{id}  <- `src/classes/Member.ts`
DELETE /api/v1/game_keys/{id}  <- `src/classes/GameKey.ts`
DELETE /api/v1/gotm_entries/{id}  <- `src/classes/Gotm.ts`
DELETE /api/v1/journal_entries/{id}  <- `src/classes/Member.ts`
DELETE /api/v1/now_playing/{id}  <- `src/classes/Member.ts`
DELETE /api/v1/nr_gotm_entries/{id}  <- `src/classes/NrGotm.ts`
DELETE /api/v1/public_reminders/{id}  <- `src/classes/PublicReminder.ts`
DELETE /api/v1/rss_feeds/{id}  <- `src/classes/RssFeed.ts`
DELETE /api/v1/search_synonym_drafts/{id}  <- `src/classes/GameSearchSynonymDraft.ts`
DELETE /api/v1/search_synonym_groups/{id}  <- `src/classes/GameSearchSynonym.ts`
DELETE /api/v1/search_synonym_groups/{id}/terms  <- `src/classes/GameSearchSynonym.ts`
DELETE /api/v1/search_synonyms/{id}  <- `src/classes/GameSearchSynonym.ts`
DELETE /api/v1/suggestions/{id}  <- `src/classes/Suggestion.ts`
DELETE /api/v1/threads/{id}/links  <- `src/classes/Thread.ts`
DELETE /api/v1/user_socials/{id}  <- `src/commands/profile.command.ts`
DELETE /api/v1/voting_info/{id}  <- `src/classes/BotVotingInfo.ts`
DELETE /api/v1/{id}/{id}/nominations/{id}  <- `src/classes/Nomination.ts`
GET    /api/v1/backlog/{id}  <- `src/classes/UserGameBacklog.ts`
GET    /api/v1/bot_presence  <- `src/classes/BotPresenceHistory.ts`
GET    /api/v1/bot_presence/latest  <- `src/classes/BotPresenceHistory.ts`
GET    /api/v1/collections/{id}  <- `src/classes/UserGameCollection.ts`
GET    /api/v1/companies/{id}  <- `src/classes/GameProfileService.ts`
GET    /api/v1/completions/leaderboard  <- `src/classes/Member.ts`
GET    /api/v1/completions/{id}  <- `src/classes/Member.ts`
GET    /api/v1/game_keys  <- `src/classes/GameKey.ts`
GET    /api/v1/game_keys/{id}  <- `src/classes/GameKey.ts`
GET    /api/v1/games  <- `src/classes/Game.ts`, `src/classes/GameReleaseAnnouncement.ts`, `src/classes/GameSearchService.ts`
GET    /api/v1/games/{id}  <- `src/classes/Game.ts`
GET    /api/v1/games/{id}/images  <- `src/classes/Game.ts`, `src/services/GameImageService.ts`
GET    /api/v1/games/{id}/journal  <- `src/classes/Member.ts`
GET    /api/v1/games/{id}/profile  <- `src/classes/GameProfileService.ts`
GET    /api/v1/games/{id}/relations  <- `src/classes/GameProfileService.ts`
GET    /api/v1/games/{id}/releases  <- `src/classes/Game.ts`
GET    /api/v1/games/{id}/threads  <- `src/classes/Thread.ts`
GET    /api/v1/gotm_entries  <- `src/classes/Gotm.ts`
GET    /api/v1/igdb/search  <- `src/commands/gamedb/gamedb-add.command.ts`
GET    /api/v1/journal_entries  <- `src/classes/Member.ts`
GET    /api/v1/journal_entries/contributors  <- `src/classes/Member.ts`
GET    /api/v1/journal_entries/{id}  <- `src/classes/Member.ts`
GET    /api/v1/now_playing  <- `src/classes/Member.ts`
GET    /api/v1/nr_gotm_entries  <- `src/classes/NrGotm.ts`
GET    /api/v1/platforms  <- `src/classes/GamePlatformRegionService.ts`
GET    /api/v1/platforms/{id}  <- `src/classes/GamePlatformRegionService.ts`
GET    /api/v1/public_reminders  <- `src/classes/PublicReminder.ts`
GET    /api/v1/public_reminders/due  <- `src/classes/PublicReminder.ts`
GET    /api/v1/regions  <- `src/classes/GamePlatformRegionService.ts`
GET    /api/v1/regions/{id}  <- `src/classes/GamePlatformRegionService.ts`
GET    /api/v1/release_announcements/due  <- `src/classes/GameReleaseAnnouncement.ts`
GET    /api/v1/rss_feeds  <- `src/classes/RssFeed.ts`
GET    /api/v1/rss_feeds/{id}/items  <- `src/classes/RssFeed.ts`
GET    /api/v1/search_synonym_drafts/{id}  <- `src/classes/GameSearchSynonymDraft.ts`
GET    /api/v1/search_synonym_groups  <- `src/classes/GameSearchSynonym.ts`
GET    /api/v1/search_synonym_groups/{id}  <- `src/classes/GameSearchSynonym.ts`
GET    /api/v1/search_synonyms  <- `src/classes/GameSearchSynonym.ts`
GET    /api/v1/search_synonyms/{id}  <- `src/classes/GameSearchSynonym.ts`
GET    /api/v1/social_platforms  <- `src/commands/profile.command.ts`
GET    /api/v1/starboard/{id}  <- `src/classes/Starboard.ts`
GET    /api/v1/suggestions  <- `src/classes/Suggestion.ts`
GET    /api/v1/suggestions/{id}  <- `src/classes/Suggestion.ts`
GET    /api/v1/threads/{id}  <- `src/classes/Thread.ts`
GET    /api/v1/users  <- `src/classes/Member.ts`, `src/commands/mp-info.command.ts`, `src/commands/profile.command.ts`
GET    /api/v1/users/avatar_history_counts  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}  <- `src/classes/Member.ts`, `src/commands/profile.command.ts`
GET    /api/v1/users/{id}/avatar_history  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/backlog  <- `src/classes/UserGameBacklog.ts`
GET    /api/v1/users/{id}/collections  <- `src/classes/UserGameCollection.ts`
GET    /api/v1/users/{id}/collections/platform_summary  <- `src/classes/UserGameCollection.ts`
GET    /api/v1/users/{id}/completions  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/game_keys  <- `src/classes/GameKey.ts`
GET    /api/v1/users/{id}/giveaway_settings  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/journal  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/journal/status  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/nick_history  <- `src/commands/profile.command.ts`
GET    /api/v1/users/{id}/now_playing  <- `src/classes/Member.ts`
GET    /api/v1/users/{id}/presence_prompt_opts  <- `src/classes/PresencePromptOptOut.ts`
GET    /api/v1/users/{id}/presence_prompts  <- `src/classes/PresencePromptHistory.ts`
GET    /api/v1/users/{id}/socials  <- `src/commands/profile.command.ts`
GET    /api/v1/voting_info  <- `src/classes/BotVotingInfo.ts`
GET    /api/v1/voting_info/current  <- `src/classes/BotVotingInfo.ts`
GET    /api/v1/voting_info/{id}  <- `src/classes/BotVotingInfo.ts`
GET    /api/v1/{id}/{id}/nominations  <- `src/classes/Nomination.ts`
GET    /api/v1/{id}/{id}/nominations/{id}  <- `src/classes/Nomination.ts`
PATCH  /api/v1/backlog/{id}  <- `src/classes/UserGameBacklog.ts`
PATCH  /api/v1/collections/{id}  <- `src/classes/UserGameCollection.ts`
PATCH  /api/v1/completions/{id}  <- `src/classes/Member.ts`
PATCH  /api/v1/games/{id}  <- `src/classes/Game.ts`
PATCH  /api/v1/games/{id}/release_announcements  <- `src/classes/GameReleaseAnnouncement.ts`
PATCH  /api/v1/gotm_entries/{id}  <- `src/classes/Gotm.ts`
PATCH  /api/v1/journal_entries/{id}  <- `src/classes/Member.ts`
PATCH  /api/v1/now_playing/{id}  <- `src/classes/Member.ts`
PATCH  /api/v1/nr_gotm_entries/{id}  <- `src/classes/NrGotm.ts`
PATCH  /api/v1/presence_prompts/{id}  <- `src/classes/PresencePromptHistory.ts`
PATCH  /api/v1/public_reminders/{id}  <- `src/classes/PublicReminder.ts`
PATCH  /api/v1/release_announcements/{id}  <- `src/classes/GameReleaseAnnouncement.ts`
PATCH  /api/v1/rss_feeds/{id}  <- `src/classes/RssFeed.ts`
PATCH  /api/v1/search_synonym_drafts/{id}  <- `src/classes/GameSearchSynonymDraft.ts`
PATCH  /api/v1/search_synonyms/{id}  <- `src/classes/GameSearchSynonym.ts`
PATCH  /api/v1/threads/{id}  <- `src/classes/Thread.ts`
PATCH  /api/v1/user_socials/{id}  <- `src/commands/profile.command.ts`
PATCH  /api/v1/users/{id}  <- `src/classes/Member.ts`
PATCH  /api/v1/users/{id}/giveaway_settings  <- `src/classes/Member.ts`
PATCH  /api/v1/users/{id}/presence_prompt_opts  <- `src/classes/PresencePromptOptOut.ts`
PATCH  /api/v1/voting_info/{id}  <- `src/classes/BotVotingInfo.ts`
POST   /api/v1/bot_presence  <- `src/classes/BotPresenceHistory.ts`
POST   /api/v1/game_keys  <- `src/classes/GameKey.ts`
POST   /api/v1/game_keys/{id}/claim  <- `src/classes/GameKey.ts`
POST   /api/v1/games  <- `src/classes/Game.ts`, `src/commands/gamedb/gamedb-add.command.ts`, `src/commands/gamedb/gamedb-view.command.ts`
POST   /api/v1/games/{id}/alternates  <- `src/classes/Game.ts`
POST   /api/v1/games/{id}/refresh-images  <- `src/classes/Game.ts`, `src/commands/superadmin.command.ts`
POST   /api/v1/games/{id}/refresh-releases  <- `src/functions/GameIgdbSync.ts`
POST   /api/v1/games/{id}/releases  <- `src/classes/Game.ts`
POST   /api/v1/gotm_entries  <- `src/classes/Gotm.ts`
POST   /api/v1/nr_gotm_entries  <- `src/classes/NrGotm.ts`
POST   /api/v1/platforms  <- `src/classes/GamePlatformRegionService.ts`
POST   /api/v1/public_reminders  <- `src/classes/PublicReminder.ts`
POST   /api/v1/regions  <- `src/classes/GamePlatformRegionService.ts`
POST   /api/v1/rss_feeds  <- `src/classes/RssFeed.ts`
POST   /api/v1/rss_feeds/{id}/items  <- `src/classes/RssFeed.ts`
POST   /api/v1/search_synonym_drafts  <- `src/classes/GameSearchSynonymDraft.ts`
POST   /api/v1/search_synonym_groups  <- `src/classes/GameSearchSynonym.ts`
POST   /api/v1/search_synonyms  <- `src/classes/GameSearchSynonym.ts`
POST   /api/v1/starboard  <- `src/classes/Starboard.ts`
POST   /api/v1/suggestions  <- `src/classes/Suggestion.ts`
POST   /api/v1/threads  <- `src/classes/Thread.ts`
POST   /api/v1/threads/{id}/links  <- `src/classes/Thread.ts`
POST   /api/v1/users/mark_departed  <- `src/classes/Member.ts`
POST   /api/v1/users/upsert  <- `src/classes/Member.ts`
POST   /api/v1/users/{id}/avatar_history  <- `src/classes/Member.ts`
POST   /api/v1/users/{id}/backlog  <- `src/classes/UserGameBacklog.ts`
POST   /api/v1/users/{id}/collections  <- `src/classes/UserGameCollection.ts`
POST   /api/v1/users/{id}/completions  <- `src/classes/Member.ts`
POST   /api/v1/users/{id}/journal  <- `src/classes/Member.ts`
POST   /api/v1/users/{id}/now_playing  <- `src/classes/Member.ts`
POST   /api/v1/users/{id}/presence_prompts  <- `src/classes/PresencePromptHistory.ts`
POST   /api/v1/users/{id}/socials  <- `src/commands/profile.command.ts`
POST   /api/v1/voting_info  <- `src/classes/BotVotingInfo.ts`
POST   /api/v1/{id}/{id}/nominations  <- `src/classes/Nomination.ts`
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
Write calls send `{ data: { <attributes> } }` and expect the same envelope shape back
that this API returns (`{ data: ... }`, `{ data: [...], meta: {...} }`, or
`{ deleted: true }`). Changing those envelopes here breaks the bot without a bot-side
release.

## Bot slash commands

Grouped by the bot source file that defines them.

### `src/commands/admin.command.ts`

```
/sync  # Synchronize application commands with Discord
/set-nextvote  # Votes are typically held the last Friday of the month
/delete-gotm-noms  # Interactive deletion of GOTM nominations for the upcoming round
/voting-setup  # Generate Subo /poll commands for GOTM and NR-GOTM voting
/delete-nr-gotm-noms  # Interactive deletion of NR-GOTM nominations for the upcoming round
/nextround-setup  # Interactive setup for the next round (GOTM, NR-GOTM, dates)
/add-gotm  # Add a new GOTM round
/add-nr-gotm  # Add a new NR-GOTM round
/edit-gotm  # Edit GOTM data by round
/edit-nr-gotm  # Edit NR-GOTM data by round
/help  # Show help for admin commands
```

### `src/commands/avatar-history.command.ts`

```
/avatar-history  # View a user's avatar history
```

### `src/commands/backlog/backlog-crud.command.ts`

```
/add  # Add a game to your backlog
/edit  # Edit one of your backlog entries
/remove  # Remove one of your backlog entries
```

### `src/commands/backlog/backlog-view.command.ts`

```
/list  # View your game backlog
```

### `src/commands/collection/collection-crud.command.ts`

```
/add  # Add a game you own to your collection
/edit  # Edit one of your collection entries
/remove  # Remove one of your collection entries
/to-now-playing  # Add a collection entry to your now-playing list
/to-completion  # Log a completion from a collection entry
```

### `src/commands/collection/collection-csv-import.command.ts`

```
/import-csv  # Import your collection from a custom CSV template
```

### `src/commands/collection/collection-steam-import.command.ts`

```
/import-steam  # Import your collection from Steam
```

### `src/commands/collection/collection-view.command.ts`

```
/list  # List your collection or another member collection
/overview  # Show a summary of your collection by platform
```

### `src/commands/create-thread.command.ts`

```
/create-thread  # Create a forum thread for a GameDB title
```

### `src/commands/game-completion.command.ts`

```
/add  # Add a game completion
/list  # List your completed games
/common  # Show shared completions between two members
/edit  # Edit one of your completion records
/delete  # Delete one of your completion records
/export  # Export your completions to a CSV file
/import-completionator  # Import completions from a Completionator CSV
```

### `src/commands/game-journal.command.ts`

```
/game-journal  # View Game Journal lists for yourself, a member, or everyone
```

### `src/commands/gamedb-admin.command.ts`

```
/link-versions  # Link alternate GameDB versions (Admin only)
/synonym-add  # Quick add one GameDB search synonym group (Admin only)
/synonym-list  # List GameDB search synonyms (Admin only)
```

### `src/commands/gamedb/gamedb-add.command.ts`

```
/add  # Add a new game to the database (searches IGDB)
/refresh-release-info  # Refresh release info from IGDB for a GameDB title
```

### `src/commands/gamedb/gamedb-search.command.ts`

```
/search  # Search for a game
```

### `src/commands/gamedb/gamedb-view.command.ts`

```
/view  # View details of a game
```

### `src/commands/generate-vote-image.command.ts`

```
/generate-vote-image  # Generate a combined vote image from round nominations
```

### `src/commands/giveaway.command.ts`

```
/list  # List available donated game keys
/donate  # Donate a game key to the giveaway pool
/revoke  # Revoke a donated game key
/gamegiveaway  # Go to the giveaway hub
```

### `src/commands/help.command.ts`

```
/help  # Show help for all bot commands
```

### `src/commands/mod.command.ts`

```
/presence  # Set Presence
/presence-history  # Show presence history
/help  # Show help for moderator commands
/create-live-event  # Create a Live Events thread and linked scheduled event from one modal
```

### `src/commands/mp-info.command.ts`

```
/mp-info  # Show members with multiplayer handles
```

### `src/commands/nominate.command.ts`

```
/nominate  # Nominate a GameDB title for GOTM or NR-GOTM
/noms  # Show the current GOTM or NR-GOTM nominations
```

### `src/commands/now-playing.command.ts`

```
/add  # Add a game to your now playing list
/list  # Show now playing data
/search  # Search for who is playing a GameDB title
```

### `src/commands/pokopia/pokopia-habitat.command.ts`

```
/habitat  # Browse Pokopia habitats
```

### `src/commands/pokopia/pokopia-pokemon.command.ts`

```
/pokedex  # Browse the Pokopia pokedex
```

### `src/commands/profile.command.ts`

```
/view  # Show a member profile
/search  # Search member profiles
/edit  # Edit profile links (self, or any user if admin)
```

### `src/commands/publicreminder.command.ts`

```
/create  # Create a public reminder
/list  # List upcoming public reminders
/delete  # Delete a public reminder
```

### `src/commands/round-history.command.ts`

```
/round-history  # Query historical GOTM/NR-GOTM rounds
```

### `src/commands/round.command.ts`

```
/round  # Show the current GOTM round and winners
```

### `src/commands/rss.command.ts`

```
/help  # Show help for RSS commands
/add  # Add an RSS feed relay
/remove  # Remove an RSS feed relay
/edit  # Edit an RSS feed relay
/list  # List RSS feed relays
```

### `src/commands/suggestion.command.ts`

```
/suggestion  # Submit a bot suggestion
```

### `src/commands/superadmin.command.ts`

```
/completion-add-other  # Add a game completion for another user
/say  # Have the bot send a message
/memberscan  # Scan guild members and upsert into RPG_CLUB_USERS
/download-missing-images  # Download images from IGDB for GameDB titles that have no API images yet
/help  # Show help for server owner commands
```

### `src/commands/thread-admin.command.ts`

```
/link  # Link a thread to a GameDB game id
/unlink  # Unlink a thread from a GameDB game id
```

### `src/commands/timestamp.command.ts`

```
/timestamp  # Generate a Discord timestamp from natural date/time input
```

### `src/commands/todo.command.ts`

```
/todo  # List GitHub issues
```

---

## Source references

- Bot repo: https://github.com/TheRPGClub/TheRPGClub-bot
- Bot README: `README.md`
- Bot API client: `src/services/RpgClubApiClient.ts`
- Bot commands: `src/commands/`, `src/events/`
- Bot-owned SQL (not yet migrated): `src/db/sql/`
