# frozen_string_literal: true

module Achievements
  # The community feed.
  #
  # - `latest`: Unlocks grouped into cards per member + Achievement Set + UTC
  #   day of `unlocked_at`, newest card first. Each card carries its count and
  #   up to CARD_UNLOCKS of its newest Unlocks.
  # - `highlights`: one card per Highlight Unlock, newest first by its
  #   highlight_time (a Mastery's hardcore time).
  #
  # `highlights` pages through a relation; `latest` reads one page of groups
  # together with their total (#group_page), so the club's history is
  # aggregated once per page. Both turn a page into cards in a fixed number of
  # queries.
  class Feed
    VIEWS = %w[latest highlights].freeze
    CARD_UNLOCKS = 8

    # `unlocked_at` is stored as UTC without a zone, so its date is the UTC day.
    DAY = "(user_achievement_unlocks.unlocked_at)::date"

    Group = Data.define(:user, :achievement_set, :day, :count, :latest_unlocked_at, :unlocks)

    def initialize(provider: nil)
      @provider = provider
    end

    # One row per card: user_id, achievement_set_id, day, unlocks_count and
    # latest_unlocked_at, newest card first.
    def groups
      grouped.select(
        "user_achievement_unlocks.user_id",
        "achievements.achievement_set_id AS achievement_set_id",
        "#{DAY} AS day",
        "COUNT(*) AS unlocks_count",
        "MAX(user_achievement_unlocks.unlocked_at) AS latest_unlocked_at"
      ).order(Arel.sql("MAX(user_achievement_unlocks.unlocked_at) DESC, user_achievement_unlocks.user_id ASC, " \
                       "achievements.achievement_set_id ASC"))
    end

    # One page of #groups and the total number of groups, from one aggregation
    # (a window count over the grouped rows). Only a page past the last one
    # has no row to carry the total, and counts it apart.
    def group_page(page:, limit:)
      rows = groups.select("COUNT(*) OVER () AS groups_count").offset(limit * (page - 1)).limit(limit).to_a
      [ rows.first&.groups_count || (page > 1 ? group_count : 0), rows ]
    end

    def group_count
      UserAchievementUnlock.connection.select_value("SELECT COUNT(*) FROM (#{grouped.select('1').to_sql}) AS groups").to_i
    end

    # The page's rows from #groups as Group cards.
    def cards(rows)
      return [] if rows.empty?

      users = users_by_id(rows.map(&:user_id))
      sets = AchievementSet.where(id: rows.map(&:achievement_set_id).uniq).index_by(&:id)
      unlocks = card_unlocks(rows).group_by { |u| [ u.user_id, u.achievement.achievement_set_id, u.unlocked_at.utc.to_date ] }

      rows.map do |row|
        day = row.day.to_date
        Group.new(
          user: users[row.user_id], achievement_set: sets[row.achievement_set_id], day: day,
          count: row.unlocks_count, latest_unlocked_at: row.latest_unlocked_at,
          unlocks: unlocks.fetch([ row.user_id, row.achievement_set_id, day ], [])
        )
      end
    end

    # Highlight Unlocks, newest first by their highlight_time (a Mastery is
    # dated by its hardcore time).
    def highlights
      scoped.where.not(highlight: nil).includes(achievement: :achievement_set)
        .order(Arel.sql("#{UserAchievementUnlock::HIGHLIGHT_TIME_SQL} DESC"), id: :desc)
    end

    # Members of the given Unlocks, without their image columns, by user_id.
    def users_by_id(user_ids)
      RpgClubUser.without_images.where(user_id: user_ids.uniq).index_by(&:user_id)
    end

    private

    def scoped
      scope = Reads.unlocks
      scope = scope.joins(achievement: :achievement_set).where(achievement_sets: { provider: @provider }) if @provider
      scope
    end

    def grouped
      scoped.group("user_achievement_unlocks.user_id", "achievements.achievement_set_id", Arel.sql(DAY))
    end

    # The newest CARD_UNLOCKS Unlocks of each card on the page, in one query.
    def card_unlocks(rows)
      keys = rows.map do |row|
        ActiveRecord::Base.sanitize_sql_array([ "(?, ?, ?::date)", row.user_id, row.achievement_set_id, row.day.to_date ])
      end
      ranked = scoped
        .where(Arel.sql("(user_achievement_unlocks.user_id, achievements.achievement_set_id, #{DAY}) IN (#{keys.join(', ')})"))
        .select("user_achievement_unlocks.*",
          "ROW_NUMBER() OVER (PARTITION BY user_achievement_unlocks.user_id, achievements.achievement_set_id, #{DAY} " \
          "ORDER BY user_achievement_unlocks.unlocked_at DESC, user_achievement_unlocks.id DESC) AS position")
      UserAchievementUnlock.from(ranked, :user_achievement_unlocks)
        .where("user_achievement_unlocks.position <= ?", CARD_UNLOCKS)
        .includes(achievement: :achievement_set)
        .order(unlocked_at: :desc, id: :desc)
        .to_a
    end
  end
end
