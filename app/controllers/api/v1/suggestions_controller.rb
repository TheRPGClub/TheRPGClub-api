# frozen_string_literal: true

module Api
  module V1
    class SuggestionsController < ApplicationController
      # Columns a caller may set on create. Status and the review columns are
      # server-managed; a member's authorship comes from their session.
      WRITABLE = %w[title details labels created_by created_by_name].freeze

      before_action :require_superadmin!, only: %i[approve reject]
      before_action :require_member_or_staff!, only: %i[create upvote remove_upvote]
      before_action :require_member!, only: %i[withdraw upvote remove_upvote]

      def index
        statuses = status_filter
        return if performed?

        scope = viewer_scope
        scope = scope.where(status: statuses) if statuses
        render_collection(scope, resource: SuggestionResource, default_order: RpgClubSuggestion::BOARD_ORDER)
      end

      def show
        render_suggestion(params[:id])
      end

      # Members role holders, staff, or the bot. A member is always the author, and
      # their submission asks the bot to ping the bot dev; the bot pings
      # inline for its own /suggestion submissions, so a service create
      # enqueues nothing.
      def create
        attrs = request_data.slice(*WRITABLE)
        record = RpgClubSuggestion.transaction do
          if current_principal.discord_user?
            attrs.merge!("created_by" => current_principal.id, "created_by_name" => author_name)
          end
          suggestion = RpgClubSuggestion.create!(attrs)
          enqueue_submitted_ping(suggestion) if current_principal.discord_user?
          suggestion
        end
        render_suggestion(record.suggestion_id, status: :created)
      end

      # Superadmin (or the bot, for a Discord reviewer named in `reviewed_by`).
      # Opens a GitHub issue in `target_repo` (one of
      # RpgClubSuggestion::TARGET_REPOS) as the bot did, stores it and asks the
      # bot to announce the outcome. The row stays locked across the GitHub call
      # so two approvals cannot open two issues. A GitHub failure changes nothing.
      def approve
        data = request_data
        repo = data["target_repo"].to_s.strip
        unless RpgClubSuggestion::TARGET_REPOS.include?(repo)
          return render json: { error: "target_repo must be one of #{RpgClubSuggestion::TARGET_REPOS.join(', ')}" },
            status: :unprocessable_content
        end

        review(data) do |suggestion|
          issue = Github::Client.new.create_issue(
            repo: repo, title: suggestion.title, body: issue_body(suggestion), labels: issue_labels(suggestion)
          )
          Github::IssueStateCache.store(repo, issue.number, issue.state)
          { status: "approved", target_repo: repo, github_issue_number: issue.number, github_issue_url: issue.url }
        end
      rescue Github::Client::ConfigurationError => error
        render json: { error: "github_not_configured", message: error.message }, status: :service_unavailable
      rescue Github::Client::RequestError => error
        render json: { error: "github_issue_failed", message: error.message }, status: :bad_gateway
      end

      # Superadmin (or the bot, as for approve). `rejection_reason` is required.
      def reject
        data = request_data
        reason = data["rejection_reason"].to_s.strip
        return render json: { error: "rejection_reason is required" }, status: :unprocessable_content if reason.empty?

        review(data) { { status: "rejected", rejection_reason: reason } }
      end

      # The author takes back their own Pending Suggestion. Anyone else
      # (staff and the service included) is refused; a reviewed or already
      # withdrawn Suggestion is a 409.
      def withdraw
        suggestion = RpgClubSuggestion.find(params[:id])
        return render json: { error: "forbidden" }, status: :forbidden unless suggestion.created_by == current_principal.id

        suggestion.with_lock do
          unless suggestion.status == "pending"
            return render json: { error: "suggestion is #{suggestion.status}, not pending" }, status: :conflict
          end

          suggestion.update!(status: "withdrawn")
        end
        render_suggestion(suggestion.suggestion_id)
      end

      # A member's upvote, at most one each (repeating it is a no-op). Only
      # Pending and Approved Suggestions take upvotes.
      def upvote
        suggestion = RpgClubSuggestion.find(params[:id])
        unless RpgClubSuggestion::UPVOTABLE_STATUSES.include?(suggestion.status)
          return render json: { error: "a #{suggestion.status} suggestion cannot be upvoted" }, status: :conflict
        end

        RpgClubSuggestionUpvote.insert(
          { suggestion_id: suggestion.suggestion_id, user_id: current_principal.id },
          unique_by: :ux_rpg_club_suggestion_upvotes_suggestion_user
        )
        render_suggestion(suggestion.suggestion_id)
      end

      # Removes the member's upvote, if any, whatever the status.
      def remove_upvote
        suggestion = RpgClubSuggestion.find(params[:id])
        suggestion.upvotes.where(user_id: current_principal.id).delete_all
        render_suggestion(suggestion.suggestion_id)
      end

      private

      # Locks the Suggestion, 409s unless it is pending, applies the block's
      # columns plus the reviewer and time, and enqueues the outcome job, all in
      # one transaction. Renders `{ data: Suggestion, meta: { outcome_job_id } }`.
      def review(data)
        suggestion = RpgClubSuggestion.find(params[:id])
        job = nil
        suggestion.with_lock do
          unless suggestion.status == "pending"
            return render json: { error: "suggestion is #{suggestion.status}, not pending" }, status: :conflict
          end

          suggestion.update!(**yield(suggestion), reviewed_by: reviewer_id(data), reviewed_at: Time.current)
          job = enqueue_outcome(suggestion)
        end
        render json: {
          data: SuggestionResource.new(viewer_scope.find(suggestion.suggestion_id)).serializable_hash,
          meta: { outcome_job_id: job.id }
        }
      end

      # A member reviews as themselves; the bot names the Discord reviewer.
      def reviewer_id(data)
        current_principal.discord_user? ? current_principal.id : data["reviewed_by"].presence&.to_s
      end

      # The bot's issue body and labels (suggestion.command.ts approveSuggestion).
      def issue_body(suggestion)
        "#{suggestion.created_by_name.presence || 'Unknown'}: #{suggestion.details.presence || 'No details provided.'}"
      end

      def issue_labels(suggestion)
        suggestion.labels.to_s.split(",").map(&:strip).compact_blank
      end

      # Payload (kind suggestion_outcome): { suggestion_id, outcome, created_by,
      # title, github_issue_number, github_issue_url, rejection_reason }.
      # Enqueued for the bot's own reviews too: the job is the announcement.
      def enqueue_outcome(suggestion)
        BotJob.enqueue!(
          kind: "suggestion_outcome",
          payload: {
            suggestion_id: suggestion.suggestion_id, outcome: suggestion.status, created_by: suggestion.created_by,
            title: suggestion.title, github_issue_number: suggestion.github_issue_number,
            github_issue_url: suggestion.github_issue_url, rejection_reason: suggestion.rejection_reason
          },
          requested_by: current_principal.discord_user? ? current_principal.id : nil
        )
      end

      # Upvotes and withdraw act as a signed-in member; the service has no
      # member identity to act as.
      def require_member!
        return true if current_principal.discord_user?

        render json: { error: "forbidden" }, status: :forbidden
        false
      end

      def viewer_scope
        RpgClubSuggestion.with_upvotes(current_principal.discord_user? ? current_principal.id : nil)
      end

      def render_suggestion(id, status: :ok)
        render json: { data: SuggestionResource.new(viewer_scope.find(id)).serializable_hash }, status: status
      end

      def author_name
        RpgClubUser.where(user_id: current_principal.id).pick(:username) || current_principal.username
      end

      # Payload (kind suggestion_submitted): { suggestion_id, created_by }.
      def enqueue_submitted_ping(suggestion)
        BotJob.enqueue!(
          kind: "suggestion_submitted",
          payload: { suggestion_id: suggestion.suggestion_id, created_by: suggestion.created_by },
          requested_by: current_principal.id
        )
      end

      # `?status=pending,approved`: nil (every status) when absent; 400 for a
      # value outside RpgClubSuggestion::STATUSES.
      def status_filter
        return if params[:status].blank?

        statuses = params[:status].to_s.split(",").map(&:strip).compact_blank.uniq
        unknown = statuses - RpgClubSuggestion::STATUSES
        return statuses if unknown.empty?

        render json: { error: "unknown status: #{unknown.join(', ')}" }, status: :bad_request
        nil
      end
    end
  end
end
