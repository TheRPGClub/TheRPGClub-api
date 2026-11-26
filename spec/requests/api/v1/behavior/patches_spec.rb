# frozen_string_literal: true

require "rails_helper"

# Patches (GLOSSARY.md "Patch"; spec api#510, ticket api#511) under
# /api/v1/patches. Admins and Superadmins write, publish, unpublish and delete
# drafts; anyone, Visitors included, reads the published Patches while Patch
# Notes is Live.
RSpec.describe "api/v1/patches behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, role_member: true, role_admin: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:member) { create(:user, role_member: true) }

  let(:rich_body) do
    [
      { "type" => "p", "children" => [ { "text" => "A quiet week." } ] },
      { "type" => "h2", "children" => [ { "text" => "New" } ] },
      { "type" => "ul", "children" => [
        { "type" => "li", "children" => [ { "type" => "lic", "children" => [ { "text" => "Patch Notes" } ] } ] }
      ] }
    ]
  end

  def write(as:, is_dev: false, **data)
    post "/api/v1/patches", params: { data: { rich_body: rich_body, body: "A quiet week.", cut_body: "A quiet week." }.merge(data) },
      headers: auth_headers_for(as, is_dev: is_dev), as: :json
  end

  describe "writing a Patch" do
    it "lets an Admin start a draft, numbered for them" do
      write(as: admin, title: "The Franchise update")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "title" => "The Franchise update", "status" => "draft", "published_at" => nil,
        "rich_body" => rich_body, "body" => "A quiet week.", "cut_body" => "A quiet week."
      )
      expect(json.dig("data", "number")).to be_a(Integer)
    end

    it "lets a Superadmin start one, and leaves the title optional" do
      write(as: member, is_dev: true)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "title")).to be_nil
    end

    it "refuses Moderators, members, the service and Visitors" do
      [ moderator, member ].each do |user|
        write(as: user)
        expect(response).to have_http_status(:forbidden), "#{user.user_id} got #{response.status}"
      end

      post "/api/v1/patches", params: { data: { body: "x" } }, headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/patches", params: { data: { body: "x" } }, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/patches", params: { status: "all" }, headers: auth_headers_for(admin)
      expect(json.fetch("data")).to be_empty
    end
  end

  # Starts a draft as the Admin and returns its number.
  def draft(**data)
    write(as: admin, **data)
    json.dig("data", "number")
  end

  def act(action, number, as: admin, is_dev: false)
    post "/api/v1/patches/#{number}/#{action}", headers: auth_headers_for(as, is_dev: is_dev)
  end

  def published(**data)
    number = draft(**data)
    act(:publish, number)
    number
  end

  describe "editing a draft" do
    it "changes only the fields given" do
      number = draft(title: "Working title")

      patch "/api/v1/patches/#{number}", params: { data: { body: "Two things.", cut_body: "Two things." } },
        headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("number" => number, "title" => "Working title", "body" => "Two things.",
        "rich_body" => rich_body)
    end

    it "refuses a field a Patch doesn't take, text that isn't text and a rich_body that isn't a list" do
      number = draft

      [ { status: "published" }, { body: 4 }, { body: nil }, { rich_body: "text" }, { title: "a\u0000b" } ].each do |data|
        patch "/api/v1/patches/#{number}", params: { data: data }, headers: auth_headers_for(admin), as: :json
        expect(response).to have_http_status(:unprocessable_content), "#{data} got #{response.status}"
        expect(json.fetch("error")).to eq("invalid_patch")
      end
    end

    it "refuses Moderators, members and the service" do
      number = draft

      [ auth_headers_for(moderator), auth_headers_for(member), service_headers ].each do |headers|
        patch "/api/v1/patches/#{number}", params: { data: { title: "Mine" } }, headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "numbering" do
    it "numbers Patches in order and never hands a number out twice" do
      first = draft
      second = draft
      expect(second).to eq(first + 1)

      delete "/api/v1/patches/#{second}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("number" => second, "deleted" => true)

      act(:publish, first)
      act(:unpublish, first)

      expect(draft).to eq(second + 1)
    end
  end

  describe "publishing and unpublishing" do
    it "publishes a draft with its time, and unpublishes it back to a draft" do
      number = draft

      freeze_time do
        act(:publish, number)
        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("status" => "published", "published_at" => Time.current.as_json)
      end

      get "/api/v1/patches/#{number}"
      expect(response).to have_http_status(:ok)

      act(:unpublish, number)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "draft", "published_at" => nil)

      get "/api/v1/patches/#{number}"
      expect(response).to have_http_status(:not_found)
    end

    it "refuses publishing twice and unpublishing a draft" do
      number = draft

      act(:unpublish, number)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("not_published")

      act(:publish, number)
      act(:publish, number)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("already_published")
    end

    it "lets a Superadmin publish and unpublish, and refuses everyone else" do
      number = draft

      [ moderator, member ].each do |user|
        act(:publish, number, as: user)
        expect(response).to have_http_status(:forbidden)
      end
      post "/api/v1/patches/#{number}/publish", headers: service_headers
      expect(response).to have_http_status(:forbidden)

      act(:publish, number, as: member, is_dev: true)
      expect(response).to have_http_status(:ok)

      [ moderator, member ].each do |user|
        act(:unpublish, number, as: user)
        expect(response).to have_http_status(:forbidden)
      end
      act(:unpublish, number, as: member, is_dev: true)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "deleting" do
    it "deletes a draft only, for Admins and Superadmins" do
      number = published

      delete "/api/v1/patches/#{number}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("published")

      act(:unpublish, number)
      [ auth_headers_for(moderator), auth_headers_for(member), service_headers ].each do |headers|
        delete "/api/v1/patches/#{number}", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      delete "/api/v1/patches/#{number}", headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:ok)

      get "/api/v1/patches/#{number}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "reading Patches" do
    it "lists the published ones newest first, and shows one by number, to a Visitor" do
      older = published(title: "Older")
      hidden = draft(title: "Draft")
      newer = published(title: "Newer")

      get "/api/v1/patches"
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |p| [ p["number"], p["title"] ] }).to eq([ [ newer, "Newer" ], [ older, "Older" ] ])

      get "/api/v1/patches/#{older}"
      expect(json.fetch("data")).to include("number" => older, "title" => "Older", "status" => "published")

      get "/api/v1/patches/#{hidden}"
      expect(response).to have_http_status(:not_found)
    end

    it "hides drafts from members, Moderators and the service, and shows them to Admins" do
      number = draft

      [ auth_headers_for(member), auth_headers_for(moderator), service_headers ].each do |headers|
        get "/api/v1/patches/#{number}", headers: headers
        expect(response).to have_http_status(:not_found)

        get "/api/v1/patches", headers: headers
        expect(json.fetch("data")).to be_empty
      end

      get "/api/v1/patches", params: { status: "draft" }, headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/patches/#{number}", headers: auth_headers_for(admin)
      expect(json.dig("data", "status")).to eq("draft")

      get "/api/v1/patches", params: { status: "draft" }, headers: auth_headers_for(admin)
      expect(json.fetch("data").map { |p| p["number"] }).to eq([ number ])

      get "/api/v1/patches", headers: auth_headers_for(admin)
      expect(json.fetch("data")).to be_empty

      get "/api/v1/patches", params: { status: "old" }, headers: auth_headers_for(admin)
      expect(response).to have_http_status(:bad_request)
    end

    it "gives a Patch's previous and next published numbers, skipping drafts" do
      first = published
      draft
      second = published
      third = published

      get "/api/v1/patches/#{second}"
      expect(json.fetch("data")).to include("previous_number" => first, "next_number" => third)

      get "/api/v1/patches/#{first}"
      expect(json.fetch("data")).to include("previous_number" => nil, "next_number" => second)

      get "/api/v1/patches/#{third}"
      expect(json.fetch("data")).to include("previous_number" => second, "next_number" => nil)
    end

    it "counts the top-level changes under its New, Improved and Fixed headings" do
      item = ->(text, nested = nil) do
        children = [ { "type" => "lic", "children" => [ { "text" => text } ] } ]
        children << { "type" => "ul", "children" => nested } if nested
        { "type" => "li", "children" => children }
      end
      heading = ->(type, text) { { "type" => type, "children" => [ { "text" => text } ] } }
      body = [
        { "type" => "p", "children" => [ { "text" => "Intro." } ] },
        { "type" => "ul", "children" => [ item.call("Before any section") ] },
        heading.call("h2", "New"),
        { "type" => "ul", "children" => [ item.call("One", [ item.call("A detail") ]), item.call("Two") ] },
        heading.call("h3", "Smaller things"),
        { "type" => "ol", "children" => [ item.call("Three") ] },
        heading.call("h2", " improved "),
        { "type" => "p", "children" => [ { "text" => "Faster pages." } ] },
        heading.call("h2", "Fixed"),
        { "type" => "ul", "children" => [ item.call("Four") ] },
        heading.call("h2", "Thanks"),
        { "type" => "ul", "children" => [ item.call("Not a change") ] }
      ]
      number = published(rich_body: body)

      get "/api/v1/patches/#{number}"
      expect(json.dig("data", "counts")).to eq("new" => 3, "improved" => 0, "fixed" => 1)

      get "/api/v1/patches"
      expect(json.dig("data", 0, "counts")).to eq("new" => 3, "improved" => 0, "fixed" => 1)
    end
  end

  describe "the Patch Notes Feature" do
    it "serves Visitors and members only while Live, and staff in Preview, and nobody when Off" do
      number = published

      readers = { "Visitor" => {}, "member" => auth_headers_for(member), "Moderator" => auth_headers_for(moderator),
                  "Admin" => auth_headers_for(admin) }
      expected = {
        "live" => %w[Visitor member Moderator Admin],
        "preview" => %w[Admin],
        "off" => []
      }

      expected.each do |state, allowed|
        set_feature_flag("patch_notes", state)
        readers.each do |who, headers|
          get "/api/v1/patches", headers: headers
          list_status = response.status
          get "/api/v1/patches/#{number}", headers: headers
          wanted = allowed.include?(who) ? 200 : 404
          expect([ list_status, response.status ]).to eq([ wanted, wanted ]), "#{who} in #{state}"
        end
      end
    end

    it "lets Admins write in Preview but not when Off" do
      set_feature_flag("patch_notes", "preview")
      write(as: admin)
      expect(response).to have_http_status(:created)

      set_feature_flag("patch_notes", "off")
      write(as: admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end
