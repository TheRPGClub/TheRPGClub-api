# The RPG Club

The club's backend: members, their games, club voting, and the Achievement Hub that mirrors members' achievements from external platforms.

## Membership

**Member**:
A person in the club's Discord server who has signed in to the website. Only Members can see the members' area of the website.
_Avoid_: User, account

**Visitor**:
Anyone on the website who is not a Member: someone not signed in, or someone signed in with Discord who is not in the club's Discord server. Visitors see the public front page and are invited to join the server.
_Avoid_: Guest, non-member, anonymous user

**Theme**:
The look a Member chooses for the website, from colours and type to the shape of every control; the site's pages and what they do stay the same in every Theme. Visitors, and Members who have not chosen, see the club's default Theme.
_Avoid_: Skin, style, dark mode, appearance

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
_Avoid_: 100%, finish, Game Completion (a different thing)

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

## Games

**Game Completion**:
A member's record that they finished a game, with how thoroughly (main story, main story plus side content, or completionist) and when. Distinct from an Achievement Hub Completion.
_Avoid_: Completion (unqualified), beat, finish

## Community

**Suggestion**:
A member's proposal for the club's bot or website. Pending until staff approve it (it becomes a GitHub issue) or reject it with a reason, or until its author withdraws it.
_Avoid_: Request, idea, ticket

**Suggestion Board**:
The members-only list of Suggestions, ranked by member upvotes.
_Avoid_: Roadmap, feedback board

## Members

**Birth Date**:
The date of birth a member enters on their own profile, if they choose to. Only the member and staff see the full date. Other members see the year only through a Run that starts at the member's birth year, which the member is told before starting it. A member can set or change it at most twice in a calendar month, counting the first time they enter it; staff can change it at any time.
_Avoid_: Birthday (when meaning the full date), age, DOB

## Staff

**Admin**:
A member holding the club's admins role in Discord.
_Avoid_: Administrator (the Discord permission), owner

**Moderator**:
A member holding the club's moderators role in Discord.
_Avoid_: Mod (in written docs), staff (when meaning only moderators)

**Superadmin**:
A member holding the club's dev role, trusted with actions that speak for the bot or change other members' records.
_Avoid_: Owner, root, dev (when meaning the permission level rather than the role)

## Features

**Feature**:
A part of the club's bot and website that staff turn on and off as one unit, covering its pages, commands and automated posts wherever they appear. Utilities such as the dashboard, profiles and staff tools are not Features.
_Avoid_: Module, section, area

**Core Feature**:
A Feature members cannot hide with a Feature Preference because the club depends on it: the game index, voting and GOTM, and each member's backlog, collection, now playing and completions.
_Avoid_: Required feature, default feature

**Feature Flag**:
The staff setting that decides who can use a part of the club's bot and website. It is always in one of three states: Off, Preview or Live. Only Admins and Superadmins can change it.
_Avoid_: Toggle, switch, setting, flag (when meaning a Feature Preference)

**Off**:
The Feature Flag state in which nobody can use the feature, staff included, and its automated activity is paused.
_Avoid_: Disabled, killed

**Preview**:
The Feature Flag state in which only Admins and Superadmins can use the feature, and anything it would post publicly goes to a staff test channel instead.
_Avoid_: Beta, staff-only, hidden

**Live**:
The Feature Flag state in which every member can use the feature.
_Avoid_: Public, enabled, on

**Feature Preference**:
A member's choice to hide a Live Feature that is not a Core Feature from their own view of the website. It removes the Feature everywhere it appears for them, including its sections inside other pages, but never blocks a direct link to it, and it can never make visible a Feature that its Feature Flag hides.
_Avoid_: Feature flag, setting, opt-out

## News Hub

**News Hub**:
The Feature that gathers the game news members post in Discord into one place on the website, where members filter it by News Category.
_Avoid_: News feed, news page, game news (when meaning the Feature)

**News Channel**:
The single Discord channel where members share game news, and where discussion of a piece of news happens in a thread on the member's message.
_Avoid_: Game news channel, main channel, feed, Game News Archive (retired: the News Channel is the same channel, reopened)

**News Item**:
A message a member posted in the News Channel that carries a link, an image, or both, or one the bot posted there for a member who shared news through the bot. A member's text alongside it is their comment on the news. Messages with text only, and messages a bot posts on its own account, are never News Items.
_Avoid_: Article, post, story, news (as a countable noun)

