# frozen_string_literal: true

# A member's proposal for the bot or website. Kept after review with a status
# (web parity 2, #318): pending until a Superadmin approves it into a GitHub
# issue or rejects it with a reason, or its author withdraws it.
class RpgClubSuggestion < ApplicationRecord
  self.table_name = "rpg_club_suggestions"
  self.primary_key = "suggestion_id"

  STATUSES = %w[pending approved rejected withdrawn].freeze
  # Repos an approval may open its GitHub issue in (`target_repo`).
  TARGET_REPOS = %w[TheRPGClub/TheRPGClub-bot TheRPGClub/TheRPGClub-api TheRPGClub/TheRPGClub-www].freeze
  # Statuses members can still upvote (the Suggestion Board's default view).
  UPVOTABLE_STATUSES = %w[pending approved].freeze
  # Most upvoted first, then newest.
  BOARD_ORDER = Arel.sql(
    "upvote_count DESC, rpg_club_suggestions.created_at DESC, rpg_club_suggestions.suggestion_id DESC"
  )

  # Latest activity first (the Suggestion Board Dashboard Panel): see
  # with_upvotes' `last_activity_at`.
  RECENT_ORDER = Arel.sql("last_activity_at DESC, rpg_club_suggestions.suggestion_id DESC")

  has_many :upvotes, class_name: "RpgClubSuggestionUpvote", foreign_key: :suggestion_id,
    inverse_of: :suggestion, dependent: :delete_all

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Adds `upvote_count`, `viewer_upvoted` (whether `viewer_id` upvoted;
  # false when nil) and `last_activity_at` to each row, for SuggestionResource.
  # The latest activity is the newest of the last change to the row
  # (`updated_at`: submitted, reviewed or withdrawn) and the newest upvote.
  # Removing an upvote leaves no trace, so it is not activity.
  def self.with_upvotes(viewer_id)
    counts = "SELECT COUNT(*) FROM rpg_club_suggestion_upvotes u " \
             "WHERE u.suggestion_id = rpg_club_suggestions.suggestion_id"
    last_upvote = "SELECT MAX(l.created_at) FROM rpg_club_suggestion_upvotes l " \
                  "WHERE l.suggestion_id = rpg_club_suggestions.suggestion_id"
    viewer = sanitize_sql_array([
      "EXISTS (SELECT 1 FROM rpg_club_suggestion_upvotes v " \
      "WHERE v.suggestion_id = rpg_club_suggestions.suggestion_id AND v.user_id = ?)", viewer_id.to_s
    ])
    select("rpg_club_suggestions.*, (#{counts}) AS upvote_count, #{viewer} AS viewer_upvoted, " \
           "GREATEST(rpg_club_suggestions.updated_at, (#{last_upvote})) AS last_activity_at")
  end
end
