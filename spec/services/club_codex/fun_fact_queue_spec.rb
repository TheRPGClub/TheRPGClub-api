# frozen_string_literal: true

require "rails_helper"

# The Fun Fact queue's draw under concurrency (spec #397, ticket #405): the
# picked row is locked, so a draw running alongside another never gets the
# same Fun Fact while there is another to give. The queue order itself is
# covered through POST /api/v1/codex/fun_facts/draw.
RSpec.describe ClubCodex::FunFactQueue do
  describe ".draw! alongside another draw" do
    self.use_transactional_tests = false

    let!(:author) { create(:user, role_member: true, role_regular: true) }
    let(:release) { Queue.new }
    let(:threads) { [] }

    # Lets a held draw go even when an expectation failed, so its lock never
    # outlives the example.
    after do
      release << true
      threads.each { |thread| thread.join(5) }
      CodexEntry.where(author_user_id: author.user_id).delete_all
      author.destroy!
    end

    # Starts a draw that holds its Fun Fact's lock until `release` is
    # pushed, and returns its thread once that Fun Fact is picked.
    def held_draw
      picked = Queue.new
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          CodexEntry.transaction do
            entry = described_class.draw!
            picked << entry
            release.pop
            entry
          end
        end
      end
      [ threads.last, picked.pop ]
    end

    def draw_in_thread
      threads << Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.draw! } }
      threads.last
    end

    it "gives the next Fun Fact, not the one being drawn" do
      older = create(:codex_entry, :fun_fact, author: author, created_at: 2.days.ago)
      newer = create(:codex_entry, :fun_fact, author: author, created_at: 1.day.ago)
      holder, held = held_draw
      other = draw_in_thread
      finished_while_held = other.join(2)
      release << true

      expect(finished_while_held).not_to be_nil
      expect([ held, other.value ]).to eq([ newer, older ])
      expect(holder.value).to eq(newer)
    end

    it "waits for the only Fun Fact rather than saying there are none" do
      only = create(:codex_entry, :fun_fact, author: author)
      holder, held = held_draw
      waiting = draw_in_thread
      expect(waiting.join(0.2)).to be_nil

      release << true

      expect(held).to eq(only)
      expect(waiting.value).to eq(only)
      expect(holder.value).to eq(only)
    end
  end
end
