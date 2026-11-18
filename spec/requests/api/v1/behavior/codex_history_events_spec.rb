# frozen_string_literal: true

require "rails_helper"

# Club History (spec #397, ticket #408): History Events under
# /api/v1/codex/history_events. Admins and Superadmins keep the record;
# anyone, Visitors included, reads it while the Club Codex is Live.
RSpec.describe "api/v1/codex/history_events behavior", type: :request do
  let(:admin) { create(:user, role_member: true, role_admin: true, global_name: "Ada") }
  let(:other_admin) { create(:user, role_member: true, role_admin: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let(:regular) { create(:user, role_member: true, role_regular: true) }
  let(:member) { create(:user, role_member: true) }

  let(:founding) do
    { title: "The club is founded", kind: "founding", occurred_on: "2016-01-01", date_precision: "year" }
  end

  def add_history_event(as:, is_dev: false, **data)
    post "/api/v1/codex/history_events", params: { data: founding.merge(data) },
      headers: auth_headers_for(as, is_dev: is_dev), as: :json
  end

  describe "reading Club History signed out" do
    it "lists and shows History Events to a Visitor when Live" do
      event = create(:codex_entry, :history_event, author: admin, title: "The club moves to Discord",
        kind: "platform", occurred_on: Date.new(2018, 3, 1), date_precision: "month")

      get "/api/v1/codex/history_events"
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |entry| entry["title"] }).to eq([ "The club moves to Discord" ])

      get "/api/v1/codex/history_events/#{event.id}"
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("part" => "history_event", "title" => "The club moves to Discord",
        "kind" => "platform", "occurred_on" => "2018-03-01", "date_precision" => "month",
        "viewer" => { "can_edit" => false, "can_delete" => false },
        "author" => { "user_id" => admin.user_id, "name" => "Ada",
                      "avatar_url" => "/api/v1/users/#{admin.user_id}/avatar" })
    end

    it "hides Club History from a Visitor in Preview and Off" do
      event = create(:codex_entry, :history_event, author: admin)

      %w[preview off].each do |state|
        set_feature_flag("club_codex", state)

        get "/api/v1/codex/history_events"
        expect(response).to have_http_status(:not_found), "the list was #{response.status} in #{state}"
        expect(json).to eq("error" => "not_found")

        get "/api/v1/codex/history_events/#{event.id}"
        expect(response).to have_http_status(:not_found), "the History Event was #{response.status} in #{state}"
      end
    end

    it "reads a bad or expired token as signed out" do
      create(:codex_entry, :history_event, author: admin)

      get "/api/v1/codex/history_events", headers: { "Authorization" => "Bearer not-a-token" }
      expect(response).to have_http_status(:ok)

      set_feature_flag("club_codex", "preview")
      get "/api/v1/codex/history_events", headers: { "Authorization" => "Bearer not-a-token" }
      expect(response).to have_http_status(:not_found)
    end

    it "still needs a sign-in to write" do
      event = create(:codex_entry, :history_event, author: admin)

      post "/api/v1/codex/history_events", params: { data: { title: "T" } }, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch "/api/v1/codex/history_events/#{event.id}", params: { data: { title: "T" } }, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "/api/v1/codex/history_events/#{event.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "adding a History Event" do
    it "lets an Admin add one, credited to them" do
      add_history_event(as: admin, rich_body: [ { "type" => "p", "children" => [ { "text" => "Day one." } ] } ],
        body: "Day one.")

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "part" => "history_event", "title" => "The club is founded", "kind" => "founding",
        "occurred_on" => "2016-01-01", "date_precision" => "year", "body" => "Day one.",
        "rich_body" => [ { "type" => "p", "children" => [ { "text" => "Day one." } ] } ],
        "viewer" => { "can_edit" => true, "can_delete" => true }
      )
      expect(json.dig("data", "author", "user_id")).to eq(admin.user_id)

      get "/api/v1/codex/history_events/#{json.dig('data', 'id')}"
      expect(json.dig("data", "title")).to eq("The club is founded")
    end

    it "lets a Superadmin add one" do
      add_history_event(as: member, is_dev: true)

      expect(response).to have_http_status(:created)
    end

    it "refuses Moderators, Regulars and members" do
      [ moderator, regular, member ].each do |user|
        add_history_event(as: user)

        expect(response).to have_http_status(:forbidden)
        expect(json).to include("error" => "forbidden", "message" => "Only Admins can change Club History.")
      end

      get "/api/v1/codex/history_events"
      expect(json.fetch("data")).to be_empty
    end

    it "adds one for an Admin the bot names, and refuses a Moderator it names" do
      post "/api/v1/codex/history_events", params: { data: founding.merge(acting_user_id: admin.user_id) },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:created)

      post "/api/v1/codex/history_events", params: { data: founding.merge(acting_user_id: moderator.user_id) },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "editing and deleting a History Event" do
    let!(:event) { create(:codex_entry, :history_event, author: admin, title: "Staff change") }

    def edit(as:, is_dev: false, **data)
      patch "/api/v1/codex/history_events/#{event.id}", params: { data: { title: "Staff changes" }.merge(data) },
        headers: auth_headers_for(as, is_dev: is_dev), as: :json
    end

    def delete_it(as:)
      delete "/api/v1/codex/history_events/#{event.id}", headers: auth_headers_for(as)
    end

    it "lets another Admin edit and delete it" do
      edit(as: other_admin, kind: "staff")
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("title" => "Staff changes", "kind" => "staff")
      expect(json.dig("data", "author", "user_id")).to eq(admin.user_id)

      delete_it(as: other_admin)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("id" => event.id, "deleted" => true)

      get "/api/v1/codex/history_events/#{event.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "lets a Superadmin edit and delete it" do
      edit(as: member, is_dev: true)
      expect(response).to have_http_status(:ok)

      delete "/api/v1/codex/history_events/#{event.id}", headers: auth_headers_for(member, is_dev: true)
      expect(response).to have_http_status(:ok)
    end

    it "refuses Moderators and Regulars, the author's rights included once they are no longer an Admin" do
      admin.update!(role_admin: false, role_moderator: true)

      [ moderator, regular, admin ].each do |user|
        edit(as: user)
        expect(response).to have_http_status(:forbidden)
        expect(json.fetch("message")).to eq("Only Admins can change Club History.")

        delete_it(as: user)
        expect(response).to have_http_status(:forbidden)
      end

      get "/api/v1/codex/history_events/#{event.id}"
      expect(json.dig("data", "title")).to eq("Staff change")
    end

    it "edits and deletes for the Admin the bot names" do
      patch "/api/v1/codex/history_events/#{event.id}",
        params: { data: { title: "From Discord", acting_user_id: moderator.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/codex/history_events/#{event.id}",
        params: { data: { title: "From Discord", acting_user_id: other_admin.user_id } },
        headers: service_headers, as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/codex/history_events/#{event.id}", headers: service_headers
      expect(response).to have_http_status(:bad_request)

      delete "/api/v1/codex/history_events/#{event.id}", params: { acting_user_id: other_admin.user_id },
        headers: service_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the viewer flags" do
    let!(:event) { create(:codex_entry, :history_event, author: admin) }

    it "show edit and delete rights to Admins and Superadmins only" do
      yes = { "can_edit" => true, "can_delete" => true }
      no = { "can_edit" => false, "can_delete" => false }
      viewer_for = lambda do |headers, params = {}|
        get "/api/v1/codex/history_events/#{event.id}", params: params, headers: headers
        json.dig("data", "viewer")
      end

      expect(viewer_for.call(auth_headers_for(other_admin))).to eq(yes)
      expect(viewer_for.call(auth_headers_for(member, is_dev: true))).to eq(yes)
      expect(viewer_for.call(auth_headers_for(moderator))).to eq(no)
      expect(viewer_for.call(auth_headers_for(regular))).to eq(no)
      expect(viewer_for.call({})).to eq(no)
      expect(viewer_for.call(service_headers, acting_user_id: other_admin.user_id)).to eq(yes)
      expect(viewer_for.call(service_headers, acting_user_id: moderator.user_id)).to eq(no)

      get "/api/v1/codex/history_events", headers: auth_headers_for(admin)
      expect(json.dig("data", 0, "viewer")).to eq(yes)
    end
  end

  describe "a History Event's fields" do
    def refused_with(message)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_entry", "message" => message)
    end

    it "needs a title of at most 100 characters" do
      add_history_event(as: admin, title: "  ")
      refused_with("Title can't be blank")

      add_history_event(as: admin, title: "a" * 101)
      refused_with("Title is too long (maximum is 100 characters)")

      add_history_event(as: admin, title: "a" * 100)
      expect(response).to have_http_status(:created)
    end

    it "needs a History Event Kind from the five, on add and on edit" do
      add_history_event(as: admin, kind: nil)
      refused_with("Kind must be one of founding, staff, platform, rules, milestone")

      add_history_event(as: admin, kind: "gossip")
      refused_with("Kind must be one of founding, staff, platform, rules, milestone")

      %w[founding staff platform rules milestone].each do |kind|
        add_history_event(as: admin, kind: kind)
        expect(response).to have_http_status(:created), "#{kind} was refused"
      end

      patch "/api/v1/codex/history_events/#{json.dig('data', 'id')}", params: { data: { kind: "gossip" } },
        headers: auth_headers_for(admin), as: :json
      refused_with("Kind must be one of founding, staff, platform, rules, milestone")
    end

    it "needs a date and its precision" do
      add_history_event(as: admin, occurred_on: nil, date_precision: nil)
      refused_with("Occurred on can't be blank and Date precision can't be blank")

      add_history_event(as: admin, date_precision: nil)
      refused_with("Date precision can't be blank")

      add_history_event(as: admin, occurred_on: nil)
      refused_with("Occurred on can't be blank")

      add_history_event(as: admin, date_precision: "decade")
      refused_with("Date precision must be one of day, month, year")

      add_history_event(as: admin, occurred_on: "2018-02-30", date_precision: "day")
      refused_with("Occurred on must be a date (YYYY-MM-DD)")
    end

    it "needs body whenever rich_body is given" do
      add_history_event(as: admin, rich_body: [ { "type" => "p", "children" => [ { "text" => "Hi." } ] } ])
      refused_with("Body can't be blank")

      add_history_event(as: admin, rich_body: [ { "type" => "p", "children" => [ { "text" => "Hi." } ] } ],
        body: "Hi.")
      expect(response).to have_http_status(:created)

      add_history_event(as: admin)
      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("rich_body" => nil, "body" => nil)
    end

    it "refuses a field that isn't text" do
      add_history_event(as: admin, title: { "a" => 1 })
      refused_with("title must be text")
    end

    it "pulls mentions from body" do
      mentioned = create(:user, user_id: "111111111111111111", global_name: "Bo")

      add_history_event(as: admin, kind: "staff", rich_body: [ { "type" => "p" } ],
        body: "<@#{mentioned.user_id}> joins the staff.")

      get "/api/v1/codex/history_events/#{json.dig('data', 'id')}"
      expect(json.dig("data", "mentions", mentioned.user_id, "name")).to eq("Bo")
    end
  end

  describe "dates at each precision" do
    it "stores and reads back a day, a month and a year, keeping a month or year at the start of its period" do
      add_history_event(as: admin, occurred_on: "2018-03-14", date_precision: "day")
      expect(json.dig("data", "occurred_on")).to eq("2018-03-14")
      expect(json.dig("data", "date_precision")).to eq("day")

      add_history_event(as: admin, occurred_on: "2018-03-14", date_precision: "month")
      month_id = json.dig("data", "id")
      get "/api/v1/codex/history_events/#{month_id}"
      expect(json.fetch("data")).to include("occurred_on" => "2018-03-01", "date_precision" => "month")

      add_history_event(as: admin, occurred_on: "2016-07-20", date_precision: "year")
      get "/api/v1/codex/history_events/#{json.dig('data', 'id')}"
      expect(json.fetch("data")).to include("occurred_on" => "2016-01-01", "date_precision" => "year")
    end

    it "keeps the date at its period's start when only the precision changes" do
      add_history_event(as: admin, occurred_on: "2018-03-14", date_precision: "day")

      patch "/api/v1/codex/history_events/#{json.dig('data', 'id')}", params: { data: { date_precision: "year" } },
        headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("occurred_on" => "2018-01-01", "date_precision" => "year")
    end
  end

  describe "listing Club History" do
    def titles = json.fetch("data").map { |entry| entry["title"] }

    it "orders History Events by date, then id, whatever their precision" do
      create(:codex_entry, :history_event, author: admin, title: "Spring 2018", occurred_on: Date.new(2018, 3, 1),
        date_precision: "month")
      create(:codex_entry, :history_event, author: admin, title: "Founded", occurred_on: Date.new(2016, 1, 1),
        date_precision: "year")
      create(:codex_entry, :history_event, author: admin, title: "The 14th", occurred_on: Date.new(2018, 3, 14),
        date_precision: "day")
      create(:codex_entry, :history_event, author: admin, title: "Also 2018", occurred_on: Date.new(2018, 1, 1),
        date_precision: "year")
      create(:codex_entry, :history_event, author: admin, title: "March 2018 too", occurred_on: Date.new(2018, 3, 1),
        date_precision: "day")
      create(:codex_entry, :fun_fact, author: admin)

      get "/api/v1/codex/history_events"

      expect(titles).to eq([ "Founded", "Also 2018", "Spring 2018", "March 2018 too", "The 14th" ])

      get "/api/v1/codex/history_events", params: { per: 2, page: 2 }
      expect(titles).to eq([ "Spring 2018", "March 2018 too" ])
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 3, "count" => 5, "per" => 2)
    end

    it "keeps one History Event Kind with `kind`" do
      create(:codex_entry, :history_event, author: admin, title: "Founded", kind: "founding")
      create(:codex_entry, :history_event, author: admin, title: "Ada joins the staff", kind: "staff")
      create(:codex_entry, :history_event, author: admin, title: "Bo joins the staff", kind: "staff")

      get "/api/v1/codex/history_events", params: { kind: "staff" }
      expect(titles).to eq([ "Ada joins the staff", "Bo joins the staff" ])

      get "/api/v1/codex/history_events", params: { kind: "rules" }
      expect(titles).to be_empty

      get "/api/v1/codex/history_events", params: { kind: "gossip" }
      expect(response).to have_http_status(:bad_request)
      expect(json).to include("error" => "invalid_kind")
    end
  end

  describe "the feature gate for signed-in callers" do
    it "lets Admins read and write in Preview, and hides Club History from other members" do
      set_feature_flag("club_codex", "preview")

      add_history_event(as: admin)
      expect(response).to have_http_status(:created)
      get "/api/v1/codex/history_events", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)

      get "/api/v1/codex/history_events", headers: auth_headers_for(regular)
      expect(response).to have_http_status(:not_found)
    end

    it "hides Club History from everyone, Admins included, when Off" do
      set_feature_flag("club_codex", "off")

      add_history_event(as: admin)
      expect(response).to have_http_status(:not_found)
      get "/api/v1/codex/history_events", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end
