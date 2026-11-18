# frozen_string_literal: true

require "rails_helper"

# The Fun Fact queue (spec #397, ticket #405): POST
# /api/v1/codex/fun_facts/draw hands out the next Fun Fact for /funfact and
# marks it shown, so every Fun Fact is shown once before any repeats and a
# new Fun Fact goes next.
RSpec.describe "api/v1/codex/fun_facts/draw behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }

  def draw(headers = auth_headers_for(member), params = {})
    post "/api/v1/codex/fun_facts/draw", params: params, headers: headers, as: :json
    json.fetch("fun_fact")&.fetch("body")
  end

  def add_fun_fact(body, created_at: Time.current)
    create(:codex_entry, :fun_fact, author: regular, body: body, created_at: created_at)
  end

  it "draws every Fun Fact once before any repeats" do
    add_fun_fact("First.", created_at: 3.days.ago)
    add_fun_fact("Second.", created_at: 2.days.ago)
    add_fun_fact("Third.", created_at: 1.day.ago)

    first_cycle = Array.new(3) { draw }
    expect(response).to have_http_status(:ok)
    expect(first_cycle).to contain_exactly("First.", "Second.", "Third.")

    expect(Array.new(3) { draw }).to eq(first_cycle)
  end

  it "draws never-shown Fun Facts newest first, then the one shown longest ago" do
    add_fun_fact("Old.", created_at: 3.days.ago)
    add_fun_fact("Newer.", created_at: 2.days.ago)

    expect(Array.new(2) { draw }).to eq(%w[Newer. Old.])

    add_fun_fact("Newest.", created_at: 1.day.ago)
    expect(Array.new(4) { draw }).to eq(%w[Newest. Newer. Old. Newest.])
  end

  it "draws a Fun Fact added mid-cycle next" do
    add_fun_fact("First.", created_at: 2.days.ago)
    add_fun_fact("Second.", created_at: 1.day.ago)
    expect(draw).to eq("Second.")

    add_fun_fact("Brand new.")

    expect(Array.new(2) { draw }).to eq([ "Brand new.", "First." ])
  end

  it "breaks ties on the lowest id" do
    # Added at the same moment, then shown at the same moment.
    freeze_time do
      add_fun_fact("Lower id.")
      add_fun_fact("Higher id.")
      expect(Array.new(2) { draw }).to eq([ "Lower id.", "Higher id." ])
    end

    expect(Array.new(2) { draw }).to eq([ "Lower id.", "Higher id." ])
  end

  it "doesn't move a Fun Fact in the queue when it is edited" do
    edited = add_fun_fact("Edited later.", created_at: 2.days.ago)
    add_fun_fact("Left alone.", created_at: 1.day.ago)
    expect(Array.new(2) { draw }).to eq([ "Left alone.", "Edited later." ])

    patch "/api/v1/codex/fun_facts/#{edited.id}", params: { data: { body: "Edited." } },
      headers: auth_headers_for(regular), as: :json
    expect(response).to have_http_status(:ok)

    expect(Array.new(2) { draw }).to eq([ "Left alone.", "Edited." ])
  end

  it "never draws a deleted Fun Fact" do
    deleted = add_fun_fact("Deleted.", created_at: 1.day.ago)
    add_fun_fact("Kept.", created_at: 2.days.ago)

    delete "/api/v1/codex/fun_facts/#{deleted.id}", headers: auth_headers_for(regular)
    expect(response).to have_http_status(:ok)

    expect(Array.new(2) { draw }).to eq(%w[Kept. Kept.])
  end

  it "answers { fun_fact: null } when there are none" do
    create(:codex_entry, part: "lore_entry", title: "Not a Fun Fact", body: "A story.")

    post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(member), as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to eq("fun_fact" => nil)
  end

  it "answers with the whole entry, as the other Fun Fact endpoints show it" do
    fun_fact = add_fun_fact("Rhea named the bot.")

    post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(regular), as: :json

    expect(json.fetch("fun_fact")).to include(
      "id" => fun_fact.id, "part" => "fun_fact", "body" => "Rhea named the bot.", "mentions" => {},
      "author" => include("user_id" => regular.user_id), "viewer" => { "can_edit" => true, "can_delete" => true }
    )
  end

  it "draws for the member the bot names, who needs no Regulars role" do
    add_fun_fact("From /funfact.")

    expect(draw(service_headers, data: { acting_user_id: member.user_id })).to eq("From /funfact.")
    expect(json.dig("fun_fact", "viewer")).to eq("can_edit" => false, "can_delete" => false)

    post "/api/v1/codex/fun_facts/draw", headers: service_headers, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "refuses a signed-out visitor" do
    post "/api/v1/codex/fun_facts/draw", as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  describe "the feature gate" do
    let!(:fun_fact) { add_fun_fact("Gated.") }
    let(:admin) { create(:user, role_member: true, role_admin: true) }

    def draw_status(headers, params = {})
      post "/api/v1/codex/fun_facts/draw", params: params, headers: headers, as: :json
      response.status
    end

    it "hides the draw from non-staff in Preview, and answers staff" do
      set_feature_flag("club_codex", "preview")

      expect(draw_status(auth_headers_for(member))).to eq(404)
      expect(draw_status(auth_headers_for(admin))).to eq(200)
      expect(draw_status(auth_headers_for(member, is_dev: true))).to eq(200)
    end

    it "hides the draw from everyone when Off, without moving the queue" do
      set_feature_flag("club_codex", "off")

      expect(draw_status(auth_headers_for(admin))).to eq(404)
      expect(draw_status(auth_headers_for(member, is_dev: true))).to eq(404)
      expect(draw_status(service_headers, data: { acting_user_id: admin.user_id })).to eq(403)
      expect(fun_fact.reload.last_shown_at).to be_nil
    end

    it "lets the service token through, applying the Flag to the member it acts for" do
      set_feature_flag("club_codex", "preview")

      expect(draw_status(service_headers, data: { acting_user_id: member.user_id })).to eq(403)
      expect(json).to eq("error" => "feature_unavailable")
      expect(fun_fact.reload.last_shown_at).to be_nil

      expect(draw_status(service_headers, data: { acting_user_id: admin.user_id })).to eq(200)
    end
  end
end
