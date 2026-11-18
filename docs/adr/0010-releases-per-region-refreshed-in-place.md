# Releases are kept per platform per region and refreshed from IGDB in place

GameDB used to keep one Release per platform (the earliest outside Japan, following bot#125), and refreshing a game from IGDB deleted its Releases and their announcements and inserted them again. The Release Calendar needs each region's date, Japan included, and a weekly IGDB refresh to keep upcoming dates from going stale. We now keep one IGDB Release per game, platform and region, with its Date Precision, and a refresh matches on game, platform and region to update, add or remove IGDB Releases in place. Manual Releases are never touched by a refresh. We rejected wipe-and-reinsert: a recreated Release loses its announcement state, so any refresh inside a game's 7-day announcement window posted the announcement a second time, and it also erased Manual Releases.

## Consequences

- The 7-day announcement still ignores Japan: a Japanese Release is announced only when the game has no Release outside Japan at any Date Precision, TBA included. A game with an exact Japanese day and only a vague or TBA western date waits for its western day. Japan-only games are still announced.
- A game is announced once. A refresh that removes an announced Release deletes its sent announcement too, so the game keeps the fact on `gamedb_games.release_announced_at`, and the due feed never offers another Release of that game.
- Existing Releases became Manual Releases, except the old importer's Worldwide rows (no format, no notes, game with an IGDB id), which became IGDB Releases so a refresh replaces them with IGDB's regional ones. A refresh adopts a Manual Release when IGDB reports the same game, platform and region, and the rest stay Manual until staff remove them.
- Only games with an upcoming, imprecise or missing date are refreshed. Past Releases keep their pre-change data: no Japan and no Date Precision.
