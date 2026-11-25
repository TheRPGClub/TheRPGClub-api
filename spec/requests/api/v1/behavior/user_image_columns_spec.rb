# frozen_string_literal: true

require "rails_helper"

# A member's avatar_blob / profile_image are bytea columns served only by
# GET /users/:id/avatar and /profile_image. Lists that embed members must not
# read them: every `belongs_to :user` to RpgClubUser is scoped
# `without_images`, and the avatar history leaves out its own avatar_blob.
RSpec.describe "member image columns stay out of list reads", type: :request do
  let(:member) { create(:user) }

  def binary_reads(path)
    sqls = []
    callback = lambda do |*, payload|
      sql = payload[:sql]
      sqls << sql if sql.match?(/"avatar_blob"|"profile_image"(?!_)|"rpg_club_users"\.\*|"rpg_club_user_avatar_history"\.\*/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get path, headers: service_headers
    end
    expect(response).to have_http_status(:ok)
    sqls
  end

  it "club recent completions" do
    2.times { create(:completion, user: create(:user)) }

    expect(binary_reads("/api/v1/completions/recent")).to be_empty
  end

  it "club now playing" do
    2.times { create(:now_playing_entry, user: create(:user)) }

    expect(binary_reads("/api/v1/now_playing")).to be_empty
  end

  it "journal search" do
    2.times { create(:journal_entry, user: create(:user)) }

    expect(binary_reads("/api/v1/journal_entries")).to be_empty
  end

  it "a game's completions" do
    game = create(:game)
    2.times { create(:completion, user: create(:user), game: game) }

    expect(binary_reads("/api/v1/games/#{game.game_id}/completions")).to be_empty
  end

  it "avatar history" do
    2.times { create(:avatar_history_event, user: member) }

    expect(binary_reads("/api/v1/users/#{member.user_id}/avatar_history")).to be_empty
    expect(json.fetch("data").length).to eq(2)
  end
end
