# frozen_string_literal: true

require "rails_helper"

# Every list that embeds a game renders its cover/art/logo URLs. Without
# `game: :images` preloaded, GamedbGame#primary_image_url runs one query per
# kind per row (3 per game), and Bullet can't see it: it's a fresh
# `images.where(...)` relation, not an association load. On a member with
# thousands of completions that was ~1,500 queries per 500-row page.
#
# Each example renders several rows and asserts the image lookups stay at a
# single preload query, whatever the row count.
RSpec.describe "game image preloading on list endpoints", type: :request do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:rows) { 3 }

  def covered_game
    create(:game).tap { |game| create(:game_image, :primary, game: game) }
  end

  def image_queries
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:sql].include?("gamedb_game_images") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  def expect_one_image_query(path, params: {})
    sqls = image_queries { get path, params: params, headers: service_headers }
    expect(response).to have_http_status(:ok)
    expect(sqls.size).to eq(1), "expected 1 gamedb_game_images query, got #{sqls.size}:\n#{sqls.join("\n")}"
  end

  it "completions#index" do
    rows.times { create(:completion, user: owner, game: covered_game) }

    expect_one_image_query("/api/v1/users/#{owner.user_id}/completions")
    expect(json.fetch("data").map { |c| c.dig("game", "cover_url") }).to all(be_present)
  end

  it "completions#common" do
    rows.times do
      game = covered_game
      create(:completion, user: owner, game: game)
      create(:completion, user: other, game: game)
    end

    expect_one_image_query("/api/v1/users/#{owner.user_id}/completions/common",
      params: { other_user_id: other.user_id })
    expect(json.fetch("data").length).to eq(rows)
  end

  it "backlog#index" do
    rows.times { create(:backlog_entry, user: owner, game: covered_game) }

    expect_one_image_query("/api/v1/users/#{owner.user_id}/backlog")
  end

  it "favorites#index" do
    rows.times { create(:favorite, user: owner, game: covered_game) }

    expect_one_image_query("/api/v1/users/#{owner.user_id}/favorites")
  end

  it "now_playing#user_index" do
    rows.times { create(:now_playing_entry, user: owner, game: covered_game) }

    expect_one_image_query("/api/v1/users/#{owner.user_id}/now_playing")
  end

  it "now_playing#index" do
    rows.times { create(:now_playing_entry, user: create(:user), game: covered_game) }

    expect_one_image_query("/api/v1/now_playing")
  end

  it "journal#search" do
    rows.times { create(:journal_entry, user: owner, game: covered_game) }

    expect_one_image_query("/api/v1/journal_entries")
  end
end
