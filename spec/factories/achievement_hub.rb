# frozen_string_literal: true

# Achievement Hub factories. External ids are random so concurrently running
# rspec processes can't collide on the unique indexes.
FactoryBot.define do
  factory :user_linked_account do
    user
    provider { "steam" }
    external_id { SecureRandom.random_number(10**17).to_s }
    display_name { "player_#{SecureRandom.hex(4)}" }
    sync_status { "ok" }
    sync_mode { "incremental" }
  end

  factory :achievement_set do
    provider { "steam" }
    external_id { SecureRandom.random_number(10**9).to_s }
    sequence(:title) { |n| "Achievement Set #{n}" }
  end

  factory :achievement do
    achievement_set
    external_id { "ach_#{SecureRandom.hex(6)}" }
    sequence(:name) { |n| "Achievement #{n}" }
    rarity { 50.0 }
  end

  factory :user_achievement_unlock do
    linked_account factory: :user_linked_account
    user { linked_account.user }
    achievement
    unlocked_at { Time.current }
  end

  factory :user_achievement_set_progress do
    linked_account factory: :user_linked_account
    user { linked_account.user }
    achievement_set
    synced_at { Time.current }
  end

  factory :achievement_hub_state do
    key { "state_#{SecureRandom.hex(4)}" }
    value { {} }
  end
end
