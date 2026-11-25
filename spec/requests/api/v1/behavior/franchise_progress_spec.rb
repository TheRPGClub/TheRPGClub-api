# frozen_string_literal: true

require "rails_helper"

# Franchise Progress (spec api#457, ticket api#461; GLOSSARY.md "Conquered",
# "Spin-off"). A member's meters for a Franchise (Mainline, Mainline and
# spin-offs, Spin-offs only), the members table, and Conquests with their
# bot announcement. Gated by the `franchise_progress` Feature.
RSpec.describe "Franchise Progress", type: :request do
  let(:member) { create(:user, global_name: "Mara") }
  let(:other) { create(:user, global_name: "Ivo") }
  let(:franchise) { create(:franchise, name: "Final Fantasy") }
  let(:ff1) { create(:game, title: "Final Fantasy", initial_release_date: Date.new(1987, 12, 18)) }
  let(:ff2) { create(:game, title: "Final Fantasy II", initial_release_date: Date.new(1988, 12, 17)) }
  let(:tactics) { create(:game, title: "Final Fantasy Tactics", initial_release_date: Date.new(1997, 6, 20)) }

  def link(game, mainline: false, into: franchise)
    GamedbGameFranchise.create!(franchise: into, game: game, source: "igdb", mainline: mainline)
  end

  def manual(user, game, minutes)
    create(:manual_playtime, user: user, game: game, platform: nil, minutes: minutes)
  end

  def progress(user_id: nil, as: member, of: franchise)
    get "/api/v1/franchises/#{of.franchise_id}/progress", params: { user_id: user_id }.compact,
      headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def members_table(as: member, of: franchise)
    get "/api/v1/franchises/#{of.franchise_id}/progress/members", headers: auth_headers_for(as)
    expect(response).to have_http_status(:ok)
    json.fetch("data")
  end

  def complete(game, as: member, user: member, announce: nil)
    body = { gamedb_game_id: game.game_id, completion_type: "Main Story" }
    body[:announce] = announce unless announce.nil?
    post "/api/v1/users/#{user.user_id}/completions", params: { data: body }, headers: auth_headers_for(as), as: :json
    expect(response).to have_http_status(:created)
    UserGameCompletion.find(json.dig("data", "completion_id"))
  end

  def conquest_jobs = BotJob.where(kind: "franchise_conquest")

  describe "GET /franchises/:id/progress" do
    before do
      link(ff1, mainline: true)
      link(ff2, mainline: true)
      link(tactics)
    end

    it "gives the viewer's meters per group, with Playtime" do
      create(:completion, user: member, game: ff1, completion_type: "Completionist")
      create(:completion, user: member, game: tactics)
      manual(member, ff1, 1200)
      manual(member, ff2, 300)
      manual(member, tactics, 90)

      data = progress

      expect(data).to include("user_id" => member.user_id, "franchise_id" => franchise.franchise_id,
        "conquered_at" => nil)
      expect(data.fetch("meters")).to eq(
        "mainline" => { "done" => 1, "total" => 2, "playtime_minutes" => 1500 },
        "all" => { "done" => 2, "total" => 3, "playtime_minutes" => 1590 },
        "spin_offs" => { "done" => 1, "total" => 1, "playtime_minutes" => 90 }
      )
    end

    it "lists the Mainline and spin-off games with done, the Completion type and Playtime" do
      create(:completion, user: member, game: ff1, completion_type: "Main Story")
      create(:completion, user: member, game: ff1, completion_type: "Completionist")
      manual(member, ff2, 45)

      games = progress.fetch("games")

      expect(games.fetch("mainline")).to match([
        include("game_id" => ff1.game_id, "title" => "Final Fantasy", "release_year" => 1987, "cover_url" => nil,
          "done" => true, "completion_type" => "Completionist", "playtime_minutes" => 0),
        include("game_id" => ff2.game_id, "done" => false, "completion_type" => nil, "playtime_minutes" => 45)
      ])
      expect(games.fetch("spin_offs")).to match([ include("game_id" => tactics.game_id, "done" => false) ])
    end

    it "counts a game once however many Completions it has" do
      create(:completion, user: member, game: ff1)
      create(:completion, user: member, game: ff1, completion_type: "Completionist")

      expect(progress.dig("meters", "mainline")).to include("done" => 1, "total" => 2)
    end

    it "leaves Add-ons out, even ones marked Mainline" do
      dlc = create(:game, title: "Final Fantasy II DLC", parent_igdb_id: 4242)
      link(dlc, mainline: true)
      create(:completion, user: member, game: dlc)
      manual(member, dlc, 600)

      data = progress

      expect(data.dig("meters", "mainline")).to eq("done" => 0, "total" => 2, "playtime_minutes" => 0)
      expect(data.dig("meters", "all", "total")).to eq(3)
      expect(data.fetch("games").values.flatten.map { |game| game.fetch("game_id") }).not_to include(dlc.game_id)
    end

    it "doesn't count an Alternate Version's Completion for the game" do
      remaster = create(:game, title: "Final Fantasy Pixel Remaster")
      GamedbGameAlternate.create!(game: ff1, alternate_game: remaster)
      create(:completion, user: member, game: remaster)

      expect(progress.dig("meters", "mainline", "done")).to eq(0)
    end

    it "shows another member's progress with user_id, and anyone's to the bot" do
      create(:completion, user: other, game: ff2)

      expect(progress(user_id: other.user_id).dig("meters", "mainline", "done")).to eq(1)

      get "/api/v1/franchises/#{franchise.franchise_id}/progress", params: { user_id: other.user_id },
        headers: service_headers
      expect(json.dig("data", "user_id")).to eq(other.user_id)
    end

    it "is 400 for the bot without user_id, and 404 for an unknown member or Franchise" do
      get "/api/v1/franchises/#{franchise.franchise_id}/progress", headers: service_headers
      expect(response).to have_http_status(:bad_request)

      get "/api/v1/franchises/#{franchise.franchise_id}/progress", params: { user_id: "1" },
        headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/franchises/0/progress", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "an empty meter" do
    it "has total 0 when the Franchise has no Mainline games" do
      link(tactics)
      create(:completion, user: member, game: tactics)

      expect(progress.fetch("meters")).to include(
        "mainline" => { "done" => 0, "total" => 0, "playtime_minutes" => 0 },
        "spin_offs" => { "done" => 1, "total" => 1, "playtime_minutes" => 0 }
      )
    end
  end

  describe "GET /franchises/:id/progress/members" do
    it "lists members with Playtime or a Completion: Conquered first by when, then Mainline %, then Playtime" do
      link(ff1, mainline: true)
      link(ff2, mainline: true)
      link(tactics)
      early, late, half_long, half_short, spin_only, playtime_only =
        Array.new(6) { create(:user) }
      create(:user) # nothing in the Franchise
      [ early, late ].each { |user| [ ff1, ff2 ].each { |game| create(:completion, user: user, game: game) } }
      UserFranchiseConquest.create!(user: late, franchise: franchise, conquered_at: 1.day.ago)
      UserFranchiseConquest.create!(user: early, franchise: franchise, conquered_at: 1.year.ago)
      create(:completion, user: half_short, game: ff1)
      create(:completion, user: half_long, game: ff2)
      manual(half_long, ff2, 900)
      manual(half_short, tactics, 100)
      create(:completion, user: spin_only, game: tactics)
      manual(playtime_only, ff1, 30)

      rows = members_table

      expect(rows.map { |row| row.dig("user", "user_id") })
        .to eq([ early, late, half_long, half_short, playtime_only, spin_only ].map(&:user_id))
      expect(rows.first).to include("conquered_at" => be_present)
      expect(rows.first.fetch("meters")).to include("mainline" => { "done" => 2, "total" => 2, "playtime_minutes" => 0 })
      expect(rows.third.fetch("meters")).to include("all" => { "done" => 1, "total" => 3, "playtime_minutes" => 900 })
    end

    it "gives each member's avatar: the Discord hash and the stored avatar's path" do
      link(ff1, mainline: true)
      face = create(:user, discord_avatar: "a1b2c3")
      create(:completion, user: face, game: ff1)

      expect(members_table.first.fetch("user")).to include("user_id" => face.user_id, "discord_avatar" => "a1b2c3",
        "avatar_url" => "/api/v1/users/#{face.user_id}/avatar")
    end

    it "ranks by the whole Franchise when it has no Mainline games" do
      link(ff1)
      link(tactics)
      one, two = create(:user), create(:user)
      create(:completion, user: one, game: ff1)
      [ ff1, tactics ].each { |game| create(:completion, user: two, game: game) }

      expect(members_table.map { |row| row.dig("user", "user_id") }).to eq([ two.user_id, one.user_id ])
    end

    it "leaves out departed members and Add-on-only activity" do
      link(ff1, mainline: true)
      dlc = create(:game, parent_igdb_id: 99)
      link(dlc)
      gone = create(:user, server_left_at: 1.day.ago)
      create(:completion, user: gone, game: ff1)
      create(:completion, user: member, game: dlc)

      expect(members_table).to eq([])
    end
  end

  describe "Conquests" do
    let(:regular) { create(:user, role_member: true, role_regular: true) }
    let(:admin) { create(:user, role_admin: true) }

    before do
      link(ff1, mainline: true)
      link(ff2, mainline: true)
      link(tactics)
    end

    def set_mainline(game, mainline, of: franchise)
      put "/api/v1/franchises/#{of.franchise_id}/games/#{game.game_id}", params: { data: { mainline: mainline } },
        headers: auth_headers_for(regular), as: :json
      expect(response).to have_http_status(:ok)
    end

    it "Conquers on the last Mainline Completion and queues one post, even unannounced" do
      create(:game_image, :primary, game: ff2)
      complete(ff1)
      expect(progress.fetch("conquered_at")).to be_nil
      expect(conquest_jobs).to be_empty

      last = complete(ff2, announce: false)

      expect(progress.fetch("conquered_at")).to be_present
      expect(conquest_jobs.count).to eq(1)
      job = conquest_jobs.first
      expect(job.summary).to eq("Announce Mara's Conquest of Final Fantasy")
      expect(job.requested_by_user_id).to eq(member.user_id)
      expect(job.payload).to include("user_id" => member.user_id, "franchise_id" => franchise.franchise_id,
        "completion_id" => last.completion_id, "feature_key" => "franchise_progress")
    end

    context "with image URLs configured" do
      # Image URLs need a public base URL, which CI doesn't set.
      around do |example|
        original = ENV["BACKBLAZE_PUBLIC_BASE_URL"]
        ENV["BACKBLAZE_PUBLIC_BASE_URL"] = "https://cdn.example.test/club"
        example.run
      ensure
        original.nil? ? ENV.delete("BACKBLAZE_PUBLIC_BASE_URL") : ENV["BACKBLAZE_PUBLIC_BASE_URL"] = original
      end

      it "carries the card's covers, Franchise Playtime and who else Conquered it" do
        [ ff1, ff2 ].each { |game| create(:completion, user: other, game: game) }
        UserFranchiseConquest.create!(user: other, franchise: franchise, conquered_at: 1.month.ago)
        create(:game_image, :primary, game: ff2)
        manual(member, ff1, 600)
        manual(member, tactics, 60)

        complete(ff1)
        complete(ff2)

        payload = conquest_jobs.sole.payload
        expect(payload).to include("franchise_name" => "Final Fantasy", "conquered_at" => be_present,
          "playtime_minutes" => 660, "mainline_playtime_minutes" => 600, "mainline_total" => 2)
        expect(payload.fetch("covers")).to match([
          include("game_id" => ff2.game_id, "title" => "Final Fantasy II", "release_year" => 1988,
            "cover_url" => be_present)
        ])
        expect(payload.fetch("also_conquered")).to match([
          include("user_id" => other.user_id, "name" => "Ivo", "conquered_at" => be_present)
        ])
        expect(payload.fetch("also_conquered_count")).to eq(1)
      end
    end

    it "doesn't Conquer through spin-offs, and posts once" do
      complete(tactics)
      complete(ff1)
      complete(ff2)
      complete(ff2)

      expect(UserFranchiseConquest.where(user_id: member.user_id).count).to eq(1)
      expect(conquest_jobs.count).to eq(1)
    end

    it "Conquers when a Completion is changed to the last Mainline game" do
      complete(ff1)
      completion = complete(tactics)

      patch "/api/v1/completions/#{completion.completion_id}",
        params: { data: { gamedb_game_id: ff2.game_id } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(progress.fetch("conquered_at")).to be_present
      expect(conquest_jobs.count).to eq(1)
    end

    it "keeps the Conquest when a Mainline game is added or a Completion deleted" do
      [ ff1, ff2 ].each { |game| complete(game) }
      ff3 = create(:game, title: "Final Fantasy III")

      put "/api/v1/franchises/#{franchise.franchise_id}/games/#{ff3.game_id}", params: { data: { mainline: true } },
        headers: auth_headers_for(regular), as: :json
      delete "/api/v1/completions/#{UserGameCompletion.find_by(gamedb_game_id: ff1.game_id).completion_id}",
        headers: auth_headers_for(member)

      data = progress
      expect(data.fetch("conquered_at")).to be_present
      expect(data.dig("meters", "mainline")).to include("done" => 1, "total" => 3)
    end

    it "Conquers, and posts, when a Mainline change completes the set" do
      create(:completion, user: member, game: ff1)
      create(:completion, user: member, game: tactics)

      set_mainline(ff2, false)
      expect(progress.fetch("conquered_at")).to be_present
      expect(conquest_jobs.sole.payload).to include("user_id" => member.user_id)

      set_mainline(tactics, true)
      expect(conquest_jobs.count).to eq(1)
    end

    it "Conquers when a game is linked as Mainline or unlinked" do
      create(:completion, user: member, game: ff1)
      create(:completion, user: other, game: ff2)
      done = create(:game)
      create(:completion, user: other, game: done)
      create(:completion, user: other, game: ff1)

      delete "/api/v1/franchises/#{franchise.franchise_id}/games/#{ff2.game_id}", headers: auth_headers_for(regular)
      expect(UserFranchiseConquest.pluck(:user_id)).to contain_exactly(member.user_id, other.user_id)

      fresh = create(:franchise)
      create(:completion, user: member, game: done)
      set_mainline(done, true, of: fresh)
      expect(UserFranchiseConquest.where(franchise_id: fresh.franchise_id).pluck(:user_id))
        .to contain_exactly(member.user_id, other.user_id)
    end

    it "moves Conquests on a merge, keeping the earliest, and deletes them with the Franchise" do
      target = create(:franchise)
      UserFranchiseConquest.create!(user: member, franchise: franchise, conquered_at: 2.years.ago)
      UserFranchiseConquest.create!(user: member, franchise: target, conquered_at: 1.year.ago)
      UserFranchiseConquest.create!(user: other, franchise: franchise, conquered_at: 1.day.ago)

      post "/api/v1/franchises/#{franchise.franchise_id}/merge", params: { data: { into_id: target.franchise_id } },
        headers: auth_headers_for(admin), as: :json
      expect(response).to have_http_status(:ok)

      rows = UserFranchiseConquest.order(:user_id).pluck(:user_id, :franchise_id, :conquered_at)
      expect(rows.map { |row| row.first(2) }).to contain_exactly([ member.user_id, target.franchise_id ],
        [ other.user_id, target.franchise_id ])
      expect(UserFranchiseConquest.find_by(user_id: member.user_id).conquered_at).to be_within(1.day).of(2.years.ago)

      delete "/api/v1/franchises/#{target.franchise_id}", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:no_content)
      expect(UserFranchiseConquest.count).to eq(0)
    end

    it "writes a Conquest from a Completionator import without posting it" do
      create(:completion, user: member, game: ff1)
      import = create(:completionator_import, user: member)
      row = create(:completionator_import_item, import: import, game_title: "Final Fantasy II",
        gamedb_game_id: ff2.game_id)

      post "/api/v1/completionator_import_items/#{row.item_id}/add_completion",
        params: { data: { completion_type: "Main Story", platform_id: nil } }, headers: auth_headers_for(member),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(UserFranchiseConquest.sole).to have_attributes(user_id: member.user_id, announce: false)
      expect(conquest_jobs).to be_empty
    end
  end

  describe "members' image columns" do
    # avatar_blob and profile_image are large binaries: the members table and
    # Conquests never read them (RpgClubUser.without_images).
    def user_selects
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "rpg_club_users"') }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      queries
    end

    it "are never selected by the members table, the Conquest check or its post" do
      link(ff1, mainline: true)
      [ other, member ].each { |user| create(:completion, user: user, game: ff1) }
      UserFranchiseConquest.create!(user: other, franchise: franchise, conquered_at: 1.month.ago)

      queries = user_selects do
        Franchises::Progress.new(franchise).members
        Franchises::ConquestCheck.new.for_franchise(franchise)
      end

      expect(conquest_jobs.count).to eq(1)
      expect(queries).not_to be_empty
      expect(queries).to all(satisfy { |sql| !sql.include?('"rpg_club_users".*') && !sql.include?("avatar_blob") })
    end
  end

  describe "Feature gating" do
    before { link(ff1, mainline: true) }

    it "is not found for a member in Preview, and answers staff and the bot" do
      set_feature_flag("franchise_progress", "preview")

      get "/api/v1/franchises/#{franchise.franchise_id}/progress", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)
      get "/api/v1/franchises/#{franchise.franchise_id}/progress/members", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)

      admin = create(:user, role_admin: true)
      expect(progress(as: admin).dig("meters", "mainline", "total")).to eq(1)
      expect(members_table(as: admin)).to eq([])
    end
  end
end
