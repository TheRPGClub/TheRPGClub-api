# frozen_string_literal: true

require "rails_helper"

# Two saves of one member's Pinned Pages at the same moment (two tabs, a
# double click) must not collide: the later one waits for the first, then
# reads the list it left, hidden pins and the limit included.
RSpec.describe PinnedPages::List, "saving at the same moment" do
  self.use_transactional_tests = false

  let!(:member) { create(:user, role_member: true) }
  # A member who sees every Feature page but no staff page, so staff pins
  # are the ones they can't see right now.
  let(:viewer) do
    PinnedPages::Viewer.new(access: instance_double(Features::Access, shown?: true),
      moderator: false, admin: false, superadmin: false)
  end

  after do
    MemberPinnedPage.where(user_id: member.user_id).delete_all
    RpgClubUser.where(user_id: member.user_id).delete_all
  end

  def saved_keys = MemberPinnedPage.where(user_id: member.user_id).order(:position).pluck(:page_key)

  # Runs the block as a save under way: it holds the member's row and has
  # written `keys` as their list, until the returned release is called.
  def save_under_way(keys)
    holding = Queue.new
    release = Queue.new
    thread = in_thread do
      RpgClubUser.transaction do
        RpgClubUser.lock.find(member.user_id).update!(pinned_pages_customised: true)
        MemberPinnedPage.where(user_id: member.user_id).delete_all
        keys.each_with_index do |key, position|
          MemberPinnedPage.create!(user_id: member.user_id, page_key: key, position: position)
        end
        holding << true
        release.pop
      end
    end
    holding.pop
    [ thread, -> { release << true } ]
  end

  def save_alongside(keys)
    first, release = save_under_way(keys)
    second = in_thread { described_class.new(member.user_id, viewer, RpgClubUser.find(member.user_id)).save(yield) }
    begin
      wait_for_a_blocked_lock
    ensure
      release.call
    end
    first.value
    second.value
  end

  it "saves after the save under way, without colliding with its rows" do
    error = save_alongside(%w[voting games]) { %w[games voting news] }

    expect(error).to be_nil
    expect(saved_keys).to eq(%w[games voting news])
  end

  it "counts the hidden pins the save under way kept toward the limit" do
    error = save_alongside(%w[staff_desk live_events synonyms public_reminders]) { %w[voting games members] }

    expect(error).to eq("at most 6 Pinned Pages, counting 4 you can't see right now")
    expect(saved_keys).to eq(%w[staff_desk live_events synonyms public_reminders])
  end
end
