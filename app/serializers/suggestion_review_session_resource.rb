# frozen_string_literal: true

# Serializes a RpgClubSuggestionReviewSession (all columns). `suggestion_ids`
# is rendered verbatim as the stored JSON string; the bot parses it client-side.
class SuggestionReviewSessionResource
  include BaseResource

  columns_of RpgClubSuggestionReviewSession
end
