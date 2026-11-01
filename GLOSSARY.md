# The RPG Club

The club's backend: members, their games, club voting, and the Achievement Hub that mirrors members' achievements from external platforms.

## Achievement Hub

**Provider**:
An external platform that awards achievements: RetroAchievements, Steam or PlayStation Network.
_Avoid_: Service, platform, source

**Linked Account**:
A member's identity on one Provider, claimed by the member and used to sync their achievements. At most one member may claim a given Provider identity.
_Avoid_: Social, connection, integration

**Achievement**:
A single goal defined by a Provider for a game, shared by every member. PSN trophies are Achievements whose tier is bronze, silver, gold or platinum.
_Avoid_: Trophy (except when naming a PSN tier), badge, cheevo

**Achievement Set**:
The full list of Achievements a Provider defines for one title. A game may have several Achievement Sets (e.g. separate PS4 and PS5 lists).
_Avoid_: Trophy list, game (when meaning the Provider's list)

**Unlock**:
The fact that a member earned an Achievement, and when. RetroAchievements Unlocks are either hardcore or softcore.
_Avoid_: Earn, award, achievement (when meaning the member's earning of it)

**Rarity**:
The share of a Provider's players who have unlocked an Achievement, as reported by that Provider.
_Avoid_: Earn rate, percentage

**Completion**:
A member having unlocked every Achievement in an Achievement Set.
_Avoid_: 100%, finish

**Mastery**:
A RetroAchievements Completion where every Unlock is hardcore.
_Avoid_: Hardcore completion

**Platinum**:
The PSN Achievement awarded for unlocking all others in its set; a highlight on its own.

**Highlight**:
An Unlock worth announcing: a Platinum, the Unlock that produces a Completion or Mastery, or any Unlock rarer than 5%.
_Avoid_: Milestone, notable

**Backfill**:
The first, full import of a newly Linked Account's played history. Backfilled Unlocks are never announced.
_Avoid_: Initial sync, full import

**Sync Window**:
A scheduled period in which every Linked Account is checked for new Unlocks, after which the hub stays idle.
_Avoid_: Refresh, poll
