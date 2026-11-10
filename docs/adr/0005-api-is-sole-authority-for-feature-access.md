# The API is the sole authority on feature access

Whether a member can use a feature is decided only by the API: it holds each Feature Flag's state, decides who counts as an Admin or Superadmin, and refuses non-staff requests to a Preview or Off feature. The bot and the website ask the API rather than deciding for themselves. We rejected letting each client check flags and roles on its own because the bot and API already disagree on who a Superadmin is (the bot uses the guild owner, the API the dev role), and hiding features only in the clients would leave Preview features reachable through the API.

## Consequences

- For flag checks the bot defers to the API's staff definition, even though its other permission checks still read Discord directly; aligning those is separate work.
- The list of Features is defined in API code and only their states live in the database, so adding a Feature means an API release, and new Features start in Preview.
