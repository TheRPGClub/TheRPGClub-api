# frozen_string_literal: true

require "rails_helper"

# Behavior specs for a member's Birth Date (ticket #380): the member reads and
# sets their own, at most twice per calendar month in the club's time zone
# with the first entry counted; Moderators and above set anyone's at any time
# without using up the member's changes. Since api#398 (ADR 0011) the year is
# optional: "05-04" is a Birthday alone.
RSpec.describe "api/v1/birth_date behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }

  def birth_date_path(user = member) = "/api/v1/users/#{user.user_id}/birth_date"

  def set_birth_date(value, as:, user: member)
    put birth_date_path(user), params: { data: { birth_date: value } }, headers: as, as: :json
  end

  describe "a member's own Birth Date" do
    it "can be set and read back by the member" do
      set_birth_date("1990-05-04", as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)

      get birth_date_path, headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("user_id" => member.user_id, "birth_date" => "1990-05-04")
    end

    it "is empty until the member enters it, with both of the month's changes left" do
      get birth_date_path, headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "user_id" => member.user_id, "birth_date" => nil, "changes_left_this_month" => 2, "next_change_on" => nil
      )
    end

    it "can't be read by another member" do
      member.update!(birth_date: BirthDate.new(month: 5, day: 4, year: 1990))

      get birth_date_path, headers: auth_headers_for(create(:user, role_regular: true))

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("1990")
    end

    it "can't be set by another member" do
      set_birth_date("1990-05-04", as: auth_headers_for(create(:user)))

      expect(response).to have_http_status(:forbidden)
      expect(member.reload.birth_date).to be_nil
    end

    it "can be removed by the member" do
      set_birth_date("1990-05-04", as: auth_headers_for(member))
      set_birth_date(nil, as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => nil)
    end

    it "refuses a date that isn't a real date in the past" do
      travel_to Time.utc(2026, 11, 17, 15) do
        set_birth_date("1990-02-30", as: auth_headers_for(member))
        expect(response).to have_http_status(:unprocessable_content)

        set_birth_date("2026-11-18", as: auth_headers_for(member))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("birth_date can't be in the future")
      end

      expect(member.reload.birth_date).to be_nil
    end

    it "requires birth_date in the data" do
      put birth_date_path, params: { data: { something: 1 } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "birth_date required")
    end

    it "requires authentication" do
      get birth_date_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "a Birth Date without a year" do
    it "is accepted as MM-DD and served back the same way" do
      set_birth_date("05-04", as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => "05-04")

      get birth_date_path, headers: auth_headers_for(member)

      expect(json.fetch("data")).to include("birth_date" => "05-04")
    end

    it "can be 29 February" do
      set_birth_date("02-29", as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => "02-29")
    end

    it "refuses a month and day that don't exist" do
      %w[02-30 04-31 13-01 00-10 05-00 5-4-1990 05/04].each do |value|
        set_birth_date(value, as: auth_headers_for(member))

        expect(response).to have_http_status(:unprocessable_content), value
        expect(json.fetch("error")).to eq("birth_date must be a date (YYYY-MM-DD, or MM-DD without the year)")
      end

      expect(member.reload.birth_date).to be_nil
    end

    it "keeps today's rules for a date with a year" do
      travel_to Time.utc(2026, 11, 17, 15) do
        set_birth_date("1899-12-31", as: auth_headers_for(member))
        expect(json.fetch("error")).to eq("birth_date can't be before 1900")

        set_birth_date("1991-02-29", as: auth_headers_for(member))
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "can gain or lose its year, each counting as a change" do
      travel_to Time.utc(2026, 11, 17, 15) do
        set_birth_date("05-04", as: auth_headers_for(member))
        set_birth_date("1990-05-04", as: auth_headers_for(member))

        expect(json.fetch("data")).to include("birth_date" => "1990-05-04", "changes_left_this_month" => 0)

        set_birth_date("05-04", as: auth_headers_for(member))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("next_change_on")).to eq("2026-12-01")
      end
    end

    it "doesn't count setting the same day and month again" do
      set_birth_date("05-04", as: auth_headers_for(member))
      set_birth_date("05-04", as: auth_headers_for(member))

      expect(json.fetch("data")).to include("changes_left_this_month" => 1)
    end
  end

  describe "the limit of two changes per calendar month" do
    it "counts the first entry, and refuses a third change naming the first day of next month" do
      travel_to Time.utc(2026, 11, 17, 15) do
        set_birth_date("1990-05-04", as: auth_headers_for(member))
        expect(json.fetch("data")).to include("changes_left_this_month" => 1, "next_change_on" => nil)

        set_birth_date("1990-05-14", as: auth_headers_for(member))
        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("changes_left_this_month" => 0, "next_change_on" => "2026-12-01")

        set_birth_date("1991-05-14", as: auth_headers_for(member))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("next_change_on")).to eq("2026-12-01")
        expect(json.fetch("error")).to include("1 December 2026")
      end

      expect(member.reload.birth_date).to eq(BirthDate.new(month: 5, day: 14, year: 1990))
    end

    it "gives two new changes on the first day of the next month" do
      travel_to(Time.utc(2026, 11, 3)) { 2.times { |i| set_birth_date("1990-05-0#{i + 1}", as: auth_headers_for(member)) } }

      travel_to Time.utc(2026, 12, 1, 12) do
        set_birth_date("1990-05-09", as: auth_headers_for(member))

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("birth_date" => "1990-05-09", "changes_left_this_month" => 1)
      end
    end

    it "reads the calendar month in the club's time zone" do
      # 03:00 UTC on 1 December is still 30 November in US Eastern.
      travel_to(Time.utc(2026, 11, 20)) { set_birth_date("1990-05-04", as: auth_headers_for(member)) }

      travel_to Time.utc(2026, 12, 1, 3) do
        set_birth_date("1990-05-05", as: auth_headers_for(member))
        set_birth_date("1990-05-06", as: auth_headers_for(member))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("next_change_on")).to eq("2026-12-01")
      end
    end

    it "doesn't count setting the date it already has" do
      set_birth_date("1990-05-04", as: auth_headers_for(member))
      set_birth_date("1990-05-04", as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("changes_left_this_month" => 1)
    end
  end

  describe "staff" do
    let(:moderator) { create(:user, role_moderator: true) }

    it "can read any member's Birth Date" do
      member.update!(birth_date: BirthDate.new(month: 5, day: 4, year: 1990))

      get birth_date_path, headers: auth_headers_for(moderator)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => "1990-05-04")
    end

    it "can set a member's Birth Date past the limit without using up the member's changes" do
      travel_to Time.utc(2026, 11, 17, 15) do
        3.times { |i| set_birth_date("1980-01-0#{i + 1}", as: auth_headers_for(moderator)) }
        expect(response).to have_http_status(:ok)

        2.times { |i| set_birth_date("1990-05-0#{i + 1}", as: auth_headers_for(member)) }
        expect(response).to have_http_status(:ok)

        set_birth_date("1970-07-07", as: auth_headers_for(moderator))
        expect(response).to have_http_status(:ok)
      end

      expect(member.reload.birth_date).to eq(BirthDate.new(month: 7, day: 7, year: 1970))
    end

    it "can set or correct a member's Birth Date without a year" do
      set_birth_date("1990-05-04", as: auth_headers_for(member))

      set_birth_date("05-14", as: auth_headers_for(moderator))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => "05-14", "changes_left_this_month" => 1)

      get birth_date_path, headers: auth_headers_for(member)

      expect(json.fetch("data")).to include("birth_date" => "05-14")
    end

    it "can set their own Birth Date without the limit" do
      3.times { |i| set_birth_date("1980-01-0#{i + 1}", as: auth_headers_for(moderator), user: moderator) }

      expect(response).to have_http_status(:ok)
      expect(moderator.reload.birth_date).to eq(BirthDate.new(month: 1, day: 3, year: 1980))
    end

    it "404s for a member the API doesn't know" do
      put "/api/v1/users/999999999999999999/birth_date", params: { data: { birth_date: "1990-05-04" } },
        headers: auth_headers_for(moderator), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "through the bot" do
    def bot_set(value, acting:, user: member)
      put birth_date_path(user), params: { data: { birth_date: value, acting_user_id: acting.user_id } },
        headers: service_headers, as: :json
    end

    it "sets and reads the acting member's own, within the limit" do
      3.times { |i| bot_set("1990-05-0#{i + 1}", acting: member) }

      expect(response).to have_http_status(:unprocessable_content)

      get birth_date_path, params: { acting_user_id: member.user_id }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("birth_date" => "1990-05-02", "changes_left_this_month" => 0)
    end

    it "lets a Moderator acting through it set any member's without the limit" do
      moderator = create(:user, role_moderator: true)
      3.times { |i| bot_set("1980-01-0#{i + 1}", acting: moderator) }

      expect(response).to have_http_status(:ok)
      expect(member.reload.birth_date).to eq(BirthDate.new(month: 1, day: 3, year: 1980))
    end

    it "refuses another member acting through it" do
      member.update!(birth_date: BirthDate.new(month: 5, day: 4, year: 1990))

      get birth_date_path, params: { acting_user_id: create(:user).user_id }, headers: service_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "requires the acting member" do
      get birth_date_path, headers: service_headers

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "acting_user_id required")
    end
  end

  it "is never part of the member's public profile" do
    member.update!(birth_date: BirthDate.new(month: 5, day: 4, year: 1990))

    get "/api/v1/users/#{member.user_id}", headers: auth_headers_for(create(:user))

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).not_to have_key("birth_date")
  end
end
