# frozen_string_literal: true

# Factories for the bot-community domain: presence history/prompts/opt-outs,
# public reminders, RSS feeds + seen items, starboard entries and Discord
# threads. String snowflake PKs have no DB default, so they are supplied here;
# unique-indexed columns use random values rather than plain sequences so
# concurrently running rspec processes can't collide inside their (uncommitted)
# transactions.
FactoryBot.define do
  factory :bot_presence_entry, class: "BotPresenceHistory" do
    activity_name { "Playing #{SecureRandom.hex(4)}" }
  end

  factory :presence_prompt do
    prompt_id { SecureRandom.random_number(10**18).to_s }
    user_id { SecureRandom.random_number(10**18).to_s }
    game_title { "Prompt Game #{SecureRandom.hex(4)}" }
    game_title_norm { PresencePromptOpt.normalize_title(game_title) }
  end

  factory :presence_prompt_opt do
    user_id { SecureRandom.random_number(10**18).to_s }
    scope { PresencePromptOpt::SCOPE_GAME }
    game_title { "Opt Game #{SecureRandom.hex(4)}" }
    game_title_norm { PresencePromptOpt.normalize_title(game_title) }

    trait :all do
      scope { PresencePromptOpt::SCOPE_ALL }
      game_title { nil }
      game_title_norm { PresencePromptOpt::ALL_TOKEN }
    end
  end

  factory :public_reminder, class: "RpgClubPublicReminder" do
    channel_id { SecureRandom.random_number(10**18).to_s }
    message { "Reminder #{SecureRandom.hex(4)}" }
    due_at { 1.day.from_now }
    enabled { true }
  end

  factory :rss_feed, class: "RpgClubRssFeed" do
    feed_name { "feed #{SecureRandom.hex(4)}" }
    feed_url { "https://example.com/#{SecureRandom.hex(8)}.rss" }
    channel_id { SecureRandom.random_number(10**18).to_s }
  end

  factory :rss_feed_item, class: "RpgClubRssFeedItem" do
    feed factory: :rss_feed
    item_id_hash { SecureRandom.hex(16) }
  end

  factory :starboard_entry, class: "RpgClubStarboardEntry" do
    message_id { SecureRandom.random_number(10**18).to_s }
    channel_id { SecureRandom.random_number(10**18).to_s }
    starboard_message_id { SecureRandom.random_number(10**18).to_s }
    author_id { SecureRandom.random_number(10**18).to_s }
    star_count { 1 }
  end

  factory :discord_thread do
    thread_id { SecureRandom.random_number(10**18).to_s }
    forum_channel_id { SecureRandom.random_number(10**18).to_s }
    thread_name { "thread #{SecureRandom.hex(4)}" }
  end

  factory :thread_game_link do
    thread factory: :discord_thread
    game
  end
end
