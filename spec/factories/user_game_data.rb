# frozen_string_literal: true

# Factories for the user-game data domain (completions, favorites, reviews,
# now-playing, journal entries) and the bot's journal message contexts.
# Unique-indexed columns use random values rather than plain sequences so
# concurrently running rspec processes can't collide inside their
# (uncommitted) transactions.
FactoryBot.define do
  factory :completion, class: "UserGameCompletion" do
    user
    game
    completion_type { "Main Story" }
  end

  factory :favorite, class: "UserGameFavorite" do
    user
    game
  end

  factory :review, class: "UserGameReview" do
    user
    game
    rating { 80 }
  end

  factory :now_playing_entry, class: "UserNowPlaying" do
    user
    game
  end

  factory :journal_entry, class: "UserGameJournalEntry" do
    user
    game
    entry_body { "journal body #{SecureRandom.hex(8)}" }
  end

  factory :journal_message_context, class: "JournalMessageContext" do
    channel_id { SecureRandom.random_number(10**18).to_s }
    message_id { SecureRandom.random_number(10**18).to_s }
    created_at_ms { SecureRandom.random_number(10**12) + 10**12 }
    owner_user_id { SecureRandom.random_number(10**18).to_s }
    game_id { SecureRandom.random_number(1_000_000_000) }
  end
end
