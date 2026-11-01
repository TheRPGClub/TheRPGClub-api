# frozen_string_literal: true

module Achievements
  # A member's progress grid: their cached progress rows joined to the sets,
  # one card per Achievement Set (no cross-set merging).
  #
  # - `provider`  one Provider
  # - `status`    `in_progress` (at least one Unlock, not a Completion) or
  #               `completed`; nil lists every played set
  # - `sort`      `recent` (latest Unlock first, the default), `progress`
  #               (earned share first) or `title` (A to Z)
  class SetProgressGrid
    STATUSES = %w[in_progress completed].freeze
    SORTS = %w[recent progress title].freeze

    ORDERS = {
      "recent" => "user_achievement_set_progress.last_unlocked_at DESC NULLS LAST, user_achievement_set_progress.id DESC",
      "progress" => "user_achievement_set_progress.earned_count::float / NULLIF(user_achievement_set_progress.total_count, 0) " \
                    "DESC NULLS LAST, user_achievement_set_progress.last_unlocked_at DESC NULLS LAST, " \
                    "user_achievement_set_progress.id DESC",
      "title" => "LOWER(achievement_sets.title) ASC NULLS LAST, user_achievement_set_progress.id ASC"
    }.freeze

    def initialize(user_id:, provider: nil, status: nil, sort: nil)
      @user_id = user_id.to_s
      @provider = provider
      @status = status
      @sort = sort || "recent"
    end

    def relation
      scope = Reads.progress.where(user_id: @user_id).joins(:achievement_set).includes(:achievement_set)
      scope = scope.where(achievement_sets: { provider: @provider }) if @provider
      scope =
        case @status
        when "in_progress" then scope.where(completed_at: nil).where("user_achievement_set_progress.earned_count > 0")
        when "completed" then scope.where.not(completed_at: nil)
        else scope
        end
      scope.order(Arel.sql(ORDERS.fetch(@sort)))
    end
  end
end
