# frozen_string_literal: true

module Api
  module V1
    # The Feedback Board (GLOSSARY.md "Feedback"; spec api#498): members file
    # Feedback of one kind and upvote it; a Superadmin reviews it.
    class FeedbackController < ApplicationController
      feature :feedback

      # Columns a caller may set on create. Status and the review columns are
      # server-managed; a member's authorship comes from their session.
      WRITABLE = (%w[kind title details created_by created_by_name] + RpgClubFeedback::BUG_FIELDS).freeze
      # What the author may change while it is Pending (api#500); the bug
      # fields only on a Bug Report.
      EDITABLE = (%w[title details] + RpgClubFeedback::BUG_FIELDS).freeze
      # How long an approval in progress blocks another; longer than its
      # GitHub calls can take (three, each with Github::Client::TIMEOUT_SECONDS).
      APPROVAL_WINDOW = 2.minutes
      # Groups for the Feedback Board's status filter: `open` (Pending and
      # Approved, Done included), `closed` (Rejected, Duplicate, Withdrawn),
      # alongside `done` (Approved and Done) and single statuses.
      STATUS_GROUPS = { "open" => RpgClubFeedback::OPEN_STATUSES,
                        "closed" => RpgClubFeedback::CLOSED_STATUSES }.freeze
      # The index's orders: `board` (the default: most upvoted, then newest)
      # and `recent` (latest activity first, for the Feedback Board
      # Dashboard Panel).
      SORTS = { "board" => RpgClubFeedback::BOARD_ORDER, "recent" => RpgClubFeedback::RECENT_ORDER }.freeze

      before_action :require_superadmin!, only: %i[approve reject duplicate change_kind]
      before_action :require_member_or_staff!, only: %i[create upvote remove_upvote]
      before_action :require_member!, only: %i[withdraw upvote remove_upvote]

      # GET /api/v1/feedback?kind=&status=&sort=board|recent&page=&per=
      #
      # The Feedback Board shows one kind at a time with an Open / Closed
      # filter: `kind=bug_report&status=open`. `meta.totals` counts every
      # kind's Open, Closed and Done Feedback (unfiltered) for the tabs.
      def index
        kinds = kind_filter
        return if performed?

        statuses, done = status_filter
        return if performed?

        order = sort_param(SORTS, default: "board")
        return if performed?

        scope = viewer_scope
        scope = scope.where(kind: kinds) if kinds
        scope = filter_statuses(scope, statuses, done) if statuses
        render_collection(scope, resource: FeedbackResource, default_order: order,
          prepare: ->(records) { FeedbackResource.issue_states(records) },
          meta: { totals: RpgClubFeedback.board_totals })
      end

      def show
        render_feedback(params[:id])
      end

      # Members role holders, staff, or the bot. A member is always the author, and
      # their submission asks the bot to ping the bot dev; the bot pings
      # inline for its own /feedback submissions, so a service create
      # enqueues nothing.
      def create
        attrs = request_data.slice(*WRITABLE)
        attrs.except!(*RpgClubFeedback::BUG_FIELDS) unless attrs["kind"] == "bug_report"
        record = RpgClubFeedback.transaction do
          if current_principal.discord_user?
            attrs.merge!("created_by" => current_principal.id, "created_by_name" => author_name)
          end
          feedback = RpgClubFeedback.new(attrs)
          feedback.save!(context: :filing)
          enqueue_submitted_ping(feedback) if current_principal.discord_user?
          feedback
        end
        render_feedback(record.feedback_id, status: :created)
      end

      # The author changes their own Pending Feedback (api#500): title,
      # details and, on a Bug Report, its bug fields (the screenshot has its
      # own endpoint). Anyone else is refused; reviewed or withdrawn Feedback
      # is a 409.
      def update
        feedback = RpgClubFeedback.find(params[:id])
        return render json: { error: "forbidden" }, status: :forbidden unless own?(feedback)

        attrs = request_data.slice(*EDITABLE)
        feedback.with_lock do
          unless feedback.pending?
            return render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
          end

          attrs.except!(*RpgClubFeedback::BUG_FIELDS) unless feedback.bug_report?
          feedback.assign_attributes(attrs)
          feedback.save!(context: :filing)
        end
        render_feedback(feedback.feedback_id)
      end

      # Superadmin (or the bot, for a Discord reviewer named in `reviewed_by`).
      # Opens a GitHub issue in `target_repo` (one of
      # RpgClubFeedback::TARGET_REPOS) as the bot did, stores it and asks the
      # bot to announce the outcome. A GitHub failure changes nothing.
      #
      # No lock or transaction is held across the GitHub calls. A short lock
      # marks the approval as in progress (a second approve meanwhile is a 409
      # `approval_in_progress`), the issue is opened, then a second short lock
      # re-checks Pending and stores it. The issue body carries a marker, and an
      # issue already carrying it is reused, so a retry after a lost GitHub
      # response does not open a duplicate.
      def approve
        data = request_data
        repo = data["target_repo"].to_s.strip
        unless RpgClubFeedback::TARGET_REPOS.include?(repo)
          return render json: { error: "target_repo must be one of #{RpgClubFeedback::TARGET_REPOS.join(', ')}" },
            status: :unprocessable_content
        end

        feedback = RpgClubFeedback.find(params[:id])
        mark = claim_approval(feedback)
        return unless mark

        begin
          issue = find_or_open_issue(feedback, repo)
          Github::IssueStateCache.store(repo, issue.number, issue.state)
          review(data) do
            { status: "approved", target_repo: repo, github_issue_number: issue.number, github_issue_url: issue.url,
              approval_started_at: nil }
          end
        ensure
          release_approval(feedback, mark)
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

      # Superadmin (or the bot, as for approve). Closes Pending Feedback as a
      # Duplicate of `original_id`, resolved to its root original, which must
      # be Pending or Approved (Done included) and of any kind. Its upvotes
      # move to the original, one per member, and Duplicates of it are
      # repointed to the original. Approved Feedback is refused (409): close
      # its GitHub issue instead. Renders as reject does.
      def duplicate
        data = request_data
        feedback = RpgClubFeedback.find(params[:id])
        original = RpgClubFeedback.find_by(feedback_id: data["original_id"].to_s.presence)&.root_original
        unless original
          return render json: { error: "original_id must be an existing Feedback" }, status: :unprocessable_content
        end
        if original.feedback_id == feedback.feedback_id
          return render json: { error: "feedback cannot be a duplicate of itself" }, status: :unprocessable_content
        end

        job = nil
        RpgClubFeedback.transaction do
          locked = RpgClubFeedback.where(feedback_id: [ feedback.feedback_id, original.feedback_id ])
            .order(:feedback_id).lock.index_by(&:feedback_id)
          feedback = locked.fetch(feedback.feedback_id)
          original = locked.fetch(original.feedback_id)
          unless feedback.status == "pending"
            return render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
          end
          unless RpgClubFeedback::ORIGINAL_STATUSES.include?(original.status)
            return render json: { error: "the original is #{original.status}; it must be pending or approved" },
              status: :unprocessable_content
          end

          feedback.move_upvotes_to(original)
          RpgClubFeedback.where(duplicate_of_id: feedback.feedback_id).update_all(duplicate_of_id: original.feedback_id)
          feedback.update!(status: "duplicate", duplicate_of: original, reviewed_by: reviewer_id(data),
            reviewed_at: Time.current)
          job = enqueue_outcome(feedback, original: original)
        end
        render json: {
          data: FeedbackResource.new(viewer_scope.find(feedback.feedback_id)).serializable_hash,
          meta: { outcome_job_id: job.id }
        }
      end

      # Superadmin (or the bot). Sets Pending Feedback's `kind`. Staff are
      # reshaping it, not filing it, so a kind's required fields (a Bug
      # Report's) are not checked.
      def change_kind
        kind = request_data["kind"].to_s
        unless RpgClubFeedback::KINDS.include?(kind)
          return render json: { error: "kind must be one of #{RpgClubFeedback::KINDS.join(', ')}" },
            status: :unprocessable_content
        end

        feedback = RpgClubFeedback.find(params[:id])
        feedback.with_lock do
          unless feedback.status == "pending"
            return render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
          end

          feedback.kind = kind
          feedback.save!(validate: false)
        end
        render_feedback(feedback.feedback_id)
      end

      # The author takes back their own Pending Feedback. Anyone else
      # (staff and the service included) is refused; a reviewed or already
      # withdrawn Feedback is a 409.
      def withdraw
        feedback = RpgClubFeedback.find(params[:id])
        return render json: { error: "forbidden" }, status: :forbidden unless feedback.created_by == current_principal.id

        feedback.with_lock do
          unless feedback.status == "pending"
            return render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
          end

          feedback.update!(status: "withdrawn")
        end
        render_feedback(feedback.feedback_id)
      end

      # A member's upvote, at most one each (repeating it is a no-op). Only
      # Pending and Approved Feedback that is not Done takes upvotes.
      def upvote
        feedback = RpgClubFeedback.find(params[:id])
        return render_frozen(feedback) unless feedback.upvotable?

        RpgClubFeedbackUpvote.insert(
          { feedback_id: feedback.feedback_id, user_id: current_principal.id },
          unique_by: :ux_rpg_club_feedback_upvotes_feedback_user
        )
        render_feedback(feedback.feedback_id)
      end

      # Removes the member's upvote, if any. Upvotes are frozen as upvote's
      # are: Done, Rejected, Duplicate and Withdrawn Feedback keeps them.
      def remove_upvote
        feedback = RpgClubFeedback.find(params[:id])
        return render_frozen(feedback) unless feedback.upvotable?

        feedback.upvotes.where(user_id: current_principal.id).delete_all
        render_feedback(feedback.feedback_id)
      end

      private

      # Locks the Feedback, 409s unless it is pending, applies the block's
      # columns plus the reviewer and time, and enqueues the outcome job, all in
      # one short transaction (the block makes no external calls). Renders
      # `{ data: Feedback, meta: { outcome_job_id } }`.
      def review(data)
        feedback = RpgClubFeedback.find(params[:id])
        job = nil
        feedback.with_lock do
          unless feedback.status == "pending"
            return render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
          end

          feedback.update!(**yield, reviewed_by: reviewer_id(data), reviewed_at: Time.current)
          job = enqueue_outcome(feedback)
        end
        render json: {
          data: FeedbackResource.new(viewer_scope.find(feedback.feedback_id)).serializable_hash,
          meta: { outcome_job_id: job.id }
        }
      end

      # Marks Pending Feedback as being approved, under a short row lock,
      # and returns the mark's time. Renders 409 and returns nil when it is not
      # Pending or another approval started within APPROVAL_WINDOW (an older
      # mark is from a request that died, and is taken over).
      def claim_approval(feedback)
        feedback.with_lock do
          unless feedback.status == "pending"
            render json: { error: "feedback is #{feedback.status}, not pending" }, status: :conflict
            return nil
          end
          if feedback.approval_started_at&.after?(APPROVAL_WINDOW.ago)
            render json: { error: "approval_in_progress", message: "this feedback is already being approved" },
              status: :conflict
            return nil
          end

          feedback.update_columns(approval_started_at: Time.current.floor(6))
          feedback.approval_started_at
        end
      end

      # Clears this request's mark if it is still there (a finished approval
      # already cleared it; a takeover replaced it).
      def release_approval(feedback, mark)
        RpgClubFeedback.where(feedback_id: feedback.feedback_id, approval_started_at: mark)
          .update_all(approval_started_at: nil)
      end

      def find_or_open_issue(feedback, repo)
        client = Github::Client.new
        marker = issue_marker(feedback)
        client.find_issue_by_marker(repo: repo, marker: marker, since: feedback.created_at) ||
          client.create_issue(repo: repo, title: feedback.title, body: "#{issue_body(feedback)}\n\n#{marker}",
            labels: [ feedback.issue_label(repo) ])
      end

      # Hidden in the rendered issue; identifies the Feedback an issue is for.
      def issue_marker(feedback)
        "<!-- rpgclub-feedback:#{feedback.feedback_id} -->"
      end

      # A member reviews as themselves; the bot names the Discord reviewer.
      def reviewer_id(data)
        current_principal.discord_user? ? current_principal.id : data["reviewed_by"].presence&.to_s
      end

      # See RpgClubFeedback#issue_body (a Bug Report lays out its fields).
      def issue_body(feedback) = feedback.issue_body

      # Whether the signed-in member wrote it (the service never did).
      def own?(feedback)
        current_principal.discord_user? && feedback.created_by == current_principal.id
      end

      # Payload (kind feedback_outcome): { feedback_id, kind, outcome, created_by,
      # title, github_issue_number, github_issue_url, rejection_reason }, plus
      # { duplicate_of_id, duplicate_of_title } for a Duplicate.
      # Enqueued for the bot's own reviews too: the job is the announcement.
      def enqueue_outcome(feedback, original: nil)
        payload = {
          feedback_id: feedback.feedback_id, kind: feedback.kind, outcome: feedback.status,
          created_by: feedback.created_by, title: feedback.title, github_issue_number: feedback.github_issue_number,
          github_issue_url: feedback.github_issue_url, rejection_reason: feedback.rejection_reason
        }
        outcome = feedback.status
        if original
          payload.merge!(duplicate_of_id: original.feedback_id, duplicate_of_title: original.title)
          outcome = %(marked a duplicate of "#{original.title}")
        end
        BotJob.enqueue!(
          kind: "feedback_outcome",
          summary: %(Announce that the #{feedback.kind_name} "#{feedback.title}" was #{outcome}),
          payload: payload,
          requested_by: requester_id
        )
      end

      # Upvotes and withdraw act as a signed-in member; the service has no
      # member identity to act as.
      def require_member!
        gate_or_forbid(current_principal.discord_user?)
      end

      def viewer_scope
        RpgClubFeedback.with_upvotes(current_principal.discord_user? ? current_principal.id : nil)
      end

      def render_feedback(id, status: :ok)
        render json: { data: FeedbackResource.new(viewer_scope.find(id)).serializable_hash }, status: status
      end

      def author_name
        RpgClubUser.where(user_id: current_principal.id).pick(:username) || current_principal.username
      end

      # Payload (kind feedback_submitted): { feedback_id, kind, created_by }.
      def enqueue_submitted_ping(feedback)
        BotJob.enqueue!(
          kind: "feedback_submitted",
          summary: %(Announce the new #{feedback.kind_name} "#{feedback.title}"),
          payload: { feedback_id: feedback.feedback_id, kind: feedback.kind, created_by: feedback.created_by },
          requested_by: current_principal.id
        )
      end

      # 409 for an upvote change on Feedback whose upvotes are frozen.
      def render_frozen(feedback)
        state = feedback.done? ? "done" : feedback.status
        render json: { error: "#{state} feedback cannot be upvoted" }, status: :conflict
      end

      # `?status=open` or `?status=pending,approved`: returns [statuses, done]
      # (done: whether `done` was asked for), or nil (every status) when
      # absent. 400 for a value that is neither a status, a group nor `done`.
      def status_filter
        return if params[:status].blank?

        values = params[:status].to_s.split(",").map(&:strip).compact_blank.uniq
        unknown = values - RpgClubFeedback::STATUSES - STATUS_GROUPS.keys - %w[done]
        unless unknown.empty?
          render json: { error: "unknown status: #{unknown.join(', ')}" }, status: :bad_request
          return
        end

        statuses = values.flat_map { |value| STATUS_GROUPS.fetch(value, value == "done" ? [] : [ value ]) }.uniq
        [ statuses, values.include?("done") ]
      end

      def filter_statuses(scope, statuses, done)
        filtered = scope.where(status: statuses)
        filtered = filtered.or(scope.where(status: "approved").where.not(done_at: nil)) if done
        filtered
      end

      # `?kind=bug_report` (comma-separated for several): nil (every kind)
      # when absent; 400 for a kind outside RpgClubFeedback::KINDS.
      def kind_filter
        return if params[:kind].blank?

        kinds = params[:kind].to_s.split(",").map(&:strip).compact_blank.uniq
        unknown = kinds - RpgClubFeedback::KINDS
        return kinds if unknown.empty?

        render json: { error: "unknown kind: #{unknown.join(', ')}" }, status: :bad_request
        nil
      end
    end
  end
end
