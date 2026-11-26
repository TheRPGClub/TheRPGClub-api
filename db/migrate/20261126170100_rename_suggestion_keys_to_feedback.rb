# frozen_string_literal: true

# Feedback Board (spec api#498, ticket api#499): the keys stored for
# Suggestions follow the rename, so nothing members or staff set is lost.
#
# - Feature `suggestions` -> `feedback`: its Feature Flag (Off/Preview/Live
#   state), its change history and members' "hide this Feature" preferences.
# - Pinned Pages `suggestions` -> `feedback`, `suggestion_review` ->
#   `feedback_review`.
# - Dashboard Panel `suggestions` -> `feedback`, in members' panels and in the
#   panels they have seen (so it does not turn New).
# - Bot jobs `suggestion_submitted` / `suggestion_outcome` ->
#   `feedback_submitted` / `feedback_outcome`, every one (the /admin activity
#   list included), with each payload's `suggestion_id` renamed `feedback_id`,
#   the Feedback's `kind` added and its `feature_key` renamed, so jobs still
#   queued are delivered under the new kinds.
class RenameSuggestionKeysToFeedback < ActiveRecord::Migration[8.1]
  FEATURE = %w[suggestions feedback].freeze
  PAGES = { "suggestions" => "feedback", "suggestion_review" => "feedback_review" }.freeze
  PANEL = %w[suggestions feedback].freeze
  JOB_KINDS = { "suggestion_submitted" => "feedback_submitted", "suggestion_outcome" => "feedback_outcome" }.freeze

  def up
    rename_keys(FEATURE, PAGES, PANEL, JOB_KINDS)
    execute <<~SQL
      UPDATE bot_jobs j
      SET payload = (j.payload - 'suggestion_id')
        || jsonb_build_object('feedback_id', j.payload -> 'suggestion_id', 'kind', f.kind)
        || CASE WHEN j.payload ? 'feature_key' THEN '{"feature_key":"feedback"}'::jsonb ELSE '{}'::jsonb END
      FROM rpg_club_feedback f
      WHERE j.kind IN (#{quoted(JOB_KINDS.values)}) AND j.payload ? 'suggestion_id'
        AND f.feedback_id = (j.payload ->> 'suggestion_id')::bigint
    SQL
  end

  def down
    rename_keys(FEATURE.reverse, PAGES.invert, PANEL.reverse, JOB_KINDS.invert)
    execute <<~SQL
      UPDATE bot_jobs
      SET payload = (payload - 'feedback_id' - 'kind')
        || jsonb_build_object('suggestion_id', payload -> 'feedback_id')
        || CASE WHEN payload ? 'feature_key' THEN '{"feature_key":"suggestions"}'::jsonb ELSE '{}'::jsonb END
      WHERE kind IN (#{quoted(JOB_KINDS.keys)}) AND payload ? 'feedback_id'
    SQL
  end

  private

  def rename_keys(feature, pages, panel, job_kinds)
    from, to = feature
    # The new key has no state of its own yet; if it somehow does, the old
    # key's state wins.
    execute "DELETE FROM feature_flags WHERE key = #{q(to)} AND EXISTS " \
            "(SELECT 1 FROM feature_flags WHERE key = #{q(from)})"
    execute "UPDATE feature_flags SET key = #{q(to)} WHERE key = #{q(from)}"
    execute "UPDATE feature_flag_changes SET feature_key = #{q(to)} WHERE feature_key = #{q(from)}"
    rename_member_key(:member_feature_preferences, :feature_key, from, to)

    pages.each { |old, new| rename_member_key(:member_pinned_pages, :page_key, old, new) }

    old_panel, new_panel = panel
    rename_member_key(:member_dashboard_panels, :panel_key, old_panel, new_panel)
    execute "UPDATE rpg_club_users SET dashboard_panels_seen_keys = " \
            "array_replace(dashboard_panels_seen_keys, #{q(old_panel)}, #{q(new_panel)}) " \
            "WHERE #{q(old_panel)} = ANY (dashboard_panels_seen_keys)"

    job_kinds.each do |old, new|
      execute "UPDATE bot_jobs SET kind = #{q(new)} WHERE kind = #{q(old)}"
    end
  end

  # Renames a per-member key, unique per (user_id, key): a member who already
  # has the new key keeps it and loses the old one.
  def rename_member_key(table, column, from, to)
    execute <<~SQL
      DELETE FROM #{table} o WHERE o.#{column} = #{q(from)} AND EXISTS
        (SELECT 1 FROM #{table} n WHERE n.user_id = o.user_id AND n.#{column} = #{q(to)})
    SQL
    execute "UPDATE #{table} SET #{column} = #{q(to)} WHERE #{column} = #{q(from)}"
  end

  def q(value) = connection.quote(value)

  def quoted(values) = values.map { |value| q(value) }.join(", ")
end
