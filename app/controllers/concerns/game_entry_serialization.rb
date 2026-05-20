# frozen_string_literal: true

# Shared serialization for user-scoped game list entries (favorites, backlog,
# collections, completions, now playing). Embeds the `game` association and
# optionally the `platform` so the frontend can render cover art, platform
# pills, and titles without a second round-trip.
module GameEntrySerialization
  extend ActiveSupport::Concern

  private

  def serialize_with_game(entry)
    entry.as_json.merge("game" => entry.game&.as_json)
  end

  def serialize_with_game_and_platform(entry)
    entry.as_json.merge(
      "game" => entry.game&.as_json,
      "platform" => entry.platform&.as_json
    )
  end
end
