# frozen_string_literal: true

module Franchises
  # Queues the bot's Conquest post (spec api#457, ticket api#461; the 4B
  # card): BotJob kind `franchise_conquest`, owned by the
  # `franchise_progress` Feature, posted in the completions channel with no
  # pings. It posts even when the Completion behind it wasn't announced.
  #
  # The payload carries what the card shows, as it was when the Conquest
  # was written, so the bot needs no further reads:
  #
  #   user_id, franchise_id, completion_id   the job's keys
  #   franchise_name, conquered_at
  #   playtime_minutes                       the member's Franchise Playtime
  #                                          (Mainline and spin-offs)
  #   mainline_playtime_minutes, mainline_total
  #   covers                                 up to COVERS Mainline games with
  #                                          a cover, latest release first:
  #                                          { game_id, title, release_year,
  #                                          cover_url }
  #   also_conquered                         up to OTHERS other current
  #                                          members who Conquered it,
  #                                          earliest first:
  #                                          { user_id, name, conquered_at }
  #   also_conquered_count                   how many there are in all
  module ConquestAnnouncement
    KIND = "franchise_conquest"
    COVERS = 10
    OTHERS = 10

    # `progress` (a Franchises::Progress of `franchise`) may be shared
    # across the Conquests of one check.
    def self.enqueue!(conquest, franchise: conquest.franchise, progress: Progress.new(franchise), requested_by: nil)
      mine = progress.for(conquest.user_id)
      name = display_name(conquest.user)

      BotJob.enqueue!(
        kind: KIND,
        summary: "Announce #{name}'s Conquest of #{franchise.name}",
        payload: {
          user_id: conquest.user_id, franchise_id: franchise.franchise_id, completion_id: conquest.completion_id,
          franchise_name: franchise.name, conquered_at: conquest.conquered_at.iso8601,
          playtime_minutes: mine.dig(:meters, :all, :playtime_minutes),
          mainline_playtime_minutes: mine.dig(:meters, :mainline, :playtime_minutes),
          mainline_total: mine.dig(:meters, :mainline, :total),
          covers: covers(progress),
          **others(conquest)
        },
        requested_by: requested_by || conquest.user_id
      )
    end

    def self.covers(progress)
      progress.mainline.select { |game| game[:cover_url].present? }.last(COVERS).reverse
        .map { |game| game.slice(:game_id, :title, :release_year, :cover_url) }
    end

    def self.others(conquest)
      scope = UserFranchiseConquest.joins(:user).where(franchise_id: conquest.franchise_id)
        .where(rpg_club_users: { server_left_at: nil }).where.not(user_id: conquest.user_id)
      earlier = scope.order(:conquered_at, :id).limit(OTHERS).preload(:user).map do |other|
        { user_id: other.user_id, name: display_name(other.user), conquered_at: other.conquered_at.iso8601 }
      end
      { also_conquered: earlier, also_conquered_count: scope.count }
    end

    def self.display_name(user) = user.global_name.presence || user.username.presence || user.user_id

    private_class_method :covers, :others, :display_name
  end
end
