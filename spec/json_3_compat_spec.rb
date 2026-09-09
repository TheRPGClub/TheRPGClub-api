# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for #244. json 3.0 made JSON.parse keyword-only for its
# options and now rejects keywords it does not recognise, while Rails 8.1.3.1
# both passes those options positionally and feeds the encoder's `escape` flag
# to the decoder. config/initializers/json_3_compat.rb carries the two upstream
# fixes; every example here fails under json 3 with that initializer removed.
RSpec.describe 'json 3 compatibility' do
  describe 'ActiveSupport::JSON.decode' do
    it 'decodes without options' do
      expect(ActiveSupport::JSON.decode('{"team":"rails"}')).to eq('team' => 'rails')
    end

    it 'forwards options that json 3 accepts only as keywords' do
      expect(ActiveSupport::JSON.decode('{"team":"rails"}', symbolize_names: true))
        .to eq(team: 'rails')
    end
  end

  # The failure in the issue surfaced through db:seed, but the round-trip
  # happens on plain assignment: ActiveModel::Type::Helpers::Mutable#cast
  # serializes then deserializes, and the deserialize half is what calls
  # ActiveSupport::JSON.decode. No database write is needed to exercise it.
  describe 'jsonb attribute assignment' do
    it 'round-trips a Hash through the jsonb type' do
      review = UserGameReview.new(body: { 'summary' => 'Great game' })

      expect(review.body).to eq('summary' => 'Great game')
    end

    it 'round-trips nested structures' do
      review = UserGameReview.new(body: { 'tags' => %w[rpg indie], 'score' => { 'art' => 9 } })

      expect(review.body).to eq('tags' => %w[rpg indie], 'score' => { 'art' => 9 })
    end
  end

  # ActiveRecord::Coders::JSON defaults to `{ escape: false }` and, before the
  # upstream split, handed that encoder flag to the decoder too. json 2 ignored
  # the stray key; json 3 raises `ArgumentError: unknown keyword: escape` on
  # every read of a `serialize coder: JSON` attribute -- SolidQueue::Process
  # metadata included, which took the worker down on boot.
  describe 'ActiveRecord::Coders::JSON' do
    let(:coder) { ActiveRecord::Coders::JSON.new }

    it 'loads what it dumped' do
      expect(coder.load(coder.dump('polling_interval' => 2))).to eq('polling_interval' => 2)
    end

    it 'returns nil for a blank payload' do
      expect(coder.load('')).to be_nil
    end

    # `escape: false` has to keep reaching the encoder, not just stop reaching
    # the parser: Rails 8.1 relies on it to leave HTML entities alone here.
    it 'still dumps without escaping HTML entities' do
      expect(coder.dump('body' => '<b>')).to eq('{"body":"<b>"}')
    end

    it 'round-trips through the store coder a jsonb-free serialize uses' do
      indifferent = ActiveRecord::Store::IndifferentCoder.new(:metadata, coder)
      loaded = indifferent.load(indifferent.dump(polling_interval: 2))

      expect(loaded[:polling_interval]).to eq(2)
    end
  end
end
