# frozen_string_literal: true

module Franchises
  # Franchise Progress (spec api#457, ticket api#461): how far members have
  # got through a Franchise.
  #
  # Three meters, each `{ done, total, playtime_minutes }`:
  # - `mainline`: the Mainline games;
  # - `spin_offs`: the Spin-offs (Gamedb::FranchiseGames `other`);
  # - `all`: both together.
  # A game is done when the member holds any Game Completion for it, counted
  # once however many they hold; an Alternate Version's Completion doesn't
  # count for it. Add-ons are left out, whatever their Mainline mark. A
  # meter with `total` 0 is empty. Playtime comes from Playtime::Ledger.
  #
  #   progress = Franchises::Progress.new(franchise)
  #   progress.for(user_id)   # one member: meters, conquered_at, games
  #   progress.members        # the members table, ranked
  class Progress
    # Most thorough first: the type a game shows when it has several.
    COMPLETION_TYPES = [ "Completionist", "Main Story + Side Content", "Main Story" ].freeze

    # The Mainline game ids that count towards a Conquest: Mainline links
    # that aren't Add-ons.
    def self.mainline_game_ids(franchise_id)
      GamedbGameFranchise.where(franchise_id: franchise_id, mainline: true)
        .joins(:game).where(gamedb_games: { parent_igdb_id: nil }).pluck(:game_id)
    end

    attr_reader :franchise, :mainline, :spin_offs

    def initialize(franchise)
      @franchise = franchise
      games = Gamedb::FranchiseGames.of(franchise)
      @mainline = games.fetch(:mainline)
      @spin_offs = games.fetch(:other)
    end

    def mainline_ids = @mainline_ids ||= mainline.map { |game| game[:game_id] }

    def spin_off_ids = @spin_off_ids ||= spin_offs.map { |game| game[:game_id] }

    def game_ids = mainline_ids + spin_off_ids

    # One member's progress: `{ user_id, franchise_id, conquered_at, meters,
    # games: { mainline, spin_offs } }`, each game as Gamedb::FranchiseGames
    # gives it plus `done`, `completion_type` and `playtime_minutes`.
    def for(user_id)
      user_id = user_id.to_s
      facts = Facts.new(self, user_ids: [ user_id ])
      { user_id: user_id, franchise_id: franchise.franchise_id,
        conquered_at: facts.conquered_at(user_id), meters: meters(facts, user_id),
        games: { mainline: game_rows(facts, user_id, mainline), spin_offs: game_rows(facts, user_id, spin_offs) } }
    end

    # The members table: every current member with Playtime or a Game
    # Completion here, or a Conquest. Each row `{ user (RpgClubUser),
    # meters, conquered_at }`. Conquered first, earliest first; then by
    # Mainline done (the whole Franchise when it has no Mainline games),
    # then by Playtime.
    def members
      facts = Facts.new(self, user_ids: nil)
      users = RpgClubUser.without_images.where(user_id: facts.user_ids, server_left_at: nil).index_by(&:user_id)
      rows = users.values.map do |user|
        { user: user, meters: meters(facts, user.user_id), conquered_at: facts.conquered_at(user.user_id) }
      end
      rows.sort_by { |row| rank(row) }
    end

    # The meters for one member.
    def meters(facts, user_id)
      { mainline: meter(facts, user_id, mainline_ids),
        all: meter(facts, user_id, game_ids),
        spin_offs: meter(facts, user_id, spin_off_ids) }
    end

    private

    def meter(facts, user_id, ids)
      { done: ids.count { |id| facts.done?(user_id, id) }, total: ids.size,
        playtime_minutes: ids.sum { |id| facts.minutes(user_id, id) } }
    end

    def game_rows(facts, user_id, games)
      games.map do |game|
        id = game[:game_id]
        game.slice(:game_id, :title, :cover_url, :release_year)
          .merge(done: facts.done?(user_id, id), completion_type: facts.completion_type(user_id, id),
            playtime_minutes: facts.minutes(user_id, id))
      end
    end

    def rank(row)
      ranked = mainline_ids.empty? ? row[:meters][:all] : row[:meters][:mainline]
      conquered = row[:conquered_at]
      [ conquered ? 0 : 1, conquered.to_f, -ranked[:done], -row[:meters][:all][:playtime_minutes], row[:user].user_id ]
    end

    # What the meters are worked out from, for some members (all when nil):
    # their Completions, Playtime and Conquests in the Franchise.
    class Facts
      def initialize(progress, user_ids:)
        ids = progress.game_ids
        completions = UserGameCompletion.where(gamedb_game_id: ids)
        completions = completions.where(user_id: user_ids) if user_ids
        @types = completions.pluck(:user_id, :gamedb_game_id, :completion_type)
          .group_by { |user_id, game_id, _type| [ user_id, game_id ] }
          .transform_values { |rows| rows.map(&:last).min_by { |type| COMPLETION_TYPES.index(type) || COMPLETION_TYPES.size } }
        @minutes = ids.empty? ? {} : Playtime::Ledger.new(user_ids: user_ids, game_ids: ids)
          .to_h { |playtime| [ [ playtime.user_id, playtime.game_id ], playtime.total_minutes ] }
        conquests = UserFranchiseConquest.where(franchise_id: progress.franchise.franchise_id)
        conquests = conquests.where(user_id: user_ids) if user_ids
        @conquered = conquests.pluck(:user_id, :conquered_at).to_h
      end

      def done?(user_id, game_id) = @types.key?([ user_id, game_id ])

      def completion_type(user_id, game_id) = @types[[ user_id, game_id ]]

      def minutes(user_id, game_id) = @minutes.fetch([ user_id, game_id ], 0)

      def conquered_at(user_id) = @conquered[user_id]

      # Members with Playtime above 0, a Completion, or a Conquest here.
      def user_ids
        playtime = @minutes.filter_map { |(user_id, _game_id), minutes| user_id if minutes.positive? }
        (@types.keys.map(&:first) + playtime + @conquered.keys).uniq
      end
    end
  end
end
