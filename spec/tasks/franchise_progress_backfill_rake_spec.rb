# frozen_string_literal: true

require "rails_helper"
require "rake"

# The launch backfill (spec api#457, ticket api#461): Conquests members
# already hold at launch are written with `announce: false` and never posted.
RSpec.describe "franchise_progress:backfill_conquests" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["franchise_progress:backfill_conquests"] }
  let(:member) { create(:user) }
  let(:franchise) { create(:franchise) }
  let(:ff1) { create(:game) }
  let(:ff2) { create(:game) }

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("franchise_progress:backfill_conquests") }

  before do
    task.reenable
    [ ff1, ff2 ].each { |game| GamedbGameFranchise.create!(franchise: franchise, game: game, mainline: true) }
  end

  def run_backfill
    expect { task.invoke }.to output(/Backfilled Conquests/).to_stdout
    task.reenable
  end

  it "writes unannounced Conquests once, with no bot job" do
    create(:completion, user: member, game: ff1)
    create(:completion, user: member, game: ff2)
    create(:completion, game: ff1)

    run_backfill
    run_backfill

    expect(UserFranchiseConquest.all).to contain_exactly(have_attributes(user_id: member.user_id, announce: false))
    expect(BotJob.where(kind: "franchise_conquest")).to be_empty
  end

  it "dates a Conquest by the latest of each Mainline game's first finish" do
    create(:completion, user: member, game: ff1, completed_at: "2020-03-01")
    create(:completion, user: member, game: ff1, completed_at: "2024-01-01")
    finishing = create(:completion, user: member, game: ff2, completed_at: "2021-05-04")
    create(:completion, user: member, game: ff2, completed_at: "2023-01-01")

    run_backfill

    expect(UserFranchiseConquest.sole).to have_attributes(completion_id: finishing.completion_id,
      conquered_at: ClubDay.noon(Date.new(2021, 5, 4)))
  end

  it "skips Franchises with no Mainline games" do
    spin = create(:franchise)
    GamedbGameFranchise.create!(franchise: spin, game: ff1, mainline: false)
    create(:completion, user: member, game: ff1)

    run_backfill

    expect(UserFranchiseConquest.count).to eq(0)
  end
end
