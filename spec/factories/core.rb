# frozen_string_literal: true

# Core factories shared across the behavior request specs. Unique-indexed
# columns use random values rather than plain sequences so concurrently
# running rspec processes can't collide inside their (uncommitted)
# transactions.
FactoryBot.define do
  factory :user, class: "RpgClubUser" do
    user_id { SecureRandom.random_number(10**18).to_s }
    username { "user_#{user_id}" }
    is_bot { false }

    trait :admin do
      role_admin { true }
    end
  end

  factory :game, class: "GamedbGame" do
    sequence(:title) { |n| "Test Game #{n} #{SecureRandom.hex(4)}" }
  end

  factory :genre, class: "GamedbGenre" do
    sequence(:name) { |n| "Genre #{n} #{SecureRandom.hex(4)}" }
    igdb_genre_id { SecureRandom.random_number(1_000_000_000) }
  end

  factory :platform, class: "GamedbPlatform" do
    sequence(:platform_code) { |n| "P#{n}#{SecureRandom.hex(3)}" }
    sequence(:platform_name) { |n| "Platform #{n} #{SecureRandom.hex(4)}" }
  end

  factory :backlog_entry, class: "UserGameBacklog" do
    user
    game
  end
end
