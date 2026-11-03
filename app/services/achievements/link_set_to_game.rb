# frozen_string_literal: true

module Achievements
  # Best-effort link of an Achievement Set to a GameDB game (research §6).
  #
  # - Steam: the global `rpg_club_steam_app_gamedb_map` decides when it has a
  #   row (mapped links, skipped stays unlinked); without a row the set falls
  #   back to title matching.
  # - RetroAchievements and PSN: title matching through the import matcher
  #   (Imports::CandidateFinder + TitleNormalizer.exact_match?).
  #
  # Title matching (Imports::UniqueTitleMatch) links only when exactly one
  # GameDB candidate is an exact match, trying the Provider title first, then
  # the title without edition noise. Ambiguous or missing matches leave
  # `game_id` nil. A set that is already linked is never relinked here; manual
  # fixes go through the admin PATCH endpoint.
  class LinkSetToGame
    def self.call(set)
      new(set).call
    end

    # Retries every unlinked set (the `achievements:link_sets` rake task).
    # Returns how many sets it linked.
    def self.link_unlinked
      AchievementSet.where(game_id: nil).find_each.count { |set| call(set).game_id.present? }
    end

    def initialize(set)
      @set = set
    end

    def call
      return @set if @set.game_id.present?

      game_id = @set.steam? ? steam_game_id : title_game_id
      @set.update!(game_id:) if game_id
      @set
    end

    private

    def steam_game_id
      map = RpgClubSteamAppGamedbMap.find_by(steam_app_id: @set.external_id.to_i)
      return title_game_id if map.nil?

      map.gamedb_game_id if map.status == "mapped" && GamedbGame.exists?(game_id: map.gamedb_game_id)
    end

    def title_game_id
      Imports::UniqueTitleMatch.call(@set.title).game_id
    end
  end
end
