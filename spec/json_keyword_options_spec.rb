# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for #244. json 3.0 made JSON.parse keyword-only for its
# options, while ActiveSupport 8.1.3.1 still passes them positionally, which
# breaks every jsonb attribute. config/initializers/json_keyword_options.rb
# adapts the call to the json 3 signature; these examples fail with
# `ArgumentError: wrong number of arguments (given 2, expected 1)` under json 3
# if that initializer is removed before Rails ships its own fix.
RSpec.describe 'ActiveSupport::JSON keyword options' do
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
end
