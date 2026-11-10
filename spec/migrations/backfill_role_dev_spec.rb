# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261110160000_backfill_role_dev_from_sessions.rb")

# The stored dev role (role_dev) starts false for everyone, so a Superadmin
# would read as non-staff through the bot until a role sync rewrote it. The
# backfill marks members whose latest live session was issued with the dev
# role; a role sync after deploy stays the authority (spec #347).
RSpec.describe BackfillRoleDevFromSessions do
  include ActiveSupport::Testing::TimeHelpers

  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  def session_for(user, is_dev:, created_at: Time.current, expires_at: created_at + 7.days)
    UserSessionToken.create!(user_id: user.user_id, token: SecureRandom.hex(16), is_dev: is_dev,
      created_at: created_at, expires_at: expires_at)
  end

  it "marks a member whose live session was issued with the dev role" do
    dev = create(:user)
    session_for(dev, is_dev: true)

    migrate_up

    expect(dev.reload.role_dev).to be(true)
    expect(dev.admin_or_above?).to be(true)
  end

  it "leaves members without a dev session alone" do
    member = create(:user)
    session_for(member, is_dev: false)
    no_session = create(:user)

    migrate_up

    expect([ member.reload.role_dev, no_session.reload.role_dev ]).to eq([ false, false ])
  end

  it "ignores expired sessions" do
    former = create(:user)
    session_for(former, is_dev: true, created_at: 10.days.ago)

    migrate_up

    expect(former.reload.role_dev).to be(false)
  end

  it "goes by the member's latest live session, so a dev role lost since is not restored" do
    demoted = create(:user)
    session_for(demoted, is_dev: true, created_at: 3.days.ago)
    session_for(demoted, is_dev: false, created_at: 1.day.ago)

    migrate_up

    expect(demoted.reload.role_dev).to be(false)
  end
end
