# frozen_string_literal: true

require "rails_helper"

# Club Codex entry images (spec #397, ticket #410): a gallery of up to 4 on
# History Events and Lore Entries, under /api/v1/codex/entries/:id/images.
# Whoever can edit the entry adds and removes them; Fun Facts refuse them.
#
# The Backblaze storage client is stubbed (as the game image specs stub
# their storage), so no spec makes a real HTTP call; `stored` is what the
# bucket holds.
RSpec.describe "api/v1/codex entry images behavior", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:other_regular) { create(:user, role_member: true, role_regular: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:lore_entry) { create(:codex_entry, :lore_entry, author: regular) }
  let(:history_event) { create(:codex_entry, :history_event, author: admin) }
  let(:fun_fact) { create(:codex_entry, :fun_fact, author: regular) }

  let(:stored) { {} }
  let(:client) { instance_double(Backblaze::Client) }

  around do |example|
    original = ENV.fetch("BACKBLAZE_PUBLIC_BASE_URL", nil)
    ENV["BACKBLAZE_PUBLIC_BASE_URL"] = "https://cdn.example.test/club"
    example.run
  ensure
    original.nil? ? ENV.delete("BACKBLAZE_PUBLIC_BASE_URL") : ENV["BACKBLAZE_PUBLIC_BASE_URL"] = original
  end

  before do
    allow(Backblaze::Client).to receive(:new).and_return(client)
    allow(client).to receive(:upload_bytes) do |object_key:, bytes:, content_type:|
      stored[object_key] = { bytes: bytes, content_type: content_type }
    end
    allow(client).to receive(:delete_file) { |object_key:| stored.delete(object_key) }
  end

  def png(name = "screenshot.png", bytes: "png-bytes")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", original_filename: name)
  end

  def upload_image(entry, as:, file: png)
    post "/api/v1/codex/entries/#{entry.id}/images", params: { data: { file: file } }, headers: auth_headers_for(as)
  end

  def remove_image(entry, image_id, as:)
    delete "/api/v1/codex/entries/#{entry.id}/images/#{image_id}", headers: auth_headers_for(as)
  end

  def gallery(entry, as: regular)
    path = entry.history_event? ? "history_events" : "lore_entries"
    get "/api/v1/codex/#{path}/#{entry.id}", headers: auth_headers_for(as)
    json.dig("data", "images")
  end

  describe "adding images" do
    it "stores the author's image and returns its id, url and position, for the gallery or the story" do
      upload_image(lore_entry, as: regular)

      expect(response).to have_http_status(:created)
      image = json.fetch("data")
      object_key = stored.keys.sole
      expect(object_key).to match(%r{\Acodex/entries/#{lore_entry.id}/\d{14}-\h{8}\.png\z})
      expect(stored.fetch(object_key)).to eq(bytes: "png-bytes", content_type: "image/png")
      expect(image).to eq("id" => image.fetch("id"), "url" => "https://cdn.example.test/club/#{object_key}",
        "position" => 1)
      expect(image.fetch("id")).to be_a(Integer)

      expect(gallery(lore_entry)).to eq([ image ])
    end

    it "takes up to 4 on a Lore Entry, in upload order, and refuses a fifth" do
      4.times { |n| upload_image(lore_entry, as: regular, file: png("shot-#{n}.png", bytes: "shot #{n}")) }
      expect(response).to have_http_status(:created)

      upload_image(lore_entry, as: regular)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "too_many_images", "message" => "An entry can have at most 4 images.")
      expect(stored.size).to eq(4)
      images = gallery(lore_entry)
      expect(images.pluck("position")).to eq([ 1, 2, 3, 4 ])
      expect(images.map { |image| stored.fetch(image["url"].delete_prefix("https://cdn.example.test/club/"))[:bytes] })
        .to eq([ "shot 0", "shot 1", "shot 2", "shot 3" ])
    end

    it "removes the stored file again when another upload takes the last place meanwhile" do
      3.times { upload_image(lore_entry, as: regular) }
      allow(client).to receive(:upload_bytes) do |object_key:, bytes:, content_type:|
        stored[object_key] = { bytes: bytes, content_type: content_type }
        # Another upload finishing while this one's file is on its way.
        CodexEntryImage.create!(entry_id: lore_entry.id, object_key: "codex/entries/other.png", position: 4,
          uploaded_by_user_id: moderator.user_id)
      end

      upload_image(lore_entry, as: regular, file: png(bytes: "too late"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("too_many_images")
      expect(stored.values.pluck(:bytes)).not_to include("too late")
      expect(gallery(lore_entry).size).to eq(4)
    end

    it "takes up to 4 on a History Event, added by an Admin, and refuses a fifth" do
      4.times { upload_image(history_event, as: admin) }
      expect(response).to have_http_status(:created)

      upload_image(history_event, as: admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("too_many_images")
      expect(gallery(history_event, as: regular).pluck("position")).to eq([ 1, 2, 3, 4 ])
    end

    it "refuses an image on a Fun Fact, storing nothing" do
      upload_image(fun_fact, as: regular)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "images_not_allowed", "message" => "Fun Facts can't have images.")
      expect(stored).to be_empty
      get "/api/v1/codex/fun_facts/#{fun_fact.id}", headers: auth_headers_for(regular)
      expect(json.dig("data", "images")).to eq([])
    end

    it "refuses a file that isn't an image, storing nothing" do
      upload_image(lore_entry, as: regular,
        file: Rack::Test::UploadedFile.new(StringIO.new("text"), "text/plain", original_filename: "a.txt"))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_image", "message" => "image must be JPEG, PNG, WebP, or GIF")

      post "/api/v1/codex/entries/#{lore_entry.id}/images", params: { data: { title: "no file" } },
        headers: auth_headers_for(regular)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_image", "message" => "image file is required")

      expect(stored).to be_empty
      expect(gallery(lore_entry)).to eq([])
    end

    it "404s for an unknown entry" do
      post "/api/v1/codex/entries/0/images", params: { data: { file: png } }, headers: auth_headers_for(regular)

      expect(response).to have_http_status(:not_found)
      expect(stored).to be_empty
    end
  end

  describe "removing images" do
    def key_of(image) = image.fetch("url").delete_prefix("https://cdn.example.test/club/")

    it "removes the file from storage, moves later images up, and puts the next upload last" do
      3.times { |n| upload_image(lore_entry, as: regular, file: png(bytes: "shot #{n}")) }
      first, second, third = gallery(lore_entry)

      remove_image(lore_entry, second.fetch("id"), as: regular)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => { "id" => second.fetch("id"), "deleted" => true })
      expect(stored.keys).to contain_exactly(key_of(first), key_of(third))
      expect(gallery(lore_entry)).to eq([ first, third.merge("position" => 2) ])

      upload_image(lore_entry, as: regular, file: png(bytes: "shot 3"))
      expect(json.dig("data", "position")).to eq(3)
      expect(gallery(lore_entry).map { |image| stored.fetch(key_of(image))[:bytes] })
        .to eq([ "shot 0", "shot 2", "shot 3" ])
    end

    it "lets a full gallery take a new image once one is removed" do
      4.times { upload_image(history_event, as: admin) }
      remove_image(history_event, gallery(history_event).first.fetch("id"), as: admin)

      upload_image(history_event, as: admin)

      expect(response).to have_http_status(:created)
      expect(gallery(history_event).pluck("position")).to eq([ 1, 2, 3, 4 ])
    end

    it "404s for an image of another entry, removing nothing" do
      upload_image(lore_entry, as: regular)
      image_id = json.dig("data", "id")
      other = create(:codex_entry, :lore_entry, author: regular)

      remove_image(other, image_id, as: regular)

      expect(response).to have_http_status(:not_found)
      expect(stored.size).to eq(1)
      expect(gallery(lore_entry).pluck("id")).to eq([ image_id ])
    end
  end

  describe "when storage fails" do
    it "502s when Backblaze refuses an upload, keeping nothing" do
      allow(client).to receive(:upload_bytes).and_raise(Backblaze::Client::RequestError, "B2 down")

      upload_image(lore_entry, as: regular)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to eq("error" => "backblaze_request_failed", "message" => "B2 down")
      expect(gallery(lore_entry)).to eq([])
    end

    it "422s when Backblaze has no public URL configured, uploading nothing" do
      ENV.delete("BACKBLAZE_PUBLIC_BASE_URL")

      upload_image(lore_entry, as: regular)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("backblaze_not_configured")
      expect(stored).to be_empty
    end

    it "keeps an image whose file Backblaze refuses to remove, so the removal can be retried" do
      upload_image(lore_entry, as: regular)
      image = json.fetch("data")
      allow(client).to receive(:delete_file).and_raise(Backblaze::Client::RequestError, "B2 down")

      remove_image(lore_entry, image.fetch("id"), as: regular)

      expect(response).to have_http_status(:bad_gateway)
      expect(gallery(lore_entry)).to eq([ image ])
    end
  end

  describe "the bot, acting for a member" do
    it "adds and removes images for the member it names, by their roles" do
      post "/api/v1/codex/entries/#{lore_entry.id}/images",
        params: { data: { file: png, acting_user_id: regular.user_id } }, headers: service_headers
      expect(response).to have_http_status(:created)
      image_id = json.dig("data", "id")

      delete "/api/v1/codex/entries/#{lore_entry.id}/images/#{image_id}",
        params: { acting_user_id: other_regular.user_id }, headers: service_headers
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/codex/entries/#{lore_entry.id}/images/#{image_id}",
        params: { acting_user_id: regular.user_id }, headers: service_headers
      expect(response).to have_http_status(:ok)
      expect(stored).to be_empty
    end

    it "needs the member it acts for" do
      post "/api/v1/codex/entries/#{lore_entry.id}/images", params: { data: { file: png } }, headers: service_headers

      expect(response).to have_http_status(:bad_request)
      expect(stored).to be_empty
    end
  end

  describe "the Club Codex Feature" do
    it "hides the endpoints from non-staff in Preview, and from everyone when Off" do
      upload_image(lore_entry, as: regular)
      image_id = json.dig("data", "id")

      set_feature_flag("club_codex", "preview")
      upload_image(lore_entry, as: regular)
      expect(response).to have_http_status(:not_found)
      remove_image(lore_entry, image_id, as: regular)
      expect(response).to have_http_status(:not_found)
      upload_image(lore_entry, as: create(:user, role_member: true, role_admin: true))
      expect(response).to have_http_status(:created)

      set_feature_flag("club_codex", "off")
      remove_image(lore_entry, image_id, as: admin)
      expect(response).to have_http_status(:not_found)
      expect(stored.size).to eq(2)
    end

    it "refuses the bot when the Flag hides the Feature from the member it acts for" do
      set_feature_flag("club_codex", "preview")

      post "/api/v1/codex/entries/#{lore_entry.id}/images",
        params: { data: { file: png, acting_user_id: regular.user_id } }, headers: service_headers

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "feature_unavailable")
      expect(stored).to be_empty
    end
  end

  describe "deleting an entry" do
    it "removes a Lore Entry's image files from storage" do
      2.times { upload_image(lore_entry, as: regular) }
      kept = create(:codex_entry, :lore_entry, author: regular)
      upload_image(kept, as: regular)
      kept_key = stored.keys.last

      delete "/api/v1/codex/lore_entries/#{lore_entry.id}", headers: auth_headers_for(moderator)

      expect(response).to have_http_status(:ok)
      expect(stored.keys).to eq([ kept_key ])
      expect(gallery(kept).size).to eq(1)
    end

    it "removes a History Event's image files from storage" do
      4.times { upload_image(history_event, as: admin) }

      delete "/api/v1/codex/history_events/#{history_event.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(stored).to be_empty
      get "/api/v1/codex/history_events/#{history_event.id}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:not_found)
    end

    it "removes the file of an image an upload records while the entry is being deleted" do
      upload_image(lore_entry, as: regular)
      raced = false
      allow(client).to receive(:delete_file) do |object_key:|
        stored.delete(object_key)
        next if raced

        # An upload that passed its gallery check records its image while the
        # entry's files are being removed.
        raced = true
        stored["codex/entries/#{lore_entry.id}/raced.png"] = { bytes: "raced", content_type: "image/png" }
        CodexEntryImage.create!(entry_id: lore_entry.id, object_key: "codex/entries/#{lore_entry.id}/raced.png",
          position: 2, uploaded_by_user_id: regular.user_id)
      end

      delete "/api/v1/codex/lore_entries/#{lore_entry.id}", headers: auth_headers_for(regular)

      expect(response).to have_http_status(:ok)
      expect(stored).to be_empty
      expect(CodexEntryImage.where(entry_id: lore_entry.id)).to be_empty
    end

    it "keeps the entry when storage refuses to remove a file, so the delete can be retried" do
      upload_image(lore_entry, as: regular)
      allow(client).to receive(:delete_file).and_raise(Backblaze::Client::RequestError, "B2 down")

      delete "/api/v1/codex/lore_entries/#{lore_entry.id}", headers: auth_headers_for(regular)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to include("error" => "backblaze_request_failed")
      expect(gallery(lore_entry).size).to eq(1)
    end
  end

  describe "who may add and remove images" do
    let(:member) { create(:user, role_member: true) }

    it "lets only someone who can edit a Lore Entry add or remove its images" do
      [ other_regular, member ].each do |someone|
        upload_image(lore_entry, as: someone)
        expect(response).to have_http_status(:forbidden)
        expect(json).to eq("error" => "forbidden", "message" => "Only its author or a Moderator can edit this.")
      end
      expect(stored).to be_empty

      upload_image(lore_entry, as: moderator)
      expect(response).to have_http_status(:created)
      image_id = json.dig("data", "id")

      remove_image(lore_entry, image_id, as: other_regular)
      expect(response).to have_http_status(:forbidden)
      expect(gallery(lore_entry).pluck("id")).to eq([ image_id ])

      remove_image(lore_entry, image_id, as: regular)
      expect(response).to have_http_status(:ok)
      expect(gallery(lore_entry)).to eq([])
    end

    it "lets only Admins and Superadmins add or remove a History Event's images" do
      [ moderator, regular ].each do |someone|
        upload_image(history_event, as: someone)
        expect(response).to have_http_status(:forbidden)
        expect(json).to eq("error" => "forbidden", "message" => "Only Admins can change Club History.")
      end

      upload_image(history_event, as: create(:user, role_member: true, role_admin: true))
      expect(response).to have_http_status(:created)
      image_id = json.dig("data", "id")

      remove_image(history_event, image_id, as: moderator)
      expect(response).to have_http_status(:forbidden)

      remove_image(history_event, image_id, as: admin)
      expect(response).to have_http_status(:ok)
    end

    it "needs a sign-in, even for a History Event" do
      post "/api/v1/codex/entries/#{history_event.id}/images", params: { data: { file: png } }

      expect(response).to have_http_status(:unauthorized)
      expect(stored).to be_empty
    end
  end
end
