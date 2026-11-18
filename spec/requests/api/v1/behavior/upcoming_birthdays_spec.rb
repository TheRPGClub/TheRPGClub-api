# frozen_string_literal: true

require "rails_helper"

# Behavior specs for Upcoming Birthdays (spec #396, ticket api#400): the
# shared Birthdays falling from today through today + 29 days, in club days
# (America/New_York), for any signed-in member or the bot. Never the year or
# the age.
RSpec.describe "api/v1/birthdays/upcoming behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:viewer) { create(:user) }

  def upcoming_birthdays(as: auth_headers_for(viewer))
    get "/api/v1/birthdays/upcoming", headers: as
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def sharing_member(birthday, year: nil, **attributes)
    month, day = birthday.split("-").map(&:to_i)
    create(:user, birth_date: BirthDate.new(month: month, day: day, year: year), birthday_shared: true, **attributes)
  end

  # Noon in New York on the given club day.
  def on_club_day(date, &)
    travel_to(Time.find_zone!("America/New_York").parse("#{date} 12:00"), &)
  end

  it "lists a shared Birthday with the member's names, avatar, day and month, and the date it falls on" do
    member = sharing_member("05-04", year: 1990, global_name: "Ava", discord_avatar: "abc123")

    on_club_day("2026-04-20") do
      expect(upcoming_birthdays).to eq([
        { "user_id" => member.user_id, "display_name" => "Ava", "username" => member.username,
          "global_name" => "Ava", "discord_avatar" => "abc123",
          "avatar_url" => "/api/v1/users/#{member.user_id}/avatar",
          "month" => 5, "day" => 4, "on" => "2026-05-04", "today" => false }
      ])
    end
  end

  def listed_on(date)
    on_club_day(date) { upcoming_birthdays.map { |entry| [ entry.fetch("user_id"), entry.fetch("on") ] } }
  end

  describe "who's included" do
    it "leaves out a Birth Date whose Birthday isn't shared" do
      create(:user, birth_date: BirthDate.new(month: 5, day: 4, year: 1990))
      shared = sharing_member("05-05")

      expect(listed_on("2026-05-01")).to eq([ [ shared.user_id, "2026-05-05" ] ])
    end

    it "leaves out members who have left the server" do
      sharing_member("05-04", server_left_at: 1.day.ago)

      expect(listed_on("2026-05-01")).to eq([])
    end

    it "lists a Birthday without a year like one with it" do
      yearless = sharing_member("05-04")

      expect(listed_on("2026-05-01")).to eq([ [ yearless.user_id, "2026-05-04" ] ])
    end
  end

  describe "the 30-day window" do
    it "runs from today through today + 29 days" do
      today = sharing_member("05-01")
      last = sharing_member("05-30")
      sharing_member("04-30")
      sharing_member("05-31")

      expect(listed_on("2026-05-01")).to eq([ [ today.user_id, "2026-05-01" ], [ last.user_id, "2026-05-30" ] ])
    end

    it "crosses the year end into next year's dates" do
      december = sharing_member("12-31")
      january = sharing_member("01-10")
      sharing_member("12-15")

      expect(listed_on("2026-12-20")).to eq([ [ december.user_id, "2026-12-31" ], [ january.user_id, "2027-01-10" ] ])
    end

    it "counts today in club time, not UTC" do
      new_years_eve = sharing_member("12-31")
      new_years_day = sharing_member("01-01")

      # 03:00 UTC on 1 January 2027 is still 31 December in New York.
      travel_to Time.utc(2027, 1, 1, 3) do
        expect(upcoming_birthdays.map { |entry| entry.values_at("user_id", "on", "today") }).to eq([
          [ new_years_eve.user_id, "2026-12-31", true ],
          [ new_years_day.user_id, "2027-01-01", false ]
        ])
      end
    end
  end

  describe "a 29 February Birthday" do
    let!(:leapling) { sharing_member("02-29", year: 2000) }

    it "falls on 28 February in a year that isn't a leap year" do
      on_club_day("2027-02-28") do
        expect(upcoming_birthdays).to contain_exactly(
          include("user_id" => leapling.user_id, "month" => 2, "day" => 29, "on" => "2027-02-28", "today" => true)
        )
      end

      expect(listed_on("2027-03-01")).to eq([])
    end

    it "falls on 29 February in a leap year" do
      expect(listed_on("2028-02-28")).to eq([ [ leapling.user_id, "2028-02-29" ] ])

      on_club_day("2028-02-29") do
        expect(upcoming_birthdays).to contain_exactly(include("on" => "2028-02-29", "today" => true))
      end
    end
  end

  it "orders by the date it falls on, then by display name" do
    sharing_member("05-03", global_name: "zed")
    sharing_member("05-03", global_name: nil, username: "Ann")
    sharing_member("05-03", global_name: "bob")
    sharing_member("05-02", global_name: "Zoe")

    on_club_day("2026-05-01") do
      expect(upcoming_birthdays.pluck("display_name", "on")).to eq([
        [ "Zoe", "2026-05-02" ], [ "Ann", "2026-05-03" ], [ "bob", "2026-05-03" ], [ "zed", "2026-05-03" ]
      ])
    end
  end

  it "never shows the year or the age" do
    sharing_member("05-04", year: 1987, user_id: "100000000000000001", username: "ava", global_name: "Ava")

    on_club_day("2026-05-01") do
      entries = upcoming_birthdays

      expect(entries.first.keys).to contain_exactly(
        "user_id", "display_name", "username", "global_name", "discord_avatar", "avatar_url",
        "month", "day", "on", "today"
      )
      expect(response.body).not_to include("1987")
      expect(response.body).not_to include("39")
    end
  end

  # Decision 11 (bot#1558's empty state): `next` is the first shared Birthday
  # after the 30 days, with no member, and null when nobody shares one.
  describe "the next Birthday beyond the 30 days" do
    def next_birthday(on:)
      on_club_day(on) do
        get "/api/v1/birthdays/upcoming", headers: auth_headers_for(viewer)
        expect(response).to have_http_status(:ok)
        json.fetch("next")
      end
    end

    it "is the first shared Birthday after the window, its day, month and date only" do
      sharing_member("05-04", year: 1987, global_name: "Ava")
      sharing_member("08-15")
      sharing_member("07-01", global_name: "Bo")
      create(:user, birth_date: BirthDate.new(month: 6, day: 2, year: nil))
      sharing_member("06-03", server_left_at: 1.day.ago)

      expect(next_birthday(on: "2026-05-01")).to eq("month" => 7, "day" => 1, "on" => "2026-07-01")
      expect(response.body).not_to include("Bo")
      expect(response.body).not_to include("1987")
    end

    it "starts the day after the window's last day" do
      sharing_member("05-30")
      sharing_member("05-31")

      expect(next_birthday(on: "2026-05-01")).to eq("month" => 5, "day" => 31, "on" => "2026-05-31")
    end

    it "is next year's date when every shared Birthday is in the window" do
      sharing_member("05-04")

      expect(next_birthday(on: "2026-05-01")).to eq("month" => 5, "day" => 4, "on" => "2027-05-04")
    end

    it "crosses the year end" do
      sharing_member("01-25")
      sharing_member("12-10")

      expect(next_birthday(on: "2026-12-20")).to eq("month" => 1, "day" => 25, "on" => "2027-01-25")
    end

    it "puts a 29 February Birthday on 28 February in a year that isn't a leap year" do
      sharing_member("02-29")

      expect(next_birthday(on: "2027-01-01")).to eq("month" => 2, "day" => 29, "on" => "2027-02-28")
      expect(next_birthday(on: "2027-12-01")).to eq("month" => 2, "day" => 29, "on" => "2028-02-29")
    end

    it "is null when nobody shares a Birthday" do
      create(:user, birth_date: BirthDate.new(month: 5, day: 4, year: nil))

      expect(next_birthday(on: "2026-05-01")).to be_nil
    end
  end

  describe "access" do
    it "answers the bot's service token" do
      member = sharing_member("05-04")

      on_club_day("2026-05-01") do
        expect(upcoming_birthdays(as: service_headers).pluck("user_id")).to eq([ member.user_id ])
      end
    end

    it "requires authentication" do
      get "/api/v1/birthdays/upcoming"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
