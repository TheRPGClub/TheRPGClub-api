# frozen_string_literal: true

# An unsorted imported News Item as the News Import's download file lists it
# (spec #355, ticket #359): the fields a classifier needs to pick a News
# Category. Params: `authors`, as NewsItemResource takes them, so the author
# is named the way the News Hub names them.
class NewsImportItemResource
  include BaseResource

  attributes :message_id, :posted_at

  attribute :author_name do |item|
    params.fetch(:authors, {})[item.author_id] || item.author_name
  end

  attributes :comment, :link_url, :link_title, :link_site_name, :link_description

  attribute(:image_count) { |item| item.images.size }
end
