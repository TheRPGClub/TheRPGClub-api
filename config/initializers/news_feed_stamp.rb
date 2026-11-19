# frozen_string_literal: true

# Create the News Feed Stamp's SQLite file once per process, so its reads and
# writes skip the schema setup (see NewsItem::FeedStamp).
Rails.application.config.after_initialize do
  NewsItem::FeedStamp.setup!
end
