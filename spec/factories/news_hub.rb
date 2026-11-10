# frozen_string_literal: true

# News Hub factories (spec #355). Snowflakes are random so concurrently
# running rspec processes cannot collide on the unique message id.
FactoryBot.define do
  factory :news_item do
    message_id { SecureRandom.random_number(10**18).to_s }
    channel_id { SecureRandom.random_number(10**18).to_s }
    author_id { SecureRandom.random_number(10**18).to_s }
    author_name { "Poster #{SecureRandom.hex(3)}" }
    category_key { "general" }
    origin { "live" }
    posted_at { Time.current }
    link_url { "https://example.test/news/#{SecureRandom.hex(4)}" }
  end

  factory :member_news_category_preference do
    association :user
    category_key { "general" }
  end
end