**News Category**:
One of the fixed kinds of news the club sorts News Items into. Every News Item belongs to exactly one News Category, which the bot picks when the item is posted (or staff assigned during the News Import) and which can be corrected afterwards.
_Avoid_: Tag, topic, thread (when meaning the kind of news)

**News Copy**:
The bot's copy of a News Item in the thread of the item's News Category. It links back to the News Item, where discussion happens, and follows it when the item is edited, deleted or moved to another category. A News Copy is never a News Item.
_Avoid_: Repost, mirror, crosspost

**News Category Preference**:
A member's choice to leave a News Category out of their own default view of the News Hub. It affects only the website, and never stops the member from viewing that category when they ask for it.
_Avoid_: Mute, unfollow, filter (when meaning the saved choice)

**News Import**:
The one-time move of the messages posted in the News Channel before the News Hub launched into the News Hub as News Items, each keeping its original author and date. An imported News Item stays hidden until staff assign its News Category.
_Avoid_: Backfill (that is the Achievement Hub's term), migration, re-post

## Challenges

**Challenge**:
A themed goal a member sets for the club, such as playing a game from every year they have been alive or playing Final Fantasy games through the autumn. Other members take part by starting a Run. Every Challenge has exactly one Challenge Format.
_Avoid_: Event, quest, marathon

**Host**:
The member who runs a Challenge, or the club itself for a Challenge staff run in the club's name. Only Regulars, Moderators, Admins and Superadmins can create a Challenge. A Challenge keeps its Host if the Host later loses the role or leaves, and staff can hand it to another Host.
_Avoid_: Owner, organiser, creator

**Run**:
One member's attempt at a Challenge, with its own progress. It is shown on the Challenge's page and on the member's profile.
_Avoid_: Entry, attempt, participation

**In Progress**:
A game that counts toward a Run because it is in the member's Now Playing. It shows the member is playing it but never fills a slot or finishes an Assignment.
_Avoid_: Started, active

**Cleared**:
A game that counts toward a Run because the member logged a Game Completion for it. Only Cleared games fill slots and finish Assignments.
_Avoid_: Done, beaten, completed (that is the Game Completion itself)

**Finished**:
A Run that reached its Challenge's goal: every slot of a fixed range Cleared, the Pool's target Cleared, or the assigned game Cleared. A member may Finish the same Challenge again in a later Run.
_Avoid_: Completed, won, done

**Expired**:
A Run that was not Finished before its Season or Edition ended. It stays on the member's profile.
_Avoid_: Failed, lapsed, timed out

**Caught Up**:
A Run of a Challenge that gains a slot every year, such as Years Alive, in which every slot up to the current year is Cleared. It stops being Caught Up when the next year's slot opens.
_Avoid_: Finished, complete (for a Run that keeps growing)

**Abandoned**:
A Run its member chose to leave. It stays on the member's profile unless they delete it.
_Avoid_: Failed, quit, cancelled

**Always Open**:
A Challenge members can start a Run of at any time, until its end date if the Host set one.
_Avoid_: Permanent, evergreen, ongoing

**Season**:
The dates, repeating every year, during which a Seasonal Challenge is Open, such as 21 June to 22 September. A Run of a Seasonal Challenge starts and ends within one Season, and only play during it counts.
_Avoid_: Window, period, edition

**Seasonal**:
A Challenge that is Open only during its Season and Closed the rest of the year. Members take part in whichever year they like, and may take part again in later years.
_Avoid_: Yearly, annual, recurring

**Edition**:
One cycle of an Assignment Challenge: members sign up, are drawn into pairs, are assigned a game and then have until the Edition ends to Clear it.
_Avoid_: Round (that is voting), season, instance

**Challenge Format**:
The way a Challenge decides which games count: Slots, Pool or Assignment.
_Avoid_: Type, kind, mode

**Slots**:
The Challenge Format where a Run has one place to fill for each year in a range, such as every year from the member's birth year to now. A game can fill the slot of any year it was released in, anywhere, but only one slot in a Run. A range that ends at the current year gains a slot each new year.
_Avoid_: Checklist, grid

**Pool**:
The Challenge Format where any game from a set the Host chose counts, such as the Final Fantasy series. The Host sets how many must be Cleared to Finish, a number or every game in the set, and a member may keep playing beyond it.
_Avoid_: Series challenge, list

**Assignment**:
The Challenge Format where another member chooses the game a member must play, such as a Secret Santa pick from their backlog.
_Avoid_: Gift, pick (when meaning the format)
