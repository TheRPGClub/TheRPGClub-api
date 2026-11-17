# frozen_string_literal: true

require "rails_helper"

# The Secret Santa draw (spec #376, "Secret Santa draw"; ticket #383): the
# members of an Edition and a random source go in, one circle comes out, in
# which each member gives to the next.
RSpec.describe Challenges::Draw do
  let(:members) { %w[ann bob cat dan eve fay] }

  # Follows the circle from its first Santa until it comes back round.
  def walk(circle)
    start = circle.keys.first
    order = [ start ]
    order << circle.fetch(order.last) until circle.fetch(order.last) == start || order.size > circle.size
    order
  end

  it "gives every member exactly one recipient, and nobody draws themselves" do
    circle = described_class.circle(members, random: Random.new(1))

    expect(circle.keys).to match_array(members)
    expect(circle.values).to match_array(members)
    expect(circle).to(be_none { |santa, recipient| santa == recipient })
  end

  it "forms one circle through every member, never smaller loops" do
    (1..25).each do |seed|
      circle = described_class.circle(members, random: Random.new(seed))

      expect(walk(circle)).to match_array(members)
    end
  end

  it "draws the same circle for the same seed, whatever order the members come in" do
    first = described_class.circle(members, random: Random.new(42))
    again = described_class.circle(members.reverse, random: Random.new(42))

    expect(again).to eq(first)
  end

  it "draws different circles for different seeds" do
    circles = (1..10).map { |seed| described_class.circle(members, random: Random.new(seed)) }

    expect(circles.uniq.size).to be > 1
  end

  it "pairs two members with each other" do
    expect(described_class.circle(%w[ann bob], random: Random.new(3))).to eq("ann" => "bob", "bob" => "ann")
  end

  it "refuses fewer than two members, since nobody may draw themselves" do
    expect { described_class.circle(%w[ann], random: Random.new(1)) }.to raise_error(ArgumentError)
  end
end
