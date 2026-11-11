# frozen_string_literal: true

# A News Item as the website and the bot read it (spec #355). Params:
# `authors`, { author_id => current member name } for the authors who have a
# member record (NewsItemResource.authors_for builds it); `now`, the time
# image expiry is judged at (default: the current time).
#
# `images` are the message's image attachments in order. Each carries
# `unavailable`: true when its Discord address has expired, and then `url`
# is null until the bot renews it (ticket #358; the feed queues the renewal,
# NewsItems::ImageRenewal).
class NewsItemResource
  include BaseResource

  # `picked_category_key` is the category the bot first picked (ticket #368),
  # null when it picked none; `news_copy` is where the News Copy lives,
  # { message_id, thread_id }, or null for none.
  attributes :message_id, :category_key, :origin, :comment, :posted_at, :edited_at, :link,
    :picked_category_key, :news_copy

  attribute :images do |item|
    now = params[:now] || Time.current
    item.images.map do |image|
      expired = NewsItem.image_expired?(image, now)
      { url: expired ? nil : image["url"], unavailable: expired }
    end
  end

  attribute :author do |item|
    authors = params.fetch(:authors, {})
    member = authors.key?(item.author_id)
    { user_id: item.author_id, name: (member && authors[item.author_id]) || item.author_name, member: member }
  end

  # { author_id => current name or nil } for the given News Items' authors
  # who have a member record, in one query: the member's display name, else
  # their username.
  def self.authors_for(items)
    RpgClubUser.where(user_id: items.map(&:author_id).uniq).pluck(:user_id, :global_name, :username)
      .to_h { |user_id, global_name, username| [ user_id, global_name.presence || username.presence ] }
  end
end
