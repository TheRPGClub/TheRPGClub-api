# frozen_string_literal: true

module Imports
  # The review step of the collection CSV and Steam import loops (#289,
  # #290): the item that needs a human, its candidates and the stored
  # match_confidence. `item` is nil when nothing needs a human (see
  # CollectionCsvWorkflow#advance / SteamWorkflow#advance).
  #
  #   Imports::Review.none  # => Review(item: nil, candidates: [], match_confidence: nil)
  #   Imports::Review.for(item, candidates)  # match_confidence read from the item
  Review = Data.define(:item, :candidates, :match_confidence) do
    def self.none = new(item: nil, candidates: [], match_confidence: nil)

    def self.for(item, candidates) = new(item: item, candidates: candidates, match_confidence: item.match_confidence)
  end
end
