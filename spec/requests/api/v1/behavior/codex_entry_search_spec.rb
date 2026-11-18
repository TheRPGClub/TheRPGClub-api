# frozen_string_literal: true

require "rails_helper"

# The Club Codex entry search (spec #397, ticket #409): the website's "See
# also" link picker finds entries of all three parts, in their short link
# shape, among those the caller may read.
RSpec.describe "api/v1/codex/entries behavior", type: :request do
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }
  let(:admin) { create(:user, role_member: true, role_admin: true) }

  let!(:history_event) do
    create(:codex_entry, :history_event, author: admin, title: "The club moves to Discord", body: "We left IRC.")
  end
  let!(:lore_entry) do
    create(:codex_entry, :lore_entry, author: regular, title: "The #general wipe",
      body: "Somebody ran the purge command on Discord's busiest channel.")
  end
  let!(:fun_fact) { create(:codex_entry, author: regular, body: "Our first Discord server was named Waffle House.") }
  let!(:unrelated) { create(:codex_entry, author: regular, body: "The bot has a favourite member.") }

  def search(as: member, **query)
    get "/api/v1/codex/entries", params: query, headers: as && auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  it "finds entries of every part by title and text, in the short link shape" do
    expect(search(q: "discord")).to contain_exactly(
      { "id" => history_event.id, "part" => "history_event", "title" => "The club moves to Discord" },
      { "id" => lore_entry.id, "part" => "lore_entry", "title" => "The #general wipe" },
      { "id" => fun_fact.id, "part" => "fun_fact", "title" => "Our first Discord server was named Waffle House." }
    )
    expect(search(q: "IRC").map { |entry| entry["id"] }).to eq([ history_event.id ])
    expect(search(q: "purge").map { |entry| entry["id"] }).to eq([ lore_entry.id ])
  end

  it "puts title matches first, then the newest" do
    expect(search(q: "discord").map { |entry| entry["id"] }).to eq([ history_event.id, fun_fact.id, lore_entry.id ])
  end

  it "lists every entry, newest first, without a query" do
    expect(search.map { |entry| entry["id"] }).to eq([ unrelated.id, fun_fact.id, lore_entry.id, history_event.id ])
  end

  it "takes a query's special characters literally" do
    expect(search(q: "%")).to eq([])
    expect(search(q: "#general").map { |entry| entry["id"] }).to eq([ lore_entry.id ])
  end

  it "finds nothing for a query holding a NUL character, which no entry can hold" do
    expect(search(q: "Disc\u0000ord")).to eq([])

    get "/api/v1/codex/fun_facts", params: { q: "Waf\u0000fle" }, headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to eq([])
  end

  it "keeps one part" do
    expect(search(q: "discord", part: "fun_fact").map { |entry| entry["id"] }).to eq([ fun_fact.id ])

    get "/api/v1/codex/entries", params: { part: "rumour" }, headers: auth_headers_for(member)
    expect(response).to have_http_status(:bad_request)
    expect(json).to eq("error" => "invalid_part",
      "message" => "Part must be one of history_event, lore_entry, fun_fact")
  end

  it "is paginated" do
    get "/api/v1/codex/entries", params: { per: 2, page: 2 }, headers: auth_headers_for(member)

    expect(json.fetch("data").map { |entry| entry["id"] }).to eq([ lore_entry.id, history_event.id ])
    expect(json.fetch("meta")).to include("page" => 2, "per" => 2)
  end

  it "finds only History Events for a Visitor, and only when Live" do
    expect(search(as: nil, q: "discord").map { |entry| entry["id"] }).to eq([ history_event.id ])
    expect(search(as: nil, part: "lore_entry")).to eq([])

    set_feature_flag("club_codex", "preview")
    get "/api/v1/codex/entries"
    expect(response).to have_http_status(:not_found)
  end

  it "finds every part for the bot" do
    get "/api/v1/codex/entries", params: { q: "discord" }, headers: service_headers

    expect(json.fetch("data").size).to eq(3)
  end
end
