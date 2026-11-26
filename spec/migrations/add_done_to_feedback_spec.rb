# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261126172000_add_done_to_feedback.rb")

# Feedback Approved before the Done notice existed (ticket api#502) is marked
# notified, so the first refresh does not announce issues closed long ago.
RSpec.describe AddDoneToFeedback do
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    RpgClubFeedback.reset_column_information
  end

  after { RpgClubFeedback.reset_column_information }

  it "marks Approved Feedback as already notified and nothing else" do
    approved = create(:feedback, status: "approved")
    pending_one = create(:feedback)
    migrate(:down)

    migrate(:up)

    expect(approved.reload.done_notified_at).to be_present
    expect(approved.done_at).to be_nil
    expect(pending_one.reload.done_notified_at).to be_nil
  end
end
