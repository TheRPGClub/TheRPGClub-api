# frozen_string_literal: true

module Challenges
  # The Santas' picks in a drawn Edition (spec #376, "Secret Santa"; ticket
  # #384). Every date is the club's.
  #
  #   santa!(edition, user_id)            the member's own sign-up as a Santa
  #   eligible_backlog(user_id)           what a Santa may pick for them
  #   taste(user_id)                      hints about what they like
  #   pick!(edition, user_id, game_id)    a Santa's pick, before the deadline
  #   withdraw!(signup)                   a Santa leaving after the draw
  #   close!(edition, now:, random:)      the random picks, at the deadline
  #
  # A Santa sees only their recipient's backlog minus the games the recipient
  # has Cleared (any Game Completion of the game), and picks one game from it
  # privately until the start of the pick deadline day; they may change it
  # until then. At the deadline every recipient whose Santa has no pick (they
  # missed it, withdrew, or left the server before picking) gets a random
  # pick from that same backlog through the backlog picker (BacklogPicker), which also passes
  # over the games in their Now Playing while it has others to choose from.
  # The circle is never redrawn.
  module Picks
    NOT_A_SANTA = "You aren't a Santa in the %<year>d Edition."
    CLOSED = "Picks for the %<year>d Edition closed on %<date>s."
    NOT_ELIGIBLE = "Pick a game from your recipient's backlog that they haven't Cleared."
    NOT_DRAWN = "The draw left you out of the %<year>d Edition."
    WITHDRAW_CLOSED = "Picks for the %<year>d Edition closed on %<date>s, so you can no longer withdraw. " \
                      "You can abandon your Run instead."

    # The drawn member's sign-up, the Santa of its `recipient_user_id`.
    # Refused (403 `not_a_santa`) for anyone else, before the draw, or once
    # they withdrew.
    def self.santa!(edition, user_id)
      signup = edition.signups.drawn.find_by(user_id: user_id, withdrawn_at: nil) if user_id.present?
      return signup if signup && edition.drawn?

      raise SignupRefused.new("not_a_santa", format(NOT_A_SANTA, year: edition.year), status: :forbidden)
    end

    # The recipient's backlog entries a Santa may pick from: every game in it
    # they have not Cleared.
    def self.eligible_backlog(user_id)
      UserGameBacklog.where(user_id: user_id).where.not(gamedb_game_id: cleared_game_ids(user_id))
    end

    TASTE_GENRES = 3

    # Taste hints for a Santa about their recipient (design picks, bot 7C
    # "Gift tags"): the member's top 3 genres and top platform across the
    # games in their Game Completions and backlog, each game counted once
    # (ties by name). Only these; no other personal data.
    #   { genres: [{ genre_id, name }], platform: { platform_id, platform_name, platform_abbreviation } | nil }
    def self.taste(user_id)
      games = GamedbGameGenre.where(game_id: UserGameCompletion.where(user_id: user_id).select(:gamedb_game_id))
        .or(GamedbGameGenre.where(game_id: UserGameBacklog.where(user_id: user_id).select(:gamedb_game_id)))
      genres = GamedbGenre.joins(:game_genres).merge(games).group(:genre_id, :name)
        .order(Arel.sql("COUNT(*) DESC"), :name, :genre_id).limit(TASTE_GENRES).pluck(:genre_id, :name)
      platform = GamedbPlatform.joins(ApplicationRecord.sanitize_sql_array([ PLAYED_ON_SQL, { user_id: user_id } ]))
        .group(:platform_id).order(Arel.sql("COUNT(*) DESC"), :platform_name, :platform_id).first
      { genres: genres.map { |genre_id, name| { genre_id: genre_id, name: name } },
        platform: platform&.slice(:platform_id, :platform_name, :platform_abbreviation) }
    end

    # The member's (game, platform) pairs from their Game Completions and
    # backlog, each once.
    PLAYED_ON_SQL = <<~SQL.squish.freeze
      JOIN (SELECT gamedb_game_id, platform_id FROM user_game_completions
              WHERE user_id = :user_id AND platform_id IS NOT NULL
            UNION
            SELECT gamedb_game_id, platform_id FROM user_game_backlog
              WHERE user_id = :user_id AND platform_id IS NOT NULL) played
        ON played.platform_id = gamedb_platforms.platform_id
    SQL
    private_constant :PLAYED_ON_SQL

    # The games the member has Cleared: any Game Completion of them.
    def self.cleared_game_ids(user_id)
      UserGameCompletion.where(user_id: user_id).where.not(gamedb_game_id: nil).select(:gamedb_game_id)
    end
    private_class_method :cleared_game_ids

    # Whether Santas may still pick on the club date `today`.
    def self.open?(edition, today = Challenges.today)
      edition.phase == "picking" && edition.picks_closed_at.nil? && today < edition.pick_deadline_on
    end

    def self.pick!(edition, user_id, game_id, now: Time.current)
      edition.with_lock do
        signup = santa!(edition, user_id)
        refuse_closed!(edition, Challenges.today(now))
        unless eligible_backlog(signup.recipient_user_id).exists?(gamedb_game_id: game_id)
          raise SignupRefused.new("not_eligible", NOT_ELIGIBLE, status: :unprocessable_content)
        end

        signup.update!(picked_game_id: game_id, picked_at: now, picked_randomly: false)
        signup
      end
    end

    # A drawn member withdraws after the draw, until the pick deadline: they
    # leave the Edition, so their pick is dropped (their recipient gets a
    # random one at the deadline) and their own Run is Abandoned. The circle
    # is not redrawn. Call inside the Edition's lock.
    def self.withdraw!(signup, now: Time.current)
      edition = signup.edition
      if signup.left_out?
        raise SignupRefused.new("not_drawn", format(NOT_DRAWN, year: edition.year))
      end
      unless open?(edition, Challenges.today(now))
        raise SignupRefused.new("picks_closed", format(WITHDRAW_CLOSED, year: edition.year,
          date: edition.pick_deadline_on.strftime("%-d %B %Y")))
      end

      signup.update!(withdrawn_at: now, picked_game_id: nil, picked_at: nil, picked_randomly: false)
      edition.runs.active.where(user_id: signup.user_id).find_each { |run| Runs.abandon!(run, now: now) }
    end

    # The pick deadline: every recipient whose Santa has no pick (missed,
    # withdrew, or left the server before picking; a Santa who left after
    # picking keeps their pick) gets a random pick from their eligible backlog,
    # through the backlog picker (passing over their Now Playing unless that
    # leaves nothing). A recipient with nothing eligible is left without a
    # game. Done once per Edition (`picks_closed_at`).
    def self.close!(edition, now:, random: Random.new)
      edition.with_lock do
        next unless edition.phase == "picking" && edition.picks_closed_at.nil?

        edition.signups.drawn.order(:id).each do |signup|
          next if signup.picked_game_id

          game_id = random_pick(signup.recipient_user_id, random)
          signup.update!(picked_game_id: game_id, picked_at: game_id && now, picked_randomly: !game_id.nil?)
        end
        edition.update!(picks_closed_at: now)
      end
    end

    def self.random_pick(user_id, random)
      seed = random.rand(BacklogPicker::MAX_SEED)
      [ false, true ].each do |include_now_playing|
        pick = BacklogPicker.new(user_id: user_id, seed: seed, exclude_game_ids: cleared_game_ids(user_id),
          include_now_playing: include_now_playing).call.pick
        return pick.entry.gamedb_game_id if pick
      end
      nil
    end
    private_class_method :random_pick

    def self.refuse_closed!(edition, today)
      return if open?(edition, today)

      raise SignupRefused.new("picks_closed",
        format(CLOSED, year: edition.year, date: edition.pick_deadline_on.strftime("%-d %B %Y")))
    end
    private_class_method :refuse_closed!
  end
end
