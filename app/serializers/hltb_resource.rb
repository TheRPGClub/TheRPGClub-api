# frozen_string_literal: true

# Serializes an RpgClubHltbCache row — the bot's scraped HowLongToBeat cache for
# a game — for the aggregate game profile (#115). The cache lives in the shared
# DB but is third-party data, so the profile exposes it (nullable when no row
# exists) to spare the bot a direct-SQL read on the view path.
#
# The three `hltb_`-prefixed columns are surfaced under the bot's logical names
# (`name` / `url` / `image_url`) so the payload matches the shape requested in
# #115; the playtime/metadata columns pass through unchanged.
class HltbResource
  include BaseResource

  attribute(:name) { |cache| cache.hltb_name }
  attribute(:url) { |cache| cache.hltb_url }
  attribute(:image_url) { |cache| cache.hltb_image_url }

  attributes :main, :main_sides, :completionist, :single_player, :co_op, :vs,
             :source_query, :scraped_at, :updated_at
end
