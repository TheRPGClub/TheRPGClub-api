# frozen_string_literal: true

# A member's Feedback on the bot or website (GLOSSARY.md "Feedback"; spec
# api#498): exactly one kind, a Feature Request, a Suggestion or a Bug Report.
# Kept after review with a status: pending until a Superadmin approves it into
# a GitHub issue, rejects it with a reason or closes it as a Duplicate of
# another, or its author withdraws it.
class RpgClubFeedback < ApplicationRecord
  self.table_name = "rpg_club_feedback"
  self.primary_key = "feedback_id"

  KINDS = %w[feature_request suggestion bug_report].freeze
  # How a kind reads in text (bot job summaries, notices).
  KIND_NAMES = { "feature_request" => "Feature Request", "suggestion" => "Suggestion",
                 "bug_report" => "Bug Report" }.freeze
  STATUSES = %w[pending approved rejected withdrawn duplicate].freeze
  # Statuses a Duplicate's original may have: Pending, or Approved (Done is
  # Approved with a closed issue).
  ORIGINAL_STATUSES = %w[pending approved].freeze
  # Repos an approval may open its GitHub issue in (`target_repo`).
  TARGET_REPOS = %w[TheRPGClub/TheRPGClub-bot TheRPGClub/TheRPGClub-api TheRPGClub/TheRPGClub-www].freeze
  # The GitHub label an approval puts on its issue, per repo and kind: one the
  # repo has. The bot repo keeps its own labels; api and www use GitHub's
  # defaults.
  ISSUE_LABELS = {
    "TheRPGClub/TheRPGClub-bot" => { "feature_request" => "new feature", "suggestion" => "improvement",
                                     "bug_report" => "bug" },
    "TheRPGClub/TheRPGClub-api" => { "feature_request" => "enhancement", "suggestion" => "enhancement",
                                     "bug_report" => "bug" },
    "TheRPGClub/TheRPGClub-www" => { "feature_request" => "enhancement", "suggestion" => "enhancement",
                                     "bug_report" => "bug" }
  }.freeze
  # The Feedback Board's Open filter: Pending and Approved, Done included
  # (Approved with a closed issue; it shows there marked Done).
  OPEN_STATUSES = %w[pending approved].freeze
  # The Feedback Board's Closed filter.
  CLOSED_STATUSES = %w[rejected duplicate withdrawn].freeze
  # Statuses members can still upvote; Done Feedback is frozen too (upvotable?).
  UPVOTABLE_STATUSES = OPEN_STATUSES
  # Most upvoted first, then newest.
  BOARD_ORDER = Arel.sql(
    "upvote_count DESC, rpg_club_feedback.created_at DESC, rpg_club_feedback.feedback_id DESC"
  )

  # Latest activity first (the Feedback Board Dashboard Panel): see
  # with_upvotes' `last_activity_at`.
  RECENT_ORDER = Arel.sql("last_activity_at DESC, rpg_club_feedback.feedback_id DESC")

  has_many :upvotes, class_name: "RpgClubFeedbackUpvote", foreign_key: :feedback_id,
    inverse_of: :feedback, dependent: :delete_all
  # A Duplicate's original: always the root (an original is never itself a
  # Duplicate when it is set, and Duplicates of a Feedback that later becomes
  # a Duplicate are repointed).
  belongs_to :duplicate_of, class_name: "RpgClubFeedback", optional: true, inverse_of: false

  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  # Adds `upvote_count`, `viewer_upvoted` (whether `viewer_id` upvoted;
  # false when nil) and `last_activity_at` to each row, for FeedbackResource.
  # The latest activity is the newest of the last change to the row
  # (`updated_at`: submitted, reviewed or withdrawn) and the newest upvote.
  # Removing an upvote leaves no trace, so it is not activity.
  def self.with_upvotes(viewer_id)
    counts = "SELECT COUNT(*) FROM rpg_club_feedback_upvotes u " \
             "WHERE u.feedback_id = rpg_club_feedback.feedback_id"
    last_upvote = "SELECT MAX(l.created_at) FROM rpg_club_feedback_upvotes l " \
                  "WHERE l.feedback_id = rpg_club_feedback.feedback_id"
    viewer = sanitize_sql_array([
      "EXISTS (SELECT 1 FROM rpg_club_feedback_upvotes v " \
      "WHERE v.feedback_id = rpg_club_feedback.feedback_id AND v.user_id = ?)", viewer_id.to_s
    ])
    select("rpg_club_feedback.*, (#{counts}) AS upvote_count, #{viewer} AS viewer_upvoted, " \
           "GREATEST(rpg_club_feedback.updated_at, (#{last_upvote})) AS last_activity_at")
  end

  def kind_name = KIND_NAMES.fetch(kind)

  # Approved, and its GitHub issue was last seen closed (`done_at`, kept by
  # record_issue_state).
  def done? = status == "approved" && done_at.present?

  # Upvotes are frozen once Feedback is Done, Rejected, a Duplicate or
  # Withdrawn.
  def upvotable? = UPVOTABLE_STATUSES.include?(status) && !done?

  # Counts per kind for the Feedback Board's kind tabs:
  # { kind => { "open" => n, "closed" => n, "done" => n } }, every kind
  # present. Open includes Done; `done` is the part of Open that is Done.
  def self.board_totals
    totals = KINDS.index_with { { "open" => 0, "closed" => 0, "done" => 0 } }
    group(:kind, :status).count.each do |(kind, status), count|
      next unless totals.key?(kind)

      totals[kind][OPEN_STATUSES.include?(status) ? "open" : "closed"] += count
    end
    where(status: "approved").where.not(done_at: nil).group(:kind).count.each do |kind, count|
      totals[kind]["done"] = count if totals.key?(kind)
    end
    totals
  end

  # Called with each issue state Github::IssueStateRefreshJob reads. Approved
  # Feedback on that issue becomes Done when it is closed (and its author is
  # told, once ever: notify_done!) and Open again when it is reopened.
  # nil (unknown) changes nothing.
  def self.record_issue_state(repo, number, state)
    on_issue = where(status: "approved", target_repo: repo, github_issue_number: number)
    case state
    when "open"
      on_issue.where.not(done_at: nil).update_all(done_at: nil)
    when "closed"
      on_issue.where(done_at: nil).update_all(done_at: Time.current)
      on_issue.where(done_notified_at: nil).find_each(&:notify_done!)
    end
  end

  # Queues the `feedback_outcome` job (outcome `done`) telling the author
  # their Feedback is Done, unless one was already queued. Payload as the
  # review outcomes: { feedback_id, kind, outcome, created_by, title,
  # github_issue_number, github_issue_url, rejection_reason }.
  def notify_done!
    self.class.transaction do
      claimed = self.class.where(feedback_id: feedback_id, done_notified_at: nil)
        .update_all(done_notified_at: Time.current)
      next if claimed.zero?

      BotJob.enqueue!(
        kind: "feedback_outcome",
        summary: %(Announce that the #{kind_name} "#{title}" is done),
        payload: {
          feedback_id: feedback_id, kind: kind, outcome: "done", created_by: created_by, title: title,
          github_issue_number: github_issue_number, github_issue_url: github_issue_url, rejection_reason: nil
        }
      )
    end
  end

  # Follows a chain of Duplicates to the Feedback they all duplicate (itself
  # when it is not a Duplicate). Stops at a loop, should one ever exist.
  def root_original
    record = self
    seen = Set[feedback_id]
    while record.status == "duplicate" && record.duplicate_of && seen.add?(record.duplicate_of_id)
      record = record.duplicate_of
    end
    record
  end

  # Moves this Feedback's upvotes to `original`, keeping one per member (an
  # upvote the member already has there wins). Returns how many moved.
  def move_upvotes_to(original)
    moved = self.class.connection.exec_update(self.class.sanitize_sql_array([ <<~SQL, original.feedback_id, feedback_id ]))
      INSERT INTO rpg_club_feedback_upvotes (feedback_id, user_id, created_at)
      SELECT ?, user_id, created_at FROM rpg_club_feedback_upvotes WHERE feedback_id = ?
      ON CONFLICT (feedback_id, user_id) DO NOTHING
    SQL
    upvotes.delete_all
    moved
  end

  # The label its GitHub issue gets in `repo`.
  def issue_label(repo) = ISSUE_LABELS.fetch(repo).fetch(kind)
end
