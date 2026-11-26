# frozen_string_literal: true

require "rails_helper"

# Bug Report fields, the screenshot and the author's edit (spec api#498,
# ticket api#500). The Backblaze client is stubbed at its constructor, as the
# Club Codex image specs do; Github::Client likewise for approval.
RSpec.describe "api/v1/feedback Bug Reports behavior", type: :request do
  let(:author) { create(:user, role_member: true) }
  let(:bug_fields) { { where: "website", what_happened: "The page is blank", expected: "My games" } }
  let(:bug_report) do
    create(:feedback, kind: "bug_report", created_by: author.user_id, created_by_name: "tester",
      title: "Blank page", where: "website", what_happened: "The page is blank", expected: "My games")
  end
  let(:stored) { {} }
  let(:storage) { instance_double(Backblaze::Client) }

  around do |example|
    original = ENV.fetch("BACKBLAZE_PUBLIC_BASE_URL", nil)
    ENV["BACKBLAZE_PUBLIC_BASE_URL"] = "https://cdn.example.test/club"
    example.run
  ensure
    original.nil? ? ENV.delete("BACKBLAZE_PUBLIC_BASE_URL") : ENV["BACKBLAZE_PUBLIC_BASE_URL"] = original
  end

  before do
    allow(Backblaze::Client).to receive(:new).and_return(storage)
    allow(storage).to receive(:upload_bytes) do |object_key:, bytes:, content_type:|
      stored[object_key] = { bytes: bytes, content_type: content_type }
    end
    allow(storage).to receive(:delete_file) { |object_key:| stored.delete(object_key) }
  end

  def image(type = :png, size: nil)
    head = { png: "\x89PNG\r\n\x1A\n".b, jpeg: "\xFF\xD8\xFF\xE0".b, webp: "RIFF\x00\x00\x00\x00WEBPVP8 ".b,
             gif: "GIF89a".b, text: "hello".b }.fetch(type)
    bytes = size ? head + ("x" * (size - head.bytesize)) : "#{head}rest"
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/#{type}", original_filename: "shot.#{type}")
  end

  def upload(feedback = bug_report, file: image, as: author)
    put "/api/v1/feedback/#{feedback.feedback_id}/screenshot", params: { data: { file: file } },
      headers: auth_headers_for(as)
  end

  def edit(feedback = bug_report, data:, as: author)
    patch "/api/v1/feedback/#{feedback.feedback_id}", params: { data: data }, headers: auth_headers_for(as), as: :json
  end

  describe "POST /api/v1/feedback (Bug Report fields)" do
    def file(data)
      post "/api/v1/feedback", params: { data: data }, headers: auth_headers_for(author), as: :json
    end

    it "takes a Bug Report with its fields" do
      file(kind: "bug_report", title: "Blank page", **bug_fields, steps: "Open /games")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "kind" => "bug_report", "where" => "website", "what_happened" => "The page is blank",
        "expected" => "My games", "steps" => "Open /games", "screenshot_url" => nil
      )
    end

    it "refuses a Bug Report missing what happened or what was expected" do
      %i[what_happened expected].each do |missing|
        expect {
          file(kind: "bug_report", title: "Blank page", **bug_fields.merge(missing => " "))
        }.not_to change(RpgClubFeedback, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "does not need where or steps" do
      file(kind: "bug_report", title: "Blank page", what_happened: "Blank", expected: "Games")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("where" => nil, "steps" => nil)
    end

    it "refuses an unknown where" do
      file(kind: "bug_report", title: "Blank page", **bug_fields, where: "discord")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "needs no bug fields for the other kinds, and drops any sent" do
      %w[feature_request suggestion].each do |kind|
        file(kind: kind, title: "An idea", what_happened: "x", where: "bot")

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).to include("what_happened" => nil, "where" => nil)
      end
    end
  end

  describe "PATCH /api/v1/feedback/:id" do
    it "lets the author change their Pending Bug Report" do
      edit(data: { title: "Still blank", steps: "Open /games", expected: "My shelf", kind: "suggestion",
                   status: "approved" })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("title" => "Still blank", "steps" => "Open /games",
        "expected" => "My shelf", "kind" => "bug_report", "status" => "pending")
    end

    it "lets the author change the title and details of other kinds, ignoring bug fields" do
      idea = create(:feedback, created_by: author.user_id)

      edit(idea, data: { title: "Better idea", details: "More", what_happened: "x" })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("title" => "Better idea", "details" => "More", "what_happened" => nil)
    end

    it "refuses emptying a Bug Report's required fields" do
      edit(data: { what_happened: "" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(bug_report.reload.what_happened).to eq("The page is blank")
    end

    it "refuses anyone but the author, staff and the service included" do
      edit(data: { title: "Hijack" }, as: create(:user, role_member: true))
      expect(response).to have_http_status(:forbidden)

      edit(data: { title: "Hijack" }, as: create(:user, role_admin: true))
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/feedback/#{bug_report.feedback_id}", params: { data: { title: "Hijack" } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      expect(bug_report.reload.title).to eq("Blank page")
    end

    it "refuses once reviewed or withdrawn" do
      %w[approved rejected withdrawn].each do |status|
        bug_report.update_columns(status: status)

        edit(data: { title: "Too late" })

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to eq("feedback is #{status}, not pending")
      end
      expect(bug_report.reload.title).to eq("Blank page")
    end
  end

  describe "PUT /api/v1/feedback/:id/screenshot" do
    it "stores the author's screenshot and serves its URL" do
      upload

      expect(response).to have_http_status(:ok)
      key = stored.keys.sole
      expect(key).to match(%r{\Afeedback/#{bug_report.feedback_id}/\d{14}-\h{8}\.png\z})
      expect(stored.dig(key, :content_type)).to eq("image/png")
      expect(json.dig("data", "screenshot_url")).to eq("https://cdn.example.test/club/#{key}")
      expect(json.fetch("data")).not_to have_key("screenshot_key")
    end

    it "takes JPEG and WebP, told by the file's bytes" do
      { jpeg: "jpg", webp: "webp" }.each do |type, extension|
        upload(file: image(type))

        expect(response).to have_http_status(:ok)
        expect(bug_report.reload.screenshot_key).to end_with(".#{extension}")
      end
    end

    it "replaces the screenshot, removing the old file" do
      upload
      first = bug_report.reload.screenshot_key

      upload(file: image(:jpeg))

      expect(response).to have_http_status(:ok)
      expect(stored.keys).to eq([ bug_report.reload.screenshot_key ])
      expect(bug_report.screenshot_key).not_to eq(first)
    end

    it "refuses other types, an empty file and a file over 5 MB, storing nothing" do
      [ image(:gif), image(:text), image(:png, size: 5.megabytes + 1),
        Rack::Test::UploadedFile.new(StringIO.new(""), "image/png", original_filename: "empty.png") ].each do |file|
        upload(file: file)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("invalid_image")
      end
      expect(stored).to be_empty
      expect(bug_report.reload.screenshot_key).to be_nil
    end

    it "takes a file of exactly 5 MB" do
      upload(file: image(:png, size: 5.megabytes))

      expect(response).to have_http_status(:ok)
    end

    it "422s with no file" do
      put "/api/v1/feedback/#{bug_report.feedback_id}/screenshot", params: { data: { note: "x" } },
        headers: auth_headers_for(author)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_image")
    end

    it "refuses other kinds" do
      idea = create(:feedback, created_by: author.user_id)

      upload(idea)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("screenshot_not_allowed")
      expect(stored).to be_empty
    end

    it "refuses anyone but the author" do
      upload(as: create(:user, role_admin: true))

      expect(response).to have_http_status(:forbidden)
      expect(stored).to be_empty
    end

    it "refuses once reviewed" do
      bug_report.update_columns(status: "rejected")

      upload

      expect(response).to have_http_status(:conflict)
      expect(stored).to be_empty
    end

    it "removes the new file when the Feedback is reviewed during the upload" do
      allow(storage).to receive(:upload_bytes) do |object_key:, bytes:, content_type:|
        stored[object_key] = { bytes: bytes, content_type: content_type }
        RpgClubFeedback.where(feedback_id: bug_report.feedback_id).update_all(status: "approved")
      end

      upload

      expect(response).to have_http_status(:conflict)
      expect(stored).to be_empty
      expect(bug_report.reload.screenshot_key).to be_nil
    end

    it "502s when Backblaze refuses the upload, changing nothing" do
      allow(storage).to receive(:upload_bytes).and_raise(Backblaze::Client::RequestError, "B2 down")

      upload

      expect(response).to have_http_status(:bad_gateway)
      expect(json.fetch("error")).to eq("backblaze_request_failed")
      expect(bug_report.reload.screenshot_key).to be_nil
    end

    it "422s when Backblaze has no public URL configured, uploading nothing" do
      ENV.delete("BACKBLAZE_PUBLIC_BASE_URL")

      upload

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("backblaze_not_configured")
      expect(stored).to be_empty
    end
  end

  describe "DELETE /api/v1/feedback/:id/screenshot" do
    before { upload }

    it "removes the screenshot and its file" do
      delete "/api/v1/feedback/#{bug_report.feedback_id}/screenshot", headers: auth_headers_for(author)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "screenshot_url")).to be_nil
      expect(stored).to be_empty
    end

    it "still removes the screenshot when Backblaze refuses to delete the file" do
      allow(storage).to receive(:delete_file).and_raise(Backblaze::Client::RequestError, "B2 down")

      delete "/api/v1/feedback/#{bug_report.feedback_id}/screenshot", headers: auth_headers_for(author)

      expect(response).to have_http_status(:ok)
      expect(bug_report.reload.screenshot_key).to be_nil
    end

    it "refuses anyone but the author, and once reviewed" do
      delete "/api/v1/feedback/#{bug_report.feedback_id}/screenshot",
        headers: auth_headers_for(create(:user, role_member: true))
      expect(response).to have_http_status(:forbidden)

      bug_report.update_columns(status: "withdrawn")
      delete "/api/v1/feedback/#{bug_report.feedback_id}/screenshot", headers: auth_headers_for(author)
      expect(response).to have_http_status(:conflict)

      expect(stored.size).to eq(1)
    end
  end

  describe "POST /api/v1/feedback/:id/approve (Bug Report issue body)" do
    let(:github) { instance_double(Github::Client, configured?: true) }

    around do |example|
      original = ENV.fetch("DISCORD_OAUTH_SUCCESS_REDIRECT", nil)
      ENV["DISCORD_OAUTH_SUCCESS_REDIRECT"] = "https://club.example.test/auth/callback?x=1"
      example.run
    ensure
      original.nil? ? ENV.delete("DISCORD_OAUTH_SUCCESS_REDIRECT") : ENV["DISCORD_OAUTH_SUCCESS_REDIRECT"] = original
    end

    before do
      allow(Github::Client).to receive(:new).and_return(github)
      allow(github).to receive_messages(find_issue_by_marker: nil, create_issue: Github::Client::Issue.new(number: 7,
        url: "https://github.com/TheRPGClub/TheRPGClub-www/issues/7", state: "open"))
    end

    def approve
      post "/api/v1/feedback/#{bug_report.feedback_id}/approve",
        params: { data: { target_repo: "TheRPGClub/TheRPGClub-www" } },
        headers: auth_headers_for(create(:user), is_dev: true), as: :json
    end

    it "lays out the fields and links the Feedback on the board, without the screenshot" do
      upload
      bug_report.update_columns(steps: "Open /games", details: nil)

      approve

      expect(response).to have_http_status(:ok)
      id = bug_report.feedback_id
      expect(github).to have_received(:create_issue).with(
        repo: "TheRPGClub/TheRPGClub-www", title: "Blank page", labels: [ "bug" ],
        body: "Reported by tester.\n\n**Where:** Website\n\n### What happened\n\nThe page is blank\n\n" \
              "### Expected\n\nMy games\n\n### Steps to reproduce\n\nOpen /games\n\n" \
              "[Feedback ##{id} on the Feedback Board](https://club.example.test/feedback?pinned=#{id})\n\n" \
              "<!-- rpgclub-feedback:#{id} -->"
      )
      expect(github).not_to have_received(:create_issue).with(hash_including(body: /cdn\.example\.test/))
    end

    it "says what was not given, and names the board without a link when the website is not configured" do
      ENV.delete("DISCORD_OAUTH_SUCCESS_REDIRECT")
      bug_report.update_columns(where: nil)

      approve

      expect(github).to have_received(:create_issue).with(hash_including(
        body: a_string_including("**Where:** Not given", "### Steps to reproduce\n\nNot given.",
          "Feedback ##{bug_report.feedback_id} on the Feedback Board\n\n<!--")
      ))
    end
  end
end
