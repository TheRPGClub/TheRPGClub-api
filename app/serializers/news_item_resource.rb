# frozen_string_literal: true

# A News Item as the website and the bot read it (spec #355). Params:
# `authors`, { author_id => current member name } for the authors who have a
# member record (NewsItemResource.authors_for builds it).
#
# `images` are the message's image attachments in order. Each carries
# `unavailable`: when true its Discord address has expired and `url` is null
# until the bot renews it (api#358); for now it is always false.
class NewsItemResource
  include BaseResource

  attributes :message_id, :category_key, :origin, :comment, :posted_at, :edited_at, :link

  attribute :images do |item|
    item.images.map { |image| { url: image["url"], unavailable: false } }
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
