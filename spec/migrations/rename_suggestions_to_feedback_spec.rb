# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261126170000_rename_suggestions_to_feedback.rb")

# Suggestions become Feedback (spec api#498, ticket api#499): the tables are
# renamed and the multi-select labels become one kind.
RSpec.describe RenameSuggestionsToFeedback do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  ensure
    [ RpgClubFeedback, RpgClubFeedbackUpvote ].each(&:reset_column_information)
  end

  def insert_suggestion(labels)
    connection.select_value(<<~SQL)
      INSERT INTO rpg_club_suggestions (title, labels)
      VALUES (#{connection.quote("Labels #{labels.inspect}")}, #{connection.quote(labels)})
      RETURNING suggestion_id
    SQL
  end

  before { migrate(:down) }

  it "gives each row the kind its labels map to" do
    ids = {
      bug: insert_suggestion("Bug"),
      bug_and_feature: insert_suggestion("New Feature, Bug"),
      feature: insert_suggestion("New Feature"),
      feature_and_improvement: insert_suggestion("Improvement,New Feature"),
      improvement: insert_suggestion("Improvement"),
      free_form: insert_suggestion("ux, bugfix"),
      none: insert_suggestion(nil)
    }

    migrate(:up)

    kinds = RpgClubFeedback.where(feedback_id: ids.values).pluck(:feedback_id, :kind).to_h
    expect(ids.transform_values { |id| kinds.fetch(id) }).to eq(
      bug: "bug_report", bug_and_feature: "bug_report", feature: "feature_request",
      feature_and_improvement: "feature_request", improvement: "suggestion", free_form: "suggestion",
      none: "suggestion"
    )
  end

  it "prints a count per kind" do
    insert_suggestion("Bug")
    2.times { insert_suggestion("New Feature") }

    expect {
      ActiveRecord::Migration.verbose = true
      described_class.new.migrate(:up)
    }.to output(/Feedback kinds: feature_request=2, suggestion=0, bug_report=1/).to_stdout
  ensure
    ActiveRecord::Migration.verbose = false
    [ RpgClubFeedback, RpgClubFeedbackUpvote ].each(&:reset_column_information)
  end

  it "keeps upvotes and drops labels and the review sessions" do
    member = create(:user)
    id = insert_suggestion("Bug")
    connection.execute("INSERT INTO rpg_club_suggestion_upvotes (suggestion_id, user_id) " \
                       "VALUES (#{id}, #{connection.quote(member.user_id)})")

    migrate(:up)

    expect(RpgClubFeedbackUpvote.where(feedback_id: id).pluck(:user_id)).to eq([ member.user_id ])
    expect(connection.column_exists?(:rpg_club_feedback, :labels)).to be(false)
    expect(connection.table_exists?(:rpg_club_suggestion_review_sessions)).to be(false)
    expect(connection.table_exists?(:rpg_club_suggestions)).to be(false)
  end

  it "keeps numbering new Feedback after the old ids" do
    id = insert_suggestion(nil)

    migrate(:up)

    expect(create(:feedback).feedback_id).to be > id
  end
end
