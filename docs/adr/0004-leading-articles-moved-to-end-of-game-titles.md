# Leading articles are moved to the end of GameDB titles

GameDB titles that start with The, A or An are stored with the article at the end ("The Last of Us" becomes "Last of Us, The"), so a plain alphabetical sort puts them under their first significant word. The title itself is rewritten, on every save and once for existing games by a data migration. We rejected a separate sort-title column so that there is one name to read, store and sort by. The cost is that the club sees "Last of Us, The" everywhere the title is shown.

## Consequences

- IGDB names arrive as "The X" and are rewritten on import and refresh. Refreshes look games up by IGDB id, so no reverse lookup is needed.
- Anything that compares GameDB titles with names written by people or other services has to ignore where the article sits. This covers game search, GOTM round search, import matching and import confidence.
- Anything that sends a title outside GameDB moves the article back to the front, for example the HowLongToBeat search.
- Titles copied into other tables (game keys, nomination and vote audit, presence prompts) keep whatever form they were written in.
