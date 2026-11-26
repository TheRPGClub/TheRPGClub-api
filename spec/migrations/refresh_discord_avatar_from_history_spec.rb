# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261126160000_refresh_discord_avatar_from_history.rb")

# A login's Discord avatar hash goes stale when the member changes their
# avatar; the bot's history has the current one.
RSpec.describe RefreshDiscordAvatarFromHistory do
  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  let(:old_hash) { "0" * 32 }
  let(:new_hash) { "a_#{'f' * 32}" }

  it "takes the bot's latest hash when it changed after the login" do
    user = create(:user, discord_avatar: old_hash, last_fetched_at: 3.days.ago)
    create(:avatar_history_event, user: user, avatar_hash: "1" * 32, changed_at: 2.days.ago)
    create(:avatar_history_event, user: user, avatar_hash: new_hash, changed_at: 1.day.ago)

    migrate_up

    expect(user.reload.discord_avatar).to eq(new_hash)
  end

  it "fills the hash for a member who never logged in" do
    user = create(:user, discord_avatar: nil, last_fetched_at: nil)
    create(:avatar_history_event, user: user, avatar_hash: new_hash, changed_at: 1.day.ago)

    migrate_up

    expect(user.reload.discord_avatar).to eq(new_hash)
  end

  it "keeps a login newer than the last logged change" do
    user = create(:user, discord_avatar: old_hash, last_fetched_at: 1.hour.ago)
    create(:avatar_history_event, user: user, avatar_hash: new_hash, changed_at: 1.day.ago)

    migrate_up

    expect(user.reload.discord_avatar).to eq(old_hash)
  end

  it "skips a logged hash that isn't one Discord issues" do
    user = create(:user, discord_avatar: old_hash, last_fetched_at: 3.days.ago)
    create(:avatar_history_event, user: user, avatar_hash: "not-a-hash", changed_at: 1.day.ago)

    migrate_up

    expect(user.reload.discord_avatar).to eq(old_hash)
  end
end
