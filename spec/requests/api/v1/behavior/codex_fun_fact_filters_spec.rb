# frozen_string_literal: true

require "rails_helper"

# Fun Fact list filters (spec #397; ticket #409, for the bot's
# `/codex fun-fact edit|delete` autocomplete, bot#1561): `q` finds Fun Facts
# by their text, and `editable=true` keeps those the acting member may edit.
RSpec.describe "api/v1/codex/fun_facts filters", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:other_regular) { create(:user, role_member: true, role_regular: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:member) { create(:user, role_member: true) }

  let!(:soup) { create(:codex_entry, author: regular, body: "The server was once named Soup Kitchen.") }
  let!(:waffles) { create(:codex_entry, author: other_regular, body: "Our first server was named Waffle House.") }
  let!(:mine_too) { create(:codex_entry, author: regular, body: "Nobody has ever finished the backlog 100% challenge.") }

  def list(as: member, headers: nil, **query)
    get "/api/v1/codex/fun_facts", params: query, headers: headers || auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data").map { |entry| entry["id"] }
  end

  it "finds Fun Facts by their text, any case, its special characters taken literally" do
    expect(list(q: "named")).to eq([ waffles.id, soup.id ])
    expect(list(q: "SOUP")).to eq([ soup.id ])
    expect(list(q: "100%")).to eq([ mine_too.id ])
    expect(list(q: "_")).to eq([])
    expect(list(q: "  ")).to eq([ mine_too.id, waffles.id, soup.id ])
  end

  it "keeps a member's own Fun Facts with editable=true" do
    expect(list(as: regular, editable: "true")).to eq([ mine_too.id, soup.id ])
    expect(list(as: member, editable: "true")).to eq([])
    expect(list(as: regular, editable: "true", q: "named")).to eq([ soup.id ])
  end

  it "keeps every Fun Fact for a Moderator and above" do
    expect(list(as: moderator, editable: "true")).to eq([ mine_too.id, waffles.id, soup.id ])
  end

  it "decides for the member the bot names" do
    expect(list(headers: service_headers, editable: "true", acting_user_id: other_regular.user_id))
      .to eq([ waffles.id ])
    expect(json.dig("data", 0, "viewer")).to eq("can_edit" => true, "can_delete" => true)
    expect(list(headers: service_headers, editable: "true", acting_user_id: moderator.user_id).size).to eq(3)

    get "/api/v1/codex/fun_facts", params: { editable: "true" }, headers: service_headers
    expect(response).to have_http_status(:bad_request)
    expect(json).to eq("error" => "acting_user_id required")
  end

  it "ignores editable unless it is true" do
    expect(list(as: regular, editable: "false").size).to eq(3)
  end
end
