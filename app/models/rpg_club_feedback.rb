# frozen_string_literal: true

# A member's Feedback on the bot or website (GLOSSARY.md "Feedback"; spec
# api#498): exactly one kind, a Feature Request, a Suggestion or a Bug Report.
# Kept after review with a status: pending until a Superadmin approves it into
# a GitHub issue or rejects it with a reason, or its author withdraws it.
class RpgClubFeedback < ApplicationRecord
  self.table_name = "rpg_club_feedback"
  self.primary_key = "feedback_id"

  KINDS = %w[feature_request suggestion bug_report].freeze
  # How a kind reads in text (bot job summaries, notices).
  KIND_NAMES = { "feature_request" => "Feature Request", "suggestion" => "Suggestion",
                 "bug_report" => "Bug Report" }.freeze
  STATUSES = %w[pending approved rejected withdrawn].freeze
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
  # Statuses members can still upvote (the Feedback Board's default view).
  UPVOTABLE_STATUSES = %w[pending approved].freeze
  # Most upvoted first, then newest.
  BOARD_ORDER = Arel.sql(
    "upvote_count DESC, rpg_club_feedback.created_at DESC, rpg_club_feedback.feedback_id DESC"
  )

  # Latest activity first (the Feedback Board Dashboard Panel): see
  # with_upvotes' `last_activity_at`.
  RECENT_ORDER = Arel.sql("last_activity_at DESC, rpg_club_feedback.feedback_id DESC")

  has_many :upvotes, class_name: "RpgClubFeedbackUpvote", foreign_key: :feedback_id,
    inverse_of: :feedback, dependent: :delete_all

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

  # The label its GitHub issue gets in `repo`.
  def issue_label(repo) = ISSUE_LABELS.fetch(repo).fetch(kind)
end
