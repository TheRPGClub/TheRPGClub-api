# frozen_string_literal: true

# Challenges factories (spec #376). A :challenge is an Always Open Pool
# Challenge hosted by a member, whose Pool is one Optional Game picked by
# hand, of which a Run needs 1.
FactoryBot.define do
  factory :gamedb_collection, class: "GamedbCollection" do
    sequence(:name) { |n| "Collection #{n} #{SecureRandom.hex(4)}" }
    igdb_collection_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :challenge do
    sequence(:name) { |n| "Challenge #{n} #{SecureRandom.hex(3)}" }
    description { "Play some games." }
    host factory: %i[user]
    challenge_format { "pool" }
    schedule { "always_open" }
    pool_optional_target { 1 }

    after(:create) do |challenge|
      ChallengePoolGame.create!(challenge: challenge, game: create(:game), inclusion: "optional")
    end

    trait :club_hosted do
      host { nil }
    end

    # A Season from `season` "MM-DD..MM-DD".
    trait :seasonal do
      transient { season { "06-21..09-22" } }
      schedule { "seasonal" }
      after(:build) do |challenge, evaluator|
        starts, ends = evaluator.season.split("..").map { |md| md.split("-").map(&:to_i) }
        challenge.assign_attributes(season_start_month: starts[0], season_start_day: starts[1],
          season_end_month: ends[0], season_end_day: ends[1])
      end
    end
  end

  factory :challenge_run do
    challenge
    user
    status { "active" }
  end
end
