# News is posted in one channel; the bot copies it into category threads

Supersedes [ADR 0006](0006-news-category-comes-from-the-thread.md) (a News Item's category comes from the thread it was posted in).

The News Hub launched with members posting straight into one forum thread per News Category. Members told us it was a regression: keeping up meant clicking through seven threads, where before a glance at one channel was enough, and some said they would mute it. Members now post in a single News Channel again, the bot picks each item's News Category with free keyphrase rules and posts a News Copy into that category's thread, and the threads are bot-only, so members who want one kind of news follow its thread. We rejected a paid model for classification: rules got about 79% of a year of real posts right against 60% for always guessing the biggest category, and the poster or staff correct the rest with a message command. We kept one category per item, rejecting several, so a News Copy has exactly one home.

## Consequences

- About one post in five lands in the wrong thread until someone corrects it; a corrected item's News Copy moves, out of date order in its new thread.
- The bot now posts in Discord on members' behalf, so edits and deletes of the original must reach the News Copy, and an outage leaves threads behind until catch-up.
- The 10,191 archive items were copied into the threads by a slow, resumable staff job; threads are only in date order because live posts wait for it.
- Discussion lives in threads on the original message, as before the News Hub; the per-category discussion threads were deleted.
