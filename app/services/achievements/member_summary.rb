# frozen_string_literal: true

module Achievements
  # A member's hub header: totals per Provider and overall, read from the cached
  # progress rows (no aggregation over Unlocks), their Linked Accounts and their
  # latest and rarest Unlocks. Only Providers the member has linked are listed.
  class MemberSummary
    LATEST = 5
    RAREST = 4
    TOTALS = %i[unlocks completions masteries platinums points].freeze

    def initialize(user)
      @user = user
    end

    def accounts
      @accounts ||= @user.linked_accounts.order(:provider).to_a
    end

    # [{ provider:, unlocks:, completions:, masteries:, platinums:, points: }]
    def providers
      @providers ||= begin
        sums = per_provider
        accounts.map { |account| { provider: account.provider }.merge(sums.fetch(account.provider, zero)) }
      end
    end

    def totals
      TOTALS.index_with { |key| providers.sum { |row| row[key] } }
    end

    def latest_unlocks
      unlocks.order(unlocked_at: :desc, id: :desc).limit(LATEST).to_a
    end

    # The member's rarest Unlocks by the Achievement's overall Rarity; an
    # Achievement with no known Rarity ranks after every rated one.
    def rarest_unlocks
      unlocks.order(Arel.sql("achievements.rarity ASC NULLS LAST, user_achievement_unlocks.unlocked_at DESC, user_achievement_unlocks.id DESC"))
        .limit(RAREST)
        .to_a
    end

    private

    def unlocks
      Reads.unlocks.where(user_id: @user.user_id).includes(achievement: :achievement_set)
    end

    def zero
      TOTALS.index_with(0)
    end

    def per_provider
      Reads.progress.where(user_id: @user.user_id).joins(:achievement_set)
        .group("achievement_sets.provider")
        .pluck(
          "achievement_sets.provider",
          Arel.sql("COALESCE(SUM(user_achievement_set_progress.earned_count), 0)"),
          Arel.sql("COUNT(user_achievement_set_progress.completed_at)"),
          Arel.sql("COUNT(user_achievement_set_progress.mastered_at)"),
          Arel.sql("COUNT(user_achievement_set_progress.platinum_at)"),
          Arel.sql("COALESCE(SUM(user_achievement_set_progress.points_earned), 0)")
        )
        .to_h { |provider, *values| [ provider, TOTALS.zip(values.map(&:to_i)).to_h ] }
    end
  end
end
