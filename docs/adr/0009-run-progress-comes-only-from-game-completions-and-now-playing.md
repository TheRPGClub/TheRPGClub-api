# Run progress comes only from Game Completions and Now Playing

A Challenge's Runs fill in their progress from what members already record: a game in Now Playing is In Progress, and a Game Completion makes it Cleared. Members never mark Challenge progress themselves, and Hosts never approve it. We chose this over self-reporting, which is what the club did by hand before, and over approval by the Host. Using records the club already keeps gives every Challenge an answer to "did they do it?" that nobody has to check, makes imports count without extra work, and means a member logs a game once rather than once per Challenge. The cost is that a member who forgets to log a Game Completion gets no progress, and a Challenge can only count what the game lists record. A future "tick it off" button would undo that guarantee and need its own trust rules.

## Considered Options

- Self-reported progress: the member ticks off games on the Run. Rejected because nobody would check it, and the club already has the data.
- Host approval: the member claims a game and the Host confirms it. Rejected because it makes every Host a bottleneck and brings back the manual tracking this Feature replaces.
- Game Completions and Now Playing only (chosen).

## Consequences

- Progress has to be recalculated whenever a Game Completion or Now Playing entry changes, from any source: the bot, the website or an import.
- The Years Alive spreadsheet import creates missing Game Completions rather than writing Run progress directly.
