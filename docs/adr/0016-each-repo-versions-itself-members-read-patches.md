# Each repo versions itself on every merge; members read numbered Patches instead

The backend, bot and website each deploy on every merge to main, so a version has to be cut at the same moment or it means nothing. We decided that each repo bumps its own semantic version on every merge, from the merged pull request's typed title: `feat` bumps the minor number, `fix` and `perf` bump the patch number, a `!` or a `BREAKING CHANGE` line bumps the major number, and every other type bumps nothing. The merge is then tagged and gets a GitHub Release. We rejected one club-wide version stamped when a Patch is published, because a Patch gathers many deploys across three repos and tagging at publish time would label code that shipped days earlier. We rejected publishing the GitHub Releases as the Patch Notes, because they are written per pull request for developers. One feature usually lands as three pull requests, and members need one line in plain words. Members therefore see a separate, simple Patch number. Each repo version shows only in small print: the website footer, the bot's `/patch-notes` reply, and on a Patch.

## Consequences

- Every pull request title must be typed. A required check refuses untyped titles, and each repo's CLAUDE.md states the rule.
- We merge with merge commits, so the version job reads the merged pull request's title through GitHub rather than the commit message.
- Every version bump becomes a Pending Change in the backend. Staff turn Pending Changes into Patch lines or dismiss them, and collection carries on while Patch Notes is Off.
- Versioning starts when the owner tags each repo's first version (1.0.0 for the backend and website, the bot's current version for the bot) and turns the job on; nothing is versioned before that.
- The backend keeps each repo's current version, written by the version job, because the website and bot deploy from the merge commit and cannot know a tag made after it. The website footer and the bot read versions from the backend; package.json versions are not used.
- The job reaches the backend with its own narrow token that can only record Pending Changes, never the bot's service token.
- A major version is a deliberate statement that something others rely on broke (an API field, a slash command, a public URL). The job never infers one.
