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

**Pinned Page**:
A page of the website that a Member has put at the top of their own sidebar so it is one click away. A Pinned Page is still listed in its usual place. Members who have pinned nothing see the club's default Pinned Pages, and a Pinned Page that the Member cannot currently see stays pinned and returns when they can.
_Avoid_: Favourite, shortcut, bookmark

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

**Release**:
A GameDB game coming out on one platform in one region. Its date is known to a Date Precision.
_Avoid_: Launch, release date (when meaning the whole record)

**Date Precision**:
How exactly a Release's date is known: an exact day, a month, a quarter, a year, or not yet announced (TBA).
_Avoid_: Date format, accuracy

**IGDB Release**:
A Release that comes from IGDB. Refreshing the game from IGDB keeps it in step: its date can move, and it can be removed.
_Avoid_: Auto release, imported release

**Manual Release**:
A Release added by staff or by an import from another source. Refreshing from IGDB never changes or removes it.
_Avoid_: Custom release, user release

**Release Calendar**:
The members' view of GameDB Releases ordered by date, upcoming by default, with past months available to browse. Only games in GameDB appear on it.
_Avoid_: Release schedule, upcoming games, launch calendar, calendar (unqualified: Challenges have their own)

**Upcoming Release**:
One entry on the Release Calendar: one game together with every Release it has on the same date, across platforms and regions.
_Avoid_: Calendar entry, event

## Community

**Suggestion**:
A member's proposal for the club's bot or website. Pending until staff approve it (it becomes a GitHub issue) or reject it with a reason, or until its author withdraws it.
_Avoid_: Request, idea, ticket

**Suggestion Board**:
The members-only list of Suggestions, ranked by member upvotes.
_Avoid_: Roadmap, feedback board

## Members

**Birth Date**:
The date of birth a member enters on their own profile, if they choose to. The year is optional: a Birth Date without one is a Birthday alone, and counts as having no birth year. Only the member and staff see the full date. Other members see the day and month only as a Birthday the member chose to share, and the year only through a Run that starts at the member's birth year, which the member is told before starting it. A member can set or change it at most twice in a calendar month, counting the first time they enter it; staff can change it at any time.
_Avoid_: Birthday (when meaning the full date), age, DOB

**Regular**:
A member holding the club's regulars role in Discord, trusted to add to the club's shared records without staff review.
_Avoid_: Veteran, trusted member

**Birthday**:
The day and month of a member's Birth Date. The club celebrates it only if the member chooses to share it; until then nobody but the member and staff sees it. Sharing never reveals the year or the member's age. Birthdays are a utility, not a Feature: the only way to switch one off is for its member to stop sharing it.
_Avoid_: Birth Date (when meaning only the day and month), anniversary, cake day

**Club day**:
A calendar day in the club's time zone, America/New_York. Challenge dates, the Birth Date change limit and Birthdays all count in club days, so a day starts and ends at midnight New York time whatever the member's own time zone.
_Avoid_: Server day, UTC day

**Birthday Post**:
The bot's one message on a club day that greets every member whose shared Birthday it is. A member gets at most one Birthday Post a calendar year, however their Birth Date changes; a 29 February Birthday is celebrated on 28 February in other years.
_Avoid_: Birthday reminder, birthday announcement

**Upcoming Birthdays**:
The shared Birthdays falling in the next 30 days, as members see them on the website and through the bot.
_Avoid_: Birthday calendar, birthday list

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

## Club Codex

**Club Codex**:
The Feature that keeps the club's story about itself, in three parts: Club History, Club Lore and Fun Facts.
_Avoid_: Club Lore (when meaning the whole Feature), wiki, archive

**Club History**:
The club's official record of how it got to where it is, told as History Events in date order.
_Avoid_: Timeline (when meaning the record itself), changelog

**History Event**:
A dated moment that changed the club, such as its founding, a member joining or leaving the staff, a move to another platform, or a rule change. Its date can be a year alone, a month and year, or a full date, as precisely as the club remembers it, and it has one History Event Kind. Staff write every History Event by hand; role changes never create one. History Events are factual, only Admins and Superadmins write them, and any of them can edit or remove any History Event.
_Avoid_: Event (unqualified), entry (unqualified)

**History Event Kind**:
One of the fixed sorts of History Event: Founding, Staff, Platform, Rules or Milestone.
_Avoid_: Category, type, tag

**Club Lore**:
The stories the club tells about itself, kept as Lore Entries.
_Avoid_: Legends, tales

**Lore Entry**:
A story about the club, usually funny and several paragraphs long, which may be tied to a date. Regulars and above publish Lore Entries straight away without staff review, and each one credits its author.
_Avoid_: Story, post, anecdote

**Fun Fact**:
One or two standalone sentences about the club or its members, such as a member's original nickname or the origin of an inside joke, which the bot posts for members to read. Regulars and above publish Fun Facts straight away without staff review, and each one credits its author. The bot shows every Fun Fact once before showing any again, and a new Fun Fact jumps the queue.
_Avoid_: Trivia, tidbit, did-you-know

**Daily Fun Fact**:
The bot's post of the next Fun Fact in general chat at 15:00 America/New_York every day. A member can also ask the bot for a Fun Fact at any time; it comes from the same queue, is posted for everyone to see, and never replaces the Daily Fun Fact.
_Avoid_: Fact of the day, daily trivia

The same moment can appear in more than one part of the Club Codex, such as a History Event recording that something happened and a Lore Entry telling the story, and any Club Codex entry can link to any others, the link showing on both. Members named in Club Codex entries are not asked for their consent and have no special say over them. An author can edit or delete their own Lore Entries and Fun Facts, and Moderators and above can edit or remove anyone's. Club History is public; Club Lore and Fun Facts are for Members only.
