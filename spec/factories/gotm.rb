# frozen_string_literal: true

# Factories for the GOTM / Non-RPG GOTM domain: round entries, nominations,
# votes and the bot voting-info rounds. Unique-indexed columns (round numbers,
# the voting-info primary key) use random values rather than plain sequences so
# concurrently running rspec processes can't collide inside their (uncommitted)
# transactions.
FactoryBot.define do
  factory :gotm_entry do
    # gotm_entries.round_number is a 32-bit integer; game_index a smallint.
    round_number { SecureRandom.random_number(1_000_000_000) }
    month_year { "Spec Month #{SecureRandom.hex(4)}" }
    game_index { 0 }
    game
  end

  factory :nr_gotm_entry do
    round_number { SecureRandom.random_number(1_000_000_000) }
    month_year { "Spec #{SecureRandom.hex(4)}" }
    game_index { 0 }
    game
  end

  factory :gotm_nomination do
    round_number { SecureRandom.random_number(1_000_000_000) }
    user
    game
    reason { "spec nomination #{SecureRandom.hex(4)}" }
  end

  factory :nr_gotm_nomination do
    round_number { SecureRandom.random_number(1_000_000_000) }
    user
    game
    reason { "spec nomination #{SecureRandom.hex(4)}" }
  end

  # Votes denormalize their nomination's round and game, so both default to
  # the associated nomination's values and stay consistent when a spec passes
  # its own `nomination:`.
  factory :gotm_vote do
    nomination factory: %i[gotm_nomination]
    user
    round_number { nomination.round_number }
    gamedb_game_id { nomination.gamedb_game_id }
  end

  factory :nr_gotm_vote do
    nomination factory: %i[nr_gotm_nomination]
    user
    round_number { nomination.round_number }
    gamedb_game_id { nomination.gamedb_game_id }
  end

  factory :voting_info, class: "BotVotingInfo" do
    round_number { SecureRandom.random_number(1_000_000_000) }
    next_vote_at { 2.days.from_now }
  end
end
