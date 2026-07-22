# frozen_string_literal: true

# Factories for the games-domain behavior specs (releases, announcements,
# images, and the join/lookup rows they hang off). Unique-indexed columns use
# random values rather than plain sequences so concurrently running rspec
# processes can't collide inside their (uncommitted) transactions.
FactoryBot.define do
  factory :release, class: "GamedbRelease" do
    game
    platform
    region
  end

  factory :release_announcement, class: "GamedbReleaseAnnouncement" do
    release
    announce_at { 1.week.from_now }
  end

  factory :game_image, class: "GamedbGameImage" do
    game
    kind { "cover" }
    object_key { "games/spec/#{SecureRandom.hex(8)}.jpg" }
    is_primary { false }
    position { 1 }

    trait :primary do
      is_primary { true }
    end
  end

  factory :game_platform, class: "GamedbGamePlatform" do
    game
    platform
  end

  factory :game_genre, class: "GamedbGameGenre" do
    game
    genre
  end
end
