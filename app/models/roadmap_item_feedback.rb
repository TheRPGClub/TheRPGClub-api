# frozen_string_literal: true

# A Feedback linked to a Roadmap Item (spec api#505, ticket api#508). A
# Feedback sits on at most one item; staff set an item's links with
# Roadmap::Items.link_feedback!.
class RoadmapItemFeedback < ApplicationRecord
  self.table_name = "roadmap_item_feedback"

  belongs_to :item, class_name: "RoadmapItem", inverse_of: :feedback_links
  belongs_to :feedback, class_name: "RpgClubFeedback", inverse_of: false
end
