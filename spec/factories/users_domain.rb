# frozen_string_literal: true

# Factories for the users domain (socials, avatar/nick history). Unique-indexed
# columns use random values rather than plain sequences so concurrently running
# rspec processes can't collide inside their (uncommitted) transactions.
#
# NOTE: the :social_platform factory lives in taxonomy.rb; the default platform
# here is created inline so this file never duplicates that definition.
FactoryBot.define do
  factory :user_social do
    user
    social_platform { SocialPlatform.create!(label: "Platform #{SecureRandom.hex(6)}") }
    url { "https://example.test/#{SecureRandom.hex(8)}" }
    display_text { "Handle #{SecureRandom.hex(4)}" }
  end

  factory :avatar_history_event, class: "RpgClubUserAvatarHistory" do
    user
    avatar_hash { SecureRandom.hex(16) }
    avatar_url { "https://cdn.example.test/avatars/#{SecureRandom.hex(8)}.png" }
  end

  factory :nick_history_event, class: "RpgClubUserNickHistory" do
    user
    old_nick { "old_#{SecureRandom.hex(4)}" }
    new_nick { "new_#{SecureRandom.hex(4)}" }
  end
end
