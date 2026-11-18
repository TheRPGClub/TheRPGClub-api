# frozen_string_literal: true

require "rails_helper"

# The Birthday Post (spec #396, ticket #401): every day at 10:00 in the
# club's time zone (America/New_York) the API asks the bot to greet every
# member whose shared Birthday it is. Members share their Birthday through the
# Birth Date endpoint, the job runs under a frozen clock, and what it queued is
# read back through the bot job claim the bot polls.
RSpec.describe "api/v1/birthday post behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Each example starts as a fresh machine: no signal file, so it reads as up.
  before { FileUtils.rm_f(BotJob::WorkSignal.path) }

  def club_time(text) = ActiveSupport::TimeZone["America/New_York"].parse(text)

  # Runs the Birthday Post job at `text`, a time in the club's time zone.
  def post_birthdays_at(text)
    travel_to(club_time(text)) { Birthdays::PostJob.perform_now }
  end

  # The bot's poll: the birthday_post jobs queued since the last one.
  def claim_birthday_posts
    post "/api/v1/bot_jobs/claim", headers: service_headers
    expect(response).to have_http_status(:ok)
    json.fetch("data").select { |job| job["kind"] == "birthday_post" }
  end

  # A member who entered `birth_date` and, unless `shared: false`, shares
  # their Birthday, both through the Birth Date endpoint as the member.
  def member_born(birth_date, shared: true, **attrs)
    member = create(:user, **attrs)
    travel_to(club_time("2026-01-02 12:00")) do
      put "/api/v1/users/#{member.user_id}/birth_date", params: { data: { birth_date: birth_date, birthday_shared: shared } },
        headers: auth_headers_for(member), as: :json
    end
    expect(response).to have_http_status(:ok)
    member
  end

  # The general chat channel (DiscordChannels::GENERAL), where the bot posts.
  let(:general_chat) { "191941851757019136" }

  it "queues one Birthday Post for the club day in general chat, carrying the member due today" do
    member = member_born("1990-05-04")

    post_birthdays_at("2026-05-04 10:00")

    job = claim_birthday_posts.sole
    expect(job.fetch("payload"))
      .to eq("club_date" => "2026-05-04", "user_ids" => [ member.user_id ], "channel_id" => general_chat)
  end

  it "greets everyone due today in one Birthday Post, by name, whether or not they gave a year" do
    carol = member_born("05-04", global_name: "Carol", username: "zed")
    alice = member_born("1990-05-04", global_name: nil, username: "alice")
    bob = member_born("2001-05-04", global_name: "Bob", username: "aaa")
    member_born("1990-05-05")

    post_birthdays_at("2026-05-04 10:00")

    expect(claim_birthday_posts.sole.dig("payload", "user_ids")).to eq([ alice, bob, carol ].map(&:user_id))
  end

  it "orders members by the same names as Upcoming Birthdays, a blank display name falling back to the username" do
    blank = member_born("05-04", global_name: " ", username: "zed")
    ann = member_born("05-04", global_name: "Ann", username: "aaa")

    post_birthdays_at("2026-05-04 10:00")
    travel_to(club_time("2026-05-04 10:00")) { get "/api/v1/birthdays/upcoming", headers: service_headers }

    expect(json.fetch("data").pluck("display_name")).to eq(%w[Ann zed])
    expect(claim_birthday_posts.sole.dig("payload", "user_ids")).to eq([ ann, blank ].map(&:user_id))
  end

  it "queues nothing on a day with no Birthdays" do
    member_born("1990-05-04")

    post_birthdays_at("2026-05-03 10:00")

    expect(claim_birthday_posts).to be_empty
  end

  it "queues nothing new when the job runs again the same day" do
    member_born("1990-05-04")
    post_birthdays_at("2026-05-04 10:00")
    expect(claim_birthday_posts.size).to eq(1)

    post_birthdays_at("2026-05-04 10:00")
    post_birthdays_at("2026-05-04 18:30")

    expect(claim_birthday_posts).to be_empty
  end

  it "greets a member at most once a calendar year, even after they move their Birth Date, and again next year" do
    member = member_born("1990-05-04")
    post_birthdays_at("2026-05-04 10:00")
    expect(claim_birthday_posts.size).to eq(1)

    travel_to(club_time("2026-05-05 12:00")) do
      put "/api/v1/users/#{member.user_id}/birth_date", params: { data: { birth_date: "1990-06-10" } },
        headers: auth_headers_for(member), as: :json
    end
    expect(response).to have_http_status(:ok)

    post_birthdays_at("2026-06-10 10:00")
    expect(claim_birthday_posts).to be_empty

    post_birthdays_at("2027-06-10 10:00")
    expect(claim_birthday_posts.sole.fetch("payload"))
      .to eq("club_date" => "2027-06-10", "user_ids" => [ member.user_id ], "channel_id" => general_chat)
  end

  describe "a 29 February Birthday" do
    it "is greeted on 28 February in a non-leap year, and not again on 1 March" do
      member = member_born("02-29")

      post_birthdays_at("2027-02-27 10:00")
      expect(claim_birthday_posts).to be_empty

      post_birthdays_at("2027-02-28 10:00")
      expect(claim_birthday_posts.sole.fetch("payload"))
        .to eq("club_date" => "2027-02-28", "user_ids" => [ member.user_id ], "channel_id" => general_chat)

      post_birthdays_at("2027-03-01 10:00")
      expect(claim_birthday_posts).to be_empty
    end

    it "is greeted on 29 February in a leap year, alongside 28 February's on their own day" do
      leap = member_born("2000-02-29")
      eve = member_born("02-28")

      post_birthdays_at("2028-02-28 10:00")
      expect(claim_birthday_posts.sole.dig("payload", "user_ids")).to eq([ eve.user_id ])

      post_birthdays_at("2028-02-29 10:00")
      expect(claim_birthday_posts.sole.fetch("payload"))
        .to eq("club_date" => "2028-02-29", "user_ids" => [ leap.user_id ], "channel_id" => general_chat)
    end
  end

  it "never greets a member who does not share their Birthday or has left the server" do
    sharing = member_born("1990-05-04")
    member_born("1990-05-04", shared: false)
    member_born("1990-05-04").update!(server_left_at: Time.utc(2026, 3, 1))

    post_birthdays_at("2026-05-04 10:00")

    expect(claim_birthday_posts.sole.dig("payload", "user_ids")).to eq([ sharing.user_id ])
  end
end
