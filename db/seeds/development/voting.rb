# frozen_string_literal: true

# GOTM / Non-RPG GOTM voting data for local development (#40, #97, #172, #173).
#
# The endpoints under gotm_entries/:round and nr_gotm_entries/:round are all
# gated on round state — Voting::CastVote needs an open window, VotesController
# hides voter identities until BotVotingInfo#voting_ended?, and
# NominationsController lets a member write only while
# BotVotingInfo.nominations_open_for? — so seeding a single winner row leaves
# every one of those paths unreachable. This builds three rounds instead: two
# finished ones (nominations + ballots + winners) and a current one.
#
# Nominations and voting are mutually exclusive by design — nominations collect
# for the round after the current one and close the moment the current round's
# vote opens — so the current round can only sit in one of them:
#
#   SEED_VOTING_PHASE=voting      (default) round 3's window is open now: cast
#                                 votes, read the anonymous tally, watch the
#                                 cap evict your oldest vote. Round 4
#                                 nominations are closed.
#   SEED_VOTING_PHASE=nominating  round 3's vote opens in five days, so round 4
#                                 nominations are open to members and round 3
#                                 has no ballots yet.
phase = ENV.fetch("SEED_VOTING_PHASE", "voting")
unless %w[voting nominating].include?(phase)
  raise ArgumentError, %(SEED_VOTING_PHASE must be "voting" or "nominating", got #{phase.inspect})
end

puts "Seeding GOTM voting data (SEED_VOTING_PHASE=#{phase})..."

# Restricted to the accounts development.rb seeds (the 1000000000000000xx id
# block) and the games it seeds (negative igdb ids) rather than everything with
# the member role — a local database may also hold real Discord accounts pulled
# in by the bot, and they have no business nominating or voting here.
members = RpgClubUser.where("user_id LIKE '1000000000000000__'").order(:user_id).index_by(&:username)
catalog = GamedbGame.where("igdb_id < 0").index_by(&:slug)

# The bot schedules votes on a Friday; anchoring the finished rounds on real
# Fridays keeps BotVotingInfo#vote_deadline's default Friday -> Sunday rule
# meaningful for round 1, which deliberately leaves vote_ends_at NULL.
friday_before = lambda do |time|
  local = time.in_time_zone(BotVotingInfo::VOTING_TIME_ZONE)
  (local.beginning_of_day - ((local.wday - 5) % 7).days) + 18.hours
end

round_one_opens = friday_before.call(75.days.ago)
round_two_opens = friday_before.call(45.days.ago)
current_opens = phase == "voting" ? 2.days.ago : 5.days.from_now

rounds = {
  # vote_ends_at NULL -> the deadline falls out of the default Sunday rule.
  1 => { opens: round_one_opens, ends: nil, finished: true },
  # An explicit override, the shape used when a round's voting is extended.
  2 => { opens: round_two_opens, ends: round_two_opens + 3.days, finished: true },
  3 => { opens: current_opens, ends: current_opens + 6.days, finished: false }
}
current_round = 3

# Re-seeding into the other phase: drop the rows the incoming phase says should
# not exist yet, so flipping SEED_VOTING_PHASE never leaves ballots on a round
# whose window has not opened (or nominations for a round that is not
# collecting).
if phase == "nominating"
  [ GotmVote, NrGotmVote ].each { |model| model.where(round_number: current_round).delete_all }
else
  [ GotmNomination, NrGotmNomination ].each { |model| model.where(round_number: current_round + 1).delete_all }
end

rounds.each do |round_number, window|
  info = BotVotingInfo.find_or_initialize_by(round_number: round_number)
  info.update!(
    next_vote_at: window.fetch(:opens),
    vote_ends_at: window.fetch(:ends),
    nomination_list_id: 1_400_000_000_000_000_000 + round_number,
    five_day_reminder_sent: window.fetch(:finished) || phase == "voting",
    one_day_reminder_sent: window.fetch(:finished) || phase == "voting"
  )
end

# [nominator username, game slug, reason]. A round holds at most one nomination
# per user, and the per-user vote cap keys off the size of the field: rounds 2
# and 3 clear Voting::CastVote::LARGE_FIELD_THRESHOLD (9) for a cap of 3, while
# rounds 1 and 4 stay under it for a cap of 2.
#
# These are written one row per member up to the worst case, not to the size
# the round ends up with: seed_nominations drops rows for games that won an
# earlier round, so a field has to survive losing every prior winner it lists
# and still clear the threshold. GOTM round 2 can lose round 1's single winner
# (10 rows -> 9) and round 3 can lose all three from rounds 1 and 2 (12 -> 9).
# Every game inside a round is listed at most once, which is what caps the
# damage at one row per prior winner. The assertions at the bottom hold the
# arithmetic to it.
gotm_nominations = {
  1 => [
    [ "dev_admin",      "emberlight-chronicles", "Second act is worth arguing about." ],
    [ "party_member",   "iron-covenant",         "Permadeath makes every recruit matter." ],
    [ "tavern_keeper",  "hollow-vanguard",       "Someone has to keep nominating it." ],
    [ "dice_goblin",    "moonlit-tactics",       "Short enough to finish inside a month." ],
    [ "loot_hoarder",   "nine-lives-of-rhea",    "Nine runs, nine completely different games." ]
  ],
  2 => [
    [ "dev_admin",      "ashes-of-asteria",   "The party banter alone carries it." ],
    [ "party_member",   "verdant-hollow",     "Highest rated thing nobody here has played." ],
    [ "tavern_keeper",  "starfall-wardens",   "Six crew members, six endings." ],
    [ "dice_goblin",    "grimoire-of-tides",  "Weather-based spellcasting is genuinely novel." ],
    [ "loot_hoarder",   "the-sunken-archive", "Cataloguing a drowned library. Trust me." ],
    [ "crit_fisher",    "clockwork-kingdom",  "On sale everywhere right now." ],
    [ "save_scummer",   "iron-covenant",      "Losing my whole roster built character." ],
    [ "lore_reader",    "emberlight-chronicles", "Re-nominating until it wins." ],
    [ "speedrunner",    "nine-lives-of-rhea", "Any% is under two hours." ],
    [ "backlog_slayer", "hollow-vanguard",    "It is going to keep showing up until you play it." ]
  ],
  3 => [
    [ "dev_admin",      "saltmarsh-requiem",     "Best reviewed RPG of the year." ],
    [ "party_member",   "verdant-hollow",        "Missed it last round, trying again." ],
    [ "tavern_keeper",  "the-sunken-archive",    "Perfect for a slow reading month." ],
    [ "dice_goblin",    "hollow-vanguard",       "Third time is the charm." ],
    [ "loot_hoarder",   "grimoire-of-tides",     "Deep enough to fill a whole month." ],
    [ "crit_fisher",    "starfall-wardens",      "Crew management is the real combat system." ],
    [ "save_scummer",   "moonlit-tactics",       "Short, cheap, on every platform." ],
    [ "lore_reader",    "emberlight-chronicles", "I will not be stopped." ],
    [ "speedrunner",    "nine-lives-of-rhea",    "Replayable without being a slog." ],
    [ "backlog_slayer", "clockwork-kingdom",     "It has been in my backlog for two years." ],
    [ "night_owl",      "iron-covenant",         "Losing the roster is the point." ],
    # gotm_nominations.gamedb_game_id is nullable (unlike the NR-GOTM table), so
    # a game-less row is legal here — this is what makes CastVote raise
    # NominationMissingGameError and return 422 nomination_missing_game.
    [ "couch_coop",     nil,                     "Placeholder, still deciding." ]
  ],
  4 => [
    [ "dev_admin",     "iron-covenant",      "Fresh field, same taste." ],
    [ "party_member",  "ashes-of-asteria",   "Replay value for a second run." ],
    [ "tavern_keeper", "saltmarsh-requiem",  "Did not win last round, deserves another shot." ],
    [ "dice_goblin",   "the-sunken-archive", "Everyone said they wanted it eventually." ],
    [ "loot_hoarder",  "verdant-hollow",     "Still the best thing none of us has finished." ],
    [ "crit_fisher",   "moonlit-tactics",    "Something short, for once." ]
  ]
}

nr_gotm_nominations = {
  1 => [
    [ "dev_admin",     "harbourline",     "Nothing but boats and spreadsheets." ],
    [ "party_member",  "tessera",         "The endgame is a hundred hours deep." ],
    [ "tavern_keeper", "static-bloom",    "Bad reviews, great runs." ],
    [ "dice_goblin",   "neon-drift-rally", "We need something short this month." ]
  ],
  2 => [
    [ "dev_admin",     "bolt-and-bramble",   "Best co-op platformer in years." ],
    [ "party_member",  "paperfold-pilgrims", "Wordless and still moving." ],
    [ "tavern_keeper", "deep-signal",        "No HUD, all sonar, total panic." ],
    [ "dice_goblin",   "harbourline",        "Comfort pick, re-nominated." ],
    [ "loot_hoarder",  "tessera",            "Still the best puzzler we have." ]
  ],
  3 => [
    [ "dev_admin",     "paperfold-pilgrims", "Short enough to fit around the GOTM." ],
    [ "party_member",  "bolt-and-bramble",   "Grab a friend for this one." ],
    [ "tavern_keeper", "neon-drift-rally",   "Twenty minutes a night, tops." ],
    [ "dice_goblin",   "deep-signal",        "Play it with headphones off the lights." ],
    [ "loot_hoarder",  "tessera",            "Third time nominating, no regrets." ],
    [ "crit_fisher",   "static-bloom",       "The runs get good after hour three." ]
  ],
  4 => [
    [ "dev_admin",     "harbourline",      "Ports. Again." ],
    [ "party_member",  "static-bloom",     "Giving it one more chance." ],
    [ "tavern_keeper", "neon-drift-rally", "Twenty minutes a night still holds." ],
    [ "dice_goblin",   "deep-signal",      "Headphones on, lights off, second attempt." ]
  ]
}

# Round 4 only exists while nominations are collecting for it.
unless phase == "nominating"
  gotm_nominations.delete(4)
  nr_gotm_nominations.delete(4)
end

member_ids = members.values.map(&:user_id)

seed_nominations = lambda do |model, vote_model, round_number, rows, opens, won_game_ids|
  # A game that has already won a round is out of the running for the rounds
  # after it, so drop those rows rather than editing the lists above: winners
  # fall out of the seeded RNG in seed_votes, so hand-curating a field to dodge
  # one only moves the problem to whoever wins in its place.
  eligible = rows.reject { |(_username, slug, _reason)| slug && won_game_ids.include?(catalog.fetch(slug).game_id) }
  kept_ids = eligible.map { |(username, _slug, _reason)| members.fetch(username).user_id }

  # find_or_initialize_by only ever creates, so leaving a member out of the
  # round does not remove the row a previous run wrote for them — a field
  # seeded before this filter existed would keep its repeat winner. Delete what
  # the round no longer lists, ballots included: the tables carry no foreign
  # key, so an orphaned vote would go on counting in the round's tally.
  stale = model.where(round_number: round_number, user_id: member_ids - kept_ids)
  vote_model.where(round_number: round_number, nomination_id: stale.select(:nomination_id)).delete_all
  stale.delete_all

  # Nominations are collected before the round's vote opens; for a round whose
  # window is still ahead they were collected before now.
  closes_at = [ opens, Time.current ].min
  eligible.each_with_index.map do |(username, slug, reason), index|
    record = model.find_or_initialize_by(round_number: round_number, user_id: members.fetch(username).user_id)
    record.gamedb_game_id = slug && catalog.fetch(slug).game_id
    record.reason = reason
    record.nominated_at = closes_at - (eligible.size - index).days
    record.save!
    record
  end
end

# Ballots are pseudo-random but seeded off the round, so re-running the seeds
# reproduces exactly the same tally rather than piling on new votes.
seed_votes = lambda do |vote_model, nomination_model, round_number, nominations, voters, opens|
  cap = Voting::CastVote.cap_for(nomination_model, round_number)
  votable = nominations.select { |nomination| nomination.gamedb_game_id.present? }
  rng = Random.new((round_number * 100) + vote_model.table_name.length)

  # Clear the seeded accounts' ballots for the round before recasting them. The
  # draw below depends on the size and order of the field, so a re-seed after
  # any change to it lands on different games and would otherwise pile new
  # votes on top of the old ones — enough, as it turns out, to hand the round
  # to a game that did not win on a clean database. Real Discord accounts are
  # left alone, as everywhere else in this file.
  vote_model.where(round_number: round_number, user_id: member_ids).delete_all

  voters.each_with_index.sum do |voter, index|
    votable.sample(1 + rng.rand(cap), random: rng).each_with_index do |nomination, offset|
      vote = vote_model.find_or_initialize_by(
        round_number: round_number,
        user_id: voter.user_id,
        gamedb_game_id: nomination.gamedb_game_id
      )
      vote.nomination_id = nomination.nomination_id
      vote.voted_at = opens + (index * 90).minutes + (offset * 5).minutes
      vote.save!
    end.size
  end
end

# The winners: the top `slots` nominations by vote count, ties broken by
# nomination order, mirroring how the bot announces a finished round.
seed_entries = lambda do |entry_model, vote_model, round_number, nominations, opens, slots|
  counts = vote_model.where(round_number: round_number).group(:nomination_id).count
  ranked = nominations
    .select { |nomination| nomination.gamedb_game_id.present? }
    .sort_by { |nomination| [ -counts.fetch(nomination.nomination_id, 0), nomination.nomination_id ] }

  ranked.first(slots).each_with_index.map do |nomination, index|
    entry = entry_model.find_or_initialize_by(round_number: round_number, game_index: index + 1)
    entry.update!(
      gamedb_game_id: nomination.gamedb_game_id,
      month_year: (opens + 1.month).strftime("%B %Y"),
      reddit_url: "https://old.reddit.com/r/therpgclub/comments/seed#{round_number}#{index + 1}",
      voting_results_message_id: format("15%016d", (round_number * 10) + index + 1)
    )
    entry.gamedb_game_id
  end
end

voters = members.values

# Ascending order is what makes the "no repeat winners" filter work at all:
# round N's winners are recorded before round N + 1's field is written, so the
# set below is always complete for the round being seeded.
seed_category = lambda do |nomination_model, vote_model, entry_model, fields, slots_for|
  won_game_ids = Set.new

  fields.sort.each do |round_number, rows|
    window = rounds[round_number]
    # The trailing round (nominating phase) has no scheduled vote yet —
    # nominations only, and no winner to record.
    if window.nil?
      seed_nominations.call(nomination_model, vote_model, round_number, rows, Time.current, won_game_ids)
      next
    end

    nominations = seed_nominations.call(
      nomination_model, vote_model, round_number, rows, window.fetch(:opens), won_game_ids
    )
    next unless window.fetch(:finished) || phase == "voting"

    # The current round leaves the last two members without a ballot, so a dev
    # logging in as one of them still has the full cap to spend.
    round_voters = window.fetch(:finished) ? voters : voters.first(voters.size - 2)
    seed_votes.call(vote_model, nomination_model, round_number, nominations, round_voters, window.fetch(:opens))
    next unless window.fetch(:finished)

    won_game_ids.merge(
      seed_entries.call(
        entry_model, vote_model, round_number, nominations, window.fetch(:opens), slots_for.call(round_number)
      )
    )
  end
end

# Round 2 records two GOTM winners; the club ran a tie that month.
seed_category.call(GotmNomination, GotmVote, GotmEntry, gotm_nominations, ->(round) { round == 2 ? 2 : 1 })
seed_category.call(NrGotmNomination, NrGotmVote, NrGotmEntry, nr_gotm_nominations, ->(_round) { 1 })

# The lists above are inputs, not outputs: which game wins a round falls out of
# the seeded RNG in seed_votes, and each winner prunes the rounds after it. So
# check the properties the fixtures exist to provide, rather than trusting that
# the last edit to a reason string did not move a winner and shrink a field.
titles = catalog.values.index_by(&:game_id)

categories = [
  [ "GOTM", GotmNomination, GotmEntry, gotm_nominations ],
  [ "NR-GOTM", NrGotmNomination, NrGotmEntry, nr_gotm_nominations ]
]

categories.each do |label, nomination_model, entry_model, fields|
  won_in = entry_model.pluck(:gamedb_game_id, :round_number)
  # Scoped to the seeded accounts like everything else here: a local database
  # holding real bot-synced nominations must not fail db:seed over rows this
  # file neither wrote nor controls.
  seeded = nomination_model.where(user_id: member_ids)

  seeded.where.not(gamedb_game_id: nil).order(:round_number).pluck(:round_number, :gamedb_game_id)
    .each do |round_number, game_id|
      _game, won_round = won_in.find { |won_game, won| won_game == game_id && won < round_number }
      next if won_round.nil?
      raise "#{label} round #{round_number} nominates #{titles.fetch(game_id).title}, which won round " \
            "#{won_round} — seed_nominations should have dropped it."
    end

  fields.each_key do |round_number|
    votable = seeded.where(round_number: round_number).where.not(gamedb_game_id: nil).count
    next if votable >= 2
    raise "#{label} round #{round_number} kept only #{votable} nomination(s) with a game after dropping " \
          "earlier winners — there is nothing to vote on. Add nominators to that round's list."
  end
end

# Field-size budget: dropping prior winners is the one thing that can push a
# round back under LARGE_FIELD_THRESHOLD and silently halve its vote cap.
[ 2, 3 ].each do |round_number|
  cap = Voting::CastVote.cap_for(GotmNomination, round_number)
  next if cap == Voting::CastVote::LARGE_FIELD_CAP
  raise "GOTM round #{round_number} kept #{GotmNomination.where(round_number: round_number).count} nominations, " \
        "under Voting::CastVote::LARGE_FIELD_THRESHOLD (#{Voting::CastVote::LARGE_FIELD_THRESHOLD}) — its vote " \
        "cap is #{cap}, not #{Voting::CastVote::LARGE_FIELD_CAP}. Add a nominator to that round's list."
end

current = BotVotingInfo.find_by(round_number: current_round)
puts <<~SUMMARY
  Seeded voting: #{GotmNomination.count} GOTM / #{NrGotmNomination.count} NR-GOTM nominations, \
  #{GotmVote.count} GOTM / #{NrGotmVote.count} NR-GOTM votes, \
  #{GotmEntry.count} GOTM / #{NrGotmEntry.count} NR-GOTM winners.
    round #{current_round} voting open:   #{current.voting_open?} (#{current.next_vote_at.iso8601} -> #{current.vote_deadline.iso8601})
    round #{current_round + 1} nominations open: #{BotVotingInfo.nominations_open_for?(current_round + 1)}
    GOTM vote cap for round #{current_round}: #{Voting::CastVote.cap_for(GotmNomination, current_round)} \
  (NR-GOTM: #{Voting::CastVote.cap_for(NrGotmNomination, current_round)})
SUMMARY
