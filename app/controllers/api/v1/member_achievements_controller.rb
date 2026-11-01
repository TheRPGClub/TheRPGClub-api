# frozen_string_literal: true

module Api
  module V1
    # A member's Achievement Hub reads for www: the summary header, the set
    # progress grid and the flat Unlocks list. Open to any signed-in principal.
    # Departed members, placeholder progress rows and removed Achievements are
    # excluded (Achievements::Reads).
    class MemberAchievementsController < ApplicationController
      include AchievementReadParams

      # 404 unless the member is active and has at least one Linked Account:
      # the hub is opt-in, so www shows the profile section only on a 200.
      def summary
        user = RpgClubUser.active.without_images.find_by(user_id: params[:user_id])
        summary = user && Achievements::MemberSummary.new(user)
        return render(json: { error: "not_found" }, status: :not_found) if summary.nil? || summary.accounts.empty?

        latest = summary.latest_unlocks
        render json: {
          data: {
            user: UserSummaryResource.new(user).serializable_hash,
            totals: summary.totals,
            providers: summary.providers,
            linked_accounts: LinkedAccountSummaryResource.new(summary.accounts).serializable_hash,
            latest_unlocks: AchievementUnlockResource.new(latest, params: viewer_params(latest)).serializable_hash
          }
        }
      end

      # The progress grid, filtered by `provider` and `status` and sorted by
      # `sort` (see Achievements::SetProgressGrid).
      def sets
        grid = Achievements::SetProgressGrid.new(
          user_id: params[:user_id],
          provider: enum_param(:provider, Achievements::Reads::PROVIDERS),
          status: enum_param(:status, Achievements::SetProgressGrid::STATUSES),
          sort: enum_param(:sort, Achievements::SetProgressGrid::SORTS)
        )
        pagy, records = pagy(grid.relation, **pagy_options)
        render json: { data: AchievementSetProgressResource.new(records).serializable_hash, meta: pagy_meta(pagy) }
      end

      # The member's flat Unlocks, newest first.
      def unlocks
        scope = Achievements::Reads.unlocks.where(user_id: params[:user_id])
          .includes(achievement: :achievement_set)
          .order(unlocked_at: :desc, id: :desc)
        pagy, records = pagy(scope, **pagy_options)
        render json: {
          data: AchievementUnlockResource.new(records, params: viewer_params(records)).serializable_hash,
          meta: pagy_meta(pagy)
        }
      end
    end
  end
end
