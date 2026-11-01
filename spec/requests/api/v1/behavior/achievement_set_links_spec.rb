# frozen_string_literal: true

require "rails_helper"

# Manual GameDB link fixes for Achievement Sets: PATCH
# /api/v1/achievement_sets/:id is admin-only (not the service, not members).
RSpec.describe "api/v1/achievement_sets PATCH behavior", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:set) { create(:achievement_set, provider: "psn", title: "Ghost of Tsushima") }
  let(:game) { create(:game) }

  def patch_link(game_id, headers)
    patch "/api/v1/achievement_sets/#{set.id}", params: { data: { game_id: game_id } }, headers: headers, as: :json
  end

  it "lets an admin link a set to a GameDB game" do
    patch_link(game.game_id, auth_headers_for(admin))

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("id" => set.id, "provider" => "psn", "game_id" => game.game_id)
    expect(set.reload.game_id).to eq(game.game_id)
  end

  it "lets a dev relink an already linked set" do
    set.update!(game_id: create(:game).game_id)

    patch_link(game.game_id, auth_headers_for(create(:user), is_dev: true))

    expect(response).to have_http_status(:ok)
    expect(set.reload.game_id).to eq(game.game_id)
  end

  it "lets an admin unlink a set with a null game_id" do
    set.update!(game_id: game.game_id)

    patch_link(nil, auth_headers_for(admin))

    expect(response).to have_http_status(:ok)
    expect(set.reload.game_id).to be_nil
  end

  it "rejects an unknown GameDB game with 422" do
    patch_link(2_000_000_000, auth_headers_for(admin))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(set.reload.game_id).to be_nil
  end

  it "requires game_id in the body" do
    patch "/api/v1/achievement_sets/#{set.id}", params: { data: { title: "x" } },
      headers: auth_headers_for(admin), as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "404s for an unknown set" do
    patch "/api/v1/achievement_sets/0", params: { data: { game_id: game.game_id } },
      headers: auth_headers_for(admin), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "forbids a regular member" do
    patch_link(game.game_id, auth_headers_for(create(:user)))

    expect(response).to have_http_status(:forbidden)
    expect(set.reload.game_id).to be_nil
  end

  it "forbids the service principal" do
    patch_link(game.game_id, service_headers)

    expect(response).to have_http_status(:forbidden)
    expect(set.reload.game_id).to be_nil
  end

  it "requires authentication" do
    patch_link(game.game_id, {})

    expect(response).to have_http_status(:unauthorized)
  end
end
