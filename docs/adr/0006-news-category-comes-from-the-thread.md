# A News Item's category comes from the thread it was posted in

Superseded by [ADR 0007](0007-news-posted-in-one-channel-copied-into-category-threads.md): members post news in one channel again and the bot copies it into the category threads.

The game news forum in Discord holds one permanent thread per News Category, and a News Item is a message inside one of those threads, so every News Item has exactly one News Category from a short fixed list. We rejected the shape Discord's forum tags were built for, one forum post per news item carrying several tags, because posting news had to stay as quick as dropping a link, and because per-thread follow and mute give members per-category notifications in Discord for free. Making every news item a forum post would have required a title for each one and turned the forum into thousands of posts.

## Consequences

- A News Item cannot belong to two News Categories. News that fits several goes where the poster judges best.
- A forum thread cannot contain threads, so discussion of a single News Item has no home of its own. Each News Category has a companion discussion thread instead, which the News Hub ignores.
- News Categories are defined in API code and each one needs a Discord thread whose ID the bot is configured with, so adding or renaming one is a release plus a manual step in Discord.
- Discord forum tags play no part in the software; they are set by hand for members browsing in Discord.
