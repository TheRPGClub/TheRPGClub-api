# frozen_string_literal: true

# Serializes a RpgClubSuggestion (all columns) plus its upvote count and
# whether the viewer upvoted it. Load records through
# `RpgClubSuggestion.with_upvotes(viewer_id)` so both are present.
class SuggestionResource
  include BaseResource

  columns_of RpgClubSuggestion

  attribute :upvote_count do |suggestion|
    suggestion.attributes["upvote_count"].to_i
  end

  attribute :viewer_upvoted do |suggestion|
    suggestion.attributes["viewer_upvoted"] == true
  end
end
