# frozen_string_literal: true

module Challenges
  # The Secret Santa draw (spec #376, "Secret Santa draw"): the members of an
  # Edition go round one random circle, each giving to the next, so everyone
  # both gives and receives and nobody draws themselves.
  #
  #   Challenges::Draw.circle(%w[ann bob cat], random: Random.new(seed))
  #   # => { "bob" => "ann", "ann" => "cat", "cat" => "bob" }  (Santa => recipient)
  #
  # It depends only on the members (not the order they come in) and the
  # random source, so a seeded source always draws the same circle.
  module Draw
    def self.circle(members, random:)
      raise ArgumentError, "a circle needs at least 2 members" if members.uniq.size < 2

      order = members.uniq.sort.shuffle(random: random)
      order.each_with_index.to_h { |santa, index| [ santa, order[(index + 1) % order.size] ] }
    end
  end
end
