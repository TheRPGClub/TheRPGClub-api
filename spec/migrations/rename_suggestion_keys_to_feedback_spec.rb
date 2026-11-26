# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261126170100_rename_suggestion_keys_to_feedback.rb")

# The keys stored for Suggestions follow the rename to Feedback (spec api#498,
# ticket api#499), so flag state, members' pins and panels, and queued bot
# jobs survive it.
RSpec.describe RenameSuggestionKeysToFeedback do
  let(:connection) { ActiveRecord::Base.connection }
  let(:member) { create(:user) }
  let(:now) { Time.current }

  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  it "moves the Feature Flag, its history and members' hidden preference to feedback" do
    FeatureFlag.where(key: %w[suggestions feedback]).delete_all
    FeatureFlag.insert_all!([ { key: "suggestions", state: "off", created_at: now, updated_at: now } ])
    FeatureFlagChange.insert_all!([ { feature_key: "suggestions", from_state: "live", to_state: "off",
                                      changed_by: "1", created_at: now } ])
    MemberFeaturePreference.insert_all!([ { user_id: member.user_id, feature_key: "suggestions", created_at: now } ])

    migrate_up

    expect(FeatureFlag.where(key: "feedback").pluck(:state)).to eq([ "off" ])
    expect(FeatureFlag.where(key: "suggestions")).to be_empty
    expect(FeatureFlagChange.where(feature_key: "feedback").pluck(:to_state)).to eq([ "off" ])
    expect(MemberFeaturePreference.where(user_id: member.user_id).pluck(:feature_key)).to eq([ "feedback" ])
    Features.forget_cached_states!
    expect(Features.state("feedback")).to eq("off")
  end

  it "keeps the old flag's state over a stray new one" do
    FeatureFlag.where(key: %w[suggestions feedback]).delete_all
    FeatureFlag.insert_all!([ { key: "suggestions", state: "live", created_at: now, updated_at: now },
                              { key: "feedback", state: "preview", created_at: now, updated_at: now } ])

    migrate_up

    expect(FeatureFlag.where(key: %w[suggestions feedback]).pluck(:key, :state)).to eq([ %w[feedback live] ])
  end

  it "renames members' Pinned Pages and Dashboard Panels in place" do
    MemberPinnedPage.insert_all!([
      { user_id: member.user_id, page_key: "suggestions", position: 0, created_at: now },
      { user_id: member.user_id, page_key: "suggestion_review", position: 1, created_at: now },
      { user_id: member.user_id, page_key: "news", position: 2, created_at: now }
    ])
    MemberDashboardPanel.insert_all!([
      { user_id: member.user_id, panel_key: "news", position: 0, created_at: now },
      { user_id: member.user_id, panel_key: "suggestions", position: 1, created_at: now }
    ])
    member.update_columns(dashboard_panels_seen_keys: %w[news suggestions codex])

    migrate_up

    expect(MemberPinnedPage.where(user_id: member.user_id).order(:position).pluck(:page_key))
      .to eq(%w[feedback feedback_review news])
    expect(MemberDashboardPanel.where(user_id: member.user_id).order(:position).pluck(:panel_key))
      .to eq(%w[news feedback])
    expect(member.reload.dashboard_panels_seen_keys).to eq(%w[news feedback codex])
  end

  it "moves queued bot jobs to the new kinds with the new payload keys" do
    feedback = create(:feedback, kind: "bug_report")
    BotJob.insert_all!([
      { kind: "suggestion_outcome", summary: "x", status: "queued", created_at: now, updated_at: now,
        payload: { suggestion_id: feedback.feedback_id, outcome: "approved", feature_key: "suggestions" } },
      { kind: "suggestion_submitted", summary: "y", status: "done", created_at: now, updated_at: now,
        payload: { suggestion_id: feedback.feedback_id, created_by: "1", feature_key: "suggestions" } }
    ])

    migrate_up

    outcome = BotJob.find_by!(summary: "x")
    expect(outcome.kind).to eq("feedback_outcome")
    expect(outcome.payload).to eq("feedback_id" => feedback.feedback_id, "kind" => "bug_report",
      "outcome" => "approved", "feature_key" => "feedback")
    expect(BotJob.find_by!(summary: "y")).to have_attributes(kind: "feedback_submitted")
    expect(BotJob.where(kind: %w[suggestion_outcome suggestion_submitted])).to be_empty
  end
end
