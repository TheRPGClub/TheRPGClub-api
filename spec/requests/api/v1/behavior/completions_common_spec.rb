# frozen_string_literal: true

require "rails_helper"

# Behavior spec for GET /api/v1/users/:user_id/completions/common — the games
# two members have both completed (the bot's `/game-completion common`).
RSpec.describe "api/v1/completions common behavior", type: :request do
  let(:left) { create(:user) }
  let(:right) { create(:user) }
  let(:viewer) { create(:user) }
  let(:path) { "/api/v1/users/#{left.user_id}/completions/common" }

  def common(**params)
    get path, params: { other_user_id: right.user_id, **params }, headers: auth_headers_for(viewer)
    expect(response).to have_http_status(:ok)
    json
  end

  def game_ids(body) = body.fetch("data").map { |row| row.fetch("gamedb_game_id") }

  # `completed_at` has a column default, so an undated entry is nulled explicitly.
  def complete(user, game, completed_at: nil, **attrs)
    entry = create(:completion, user: user, game: game, **attrs)
    entry.update_columns(completed_at: completed_at)
    entry
  end

  def both_completed(game, left_at: nil, right_at: nil, **attrs)
    complete(left, game, completed_at: left_at, **attrs)
    complete(right, game, completed_at: right_at, **attrs)
  end

  it "returns only games both members completed, with each side's latest entry and count" do
    shared = create(:game)
    old_left = create(:completion, user: left, game: shared, completed_at: Time.utc(2019, 1, 1))
    new_left = create(:completion, user: left, game: shared, completed_at: Time.utc(2021, 3, 3))
    right_entry = create(:completion, user: right, game: shared, completed_at: Time.utc(2022, 4, 4))
    create(:completion, user: left)               # left only
    create(:completion, user: right)              # right only
    create(:completion, user: viewer, game: shared) # a third member doesn't count

    body = common

    expect(game_ids(body)).to eq([ shared.game_id ])
    row = body.fetch("data").first
    expect(row.dig("game", "game_id")).to eq(shared.game_id)
    expect(Time.zone.parse(row.fetch("latest_shared_date"))).to eq(Time.utc(2022, 4, 4))
    expect(row.dig("left", "count")).to eq(2)
    expect(row.dig("left", "latest", "completion_id")).to eq(new_left.completion_id)
    expect(row.dig("left", "latest", "game", "game_id")).to eq(shared.game_id)
    expect(row.dig("right", "count")).to eq(1)
    expect(row.dig("right", "latest", "completion_id")).to eq(right_entry.completion_id)
    expect(old_left.completion_id).not_to eq(row.dig("left", "latest", "completion_id"))
    expect(body.fetch("meta")).to include(
      "count" => 1, "page" => 1, "pages" => 1,
      "left_user_id" => left.user_id, "right_user_id" => right.user_id
    )
  end

  it "picks a dated entry over an undated one as a side's latest" do
    game = create(:game)
    dated = complete(left, game, completed_at: Time.utc(2020, 1, 1))
    complete(left, game)
    complete(right, game)

    row = common.fetch("data").first

    expect(row.dig("left", "latest", "completion_id")).to eq(dated.completion_id)
    expect(Time.zone.parse(row.fetch("latest_shared_date"))).to eq(Time.utc(2020, 1, 1))
  end

  it "renders a null latest_shared_date when neither side has a date" do
    both_completed(create(:game))

    expect(common.dig("data", 0, "latest_shared_date")).to be_nil
  end

  describe "filters (a game matches when either member's entries match)" do
    it "filters by year" do
      left_year = create(:game)
      both_completed(left_year, left_at: Time.utc(2020, 6, 1), right_at: Time.utc(2023, 1, 1))
      right_year = create(:game)
      both_completed(right_year, left_at: Time.utc(2021, 1, 1), right_at: Time.utc(2020, 2, 2))
      both_completed(create(:game), left_at: Time.utc(2018, 1, 1), right_at: Time.utc(2018, 1, 1))

      body = common(year: "2020")

      expect(game_ids(body)).to contain_exactly(left_year.game_id, right_year.game_id)
      expect(body.dig("meta", "count")).to eq(2)
    end

    it "filters by year=unknown to games with any undated entry" do
      undated = create(:game)
      both_completed(undated, left_at: Time.utc(2020, 1, 1), right_at: nil)
      both_completed(create(:game), left_at: Time.utc(2020, 1, 1), right_at: Time.utc(2020, 1, 1))

      expect(game_ids(common(year: "unknown"))).to eq([ undated.game_id ])
    end

    it "filters by platform_id" do
      platform = create(:platform)
      on_platform = create(:game)
      create(:completion, user: left, game: on_platform)
      create(:completion, user: right, game: on_platform, platform: platform)
      both_completed(create(:game), platform: create(:platform))

      expect(game_ids(common(platform_id: platform.platform_id))).to eq([ on_platform.game_id ])
    end

    it "filters by q on the game title, case-insensitively" do
      match = create(:game, title: "cmnq Hidden Realm #{SecureRandom.hex(4)}")
      both_completed(match)
      both_completed(create(:game))

      expect(game_ids(common(q: "CMNQ hidden"))).to eq([ match.game_id ])
    end
  end

  describe "sorting" do
    let(:prefix) { "cmns #{SecureRandom.hex(4)}" }
    let!(:alpha) { create(:game, title: "#{prefix} alpha") }
    let!(:bravo) { create(:game, title: "#{prefix} Bravo") }
    let!(:charlie) { create(:game, title: "#{prefix} charlie") }
    let!(:delta) { create(:game, title: "#{prefix} delta") }

    before do
      both_completed(alpha, left_at: Time.utc(2020, 1, 1), right_at: Time.utc(2021, 1, 1))  # 2021
      both_completed(bravo, left_at: Time.utc(2023, 1, 1), right_at: Time.utc(2019, 1, 1))  # 2023
      both_completed(charlie)                                                                # undated
      both_completed(delta, left_at: Time.utc(2022, 1, 1), right_at: nil)                   # 2022
    end

    it "defaults to date_desc with undated games last" do
      expect(game_ids(common)).to eq([ bravo, delta, alpha, charlie ].map(&:game_id))
    end

    it "sorts date_asc with undated games last" do
      expect(game_ids(common(sort: "date_asc"))).to eq([ alpha, delta, bravo, charlie ].map(&:game_id))
    end

    it "sorts title_asc case-insensitively" do
      expect(game_ids(common(sort: "title_asc"))).to eq([ alpha, bravo, charlie, delta ].map(&:game_id))
    end

    it "sorts title_desc case-insensitively" do
      expect(game_ids(common(sort: "title_desc"))).to eq([ delta, charlie, bravo, alpha ].map(&:game_id))
    end

    it "breaks date ties by title" do
      echo = create(:game, title: "#{prefix} echo")
      both_completed(echo, left_at: Time.utc(2023, 1, 1))

      expect(game_ids(common).first(2)).to eq([ bravo, echo ].map(&:game_id))
    end

    it "paginates with page and per" do
      body = common(per: 3, page: 2)

      expect(game_ids(body)).to eq([ charlie.game_id ])
      expect(body.fetch("meta")).to include("count" => 4, "pages" => 2, "page" => 2, "per" => 3, "prev" => 1)
    end

    it "rejects an unknown sort" do
      get path, params: { other_user_id: right.user_id, sort: "rating" }, headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "returns 422 when other_user_id is missing" do
    get path, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json.fetch("error")).to match(/other_user_id/)
  end

  it "returns 422 when other_user_id is the same member" do
    get path, params: { other_user_id: left.user_id }, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 404 when other_user_id is unknown" do
    get path, params: { other_user_id: "999" }, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the path user is unknown" do
    get "/api/v1/users/999/completions/common", params: { other_user_id: right.user_id }, headers: auth_headers_for(viewer)

    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication" do
    get path, params: { other_user_id: right.user_id }

    expect(response).to have_http_status(:unauthorized)
  end
end
