# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the game-images endpoints: primary-first listing, the
# admin/service-gated multipart upload, metadata updates (primary flag
# exclusivity, position) and deletion. Backblaze traffic is stubbed at the
# Gamedb::GameImageStorage seam — no spec makes a real HTTP call.
RSpec.describe "api/v1/game_images behavior", type: :request do
  let(:game) { create(:game) }

  describe "GET /api/v1/games/:game_id/images" do
    it "lists only the game's images, primary first then by position" do
      cover_secondary = create(:game_image, game: game, kind: "cover", position: 2)
      artwork = create(:game_image, game: game, kind: "artwork", position: 1)
      cover_primary = create(:game_image, :primary, game: game, kind: "cover", position: 1)
      create(:game_image) # other game

      get "/api/v1/games/#{game.game_id}/images", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |i| i.fetch("image_id") })
        .to eq([ cover_primary.image_id, artwork.image_id, cover_secondary.image_id ])
      expect(json.fetch("data").first).to include(
        "image_id" => cover_primary.image_id,
        "game_id" => game.game_id,
        "kind" => "cover",
        "object_key" => cover_primary.object_key,
        "is_primary" => true,
        "position" => 1,
        "url" => cover_primary.url
      )
    end

    it "404s for an unknown game" do
      get "/api/v1/games/999999999/images", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/games/#{game.game_id}/images"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/games/:game_id/images" do
    let(:upload) do
      Rack::Test::UploadedFile.new(StringIO.new("fake-png-bytes"), "image/png", original_filename: "cover.png")
    end
    let(:storage) { instance_double(Gamedb::GameImageStorage) }

    before { allow(Gamedb::GameImageStorage).to receive(:new).and_return(storage) }

    it "uploads through the storage service and returns the created image" do
      record = create(:game_image, :primary, game: game, kind: "cover")
      allow(storage).to receive(:upload_manual!).and_return(record)

      post "/api/v1/games/#{game.game_id}/images",
        params: { image: { file: upload, kind: "cover" } }, headers: service_headers

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "image_id" => record.image_id,
        "kind" => "cover",
        "is_primary" => true,
        "url" => record.url
      )
      expect(storage).to have_received(:upload_manual!).with(
        game: game, uploaded_file: anything, kind: "cover", uploaded_by_user_id: nil, primary: true
      )
    end

    it "records the uploading admin and honors is_primary=false" do
      admin = create(:user, :admin)
      record = create(:game_image, game: game, kind: "artwork")
      allow(storage).to receive(:upload_manual!).and_return(record)

      post "/api/v1/games/#{game.game_id}/images",
        params: { image: { file: upload, kind: "artwork", is_primary: "false" } },
        headers: auth_headers_for(admin)

      expect(response).to have_http_status(:created)
      expect(storage).to have_received(:upload_manual!).with(
        game: game, uploaded_file: anything, kind: "artwork", uploaded_by_user_id: admin.user_id, primary: false
      )
    end

    it "422s for an invalid kind" do
      allow(Gamedb::GameImageStorage).to receive(:new).and_call_original

      post "/api/v1/games/#{game.game_id}/images",
        params: { image: { file: upload, kind: "screenshot" } }, headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("kind must be one of")
    end

    it "422s when the kind is missing" do
      post "/api/v1/games/#{game.game_id}/images",
        params: { image: { file: upload } }, headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    # ActionController::ParameterMissing is a KeyError, which #create rescues
    # into a 422 — matching the documented contract (no 400 is documented).
    it "422s when the image envelope is missing" do
      post "/api/v1/games/#{game.game_id}/images", params: {}, headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("image")
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games/#{game.game_id}/images",
          params: { image: { file: upload, kind: "cover" } }, headers: auth_headers_for(create(:user))
      }.not_to change(GamedbGameImage, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/games/#{game.game_id}/images", params: { image: { file: upload, kind: "cover" } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/games/:game_id/images/:id" do
    it "updates the position" do
      image = create(:game_image, game: game, position: 1)

      patch "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { data: { position: 5 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "position")).to eq(5)
      expect(image.reload.position).to eq(5)
    end

    it "marking primary clears the flag on same-kind siblings only" do
      old_primary = create(:game_image, :primary, game: game, kind: "cover")
      promoted = create(:game_image, game: game, kind: "cover", position: 2)
      artwork_primary = create(:game_image, :primary, game: game, kind: "artwork")

      patch "/api/v1/games/#{game.game_id}/images/#{promoted.image_id}",
        params: { data: { is_primary: true } }, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(promoted.reload.is_primary).to be(true)
      expect(old_primary.reload.is_primary).to be(false)
      expect(artwork_primary.reload.is_primary).to be(true)
    end

    it "accepts PUT as an alias" do
      image = create(:game_image, game: game)

      put "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { data: { position: 3 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(image.reload.position).to eq(3)
    end

    it "422s for an invalid position" do
      image = create(:game_image, game: game)

      patch "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { data: { position: 0 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(image.reload.position).to eq(1)
    end

    it "404s for an image belonging to another game" do
      foreign = create(:game_image)

      patch "/api/v1/games/#{game.game_id}/images/#{foreign.image_id}",
        params: { data: { position: 2 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      image = create(:game_image, game: game)

      patch "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { position: 2 }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      image = create(:game_image, game: game)

      patch "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { data: { position: 9 } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(image.reload.position).to eq(1)
    end

    it "requires authentication" do
      image = create(:game_image, game: game)

      patch "/api/v1/games/#{game.game_id}/images/#{image.image_id}",
        params: { data: { position: 2 } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/games/:game_id/images/:id" do
    let(:storage) { instance_double(Gamedb::GameImageStorage) }

    before do
      allow(Gamedb::GameImageStorage).to receive(:new).and_return(storage)
      allow(storage).to receive(:delete!) { |image| image.destroy! }
    end

    it "deletes the image through the storage service" do
      image = create(:game_image, game: game)

      delete "/api/v1/games/#{game.game_id}/images/#{image.image_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbGameImage.exists?(image.image_id)).to be(false)
      expect(storage).to have_received(:delete!)
    end

    it "404s for an unknown image" do
      delete "/api/v1/games/#{game.game_id}/images/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      image = create(:game_image, game: game)

      delete "/api/v1/games/#{game.game_id}/images/#{image.image_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbGameImage.exists?(image.image_id)).to be(true)
    end

    it "requires authentication" do
      image = create(:game_image, game: game)

      delete "/api/v1/games/#{game.game_id}/images/#{image.image_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
