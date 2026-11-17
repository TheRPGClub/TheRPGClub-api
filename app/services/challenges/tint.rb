# frozen_string_literal: true

module Challenges
  # The Challenge tint (spec #376; the website's DESIGN.md, "Challenges
  # inks"): the one colour a Challenge wears on the bot's posts and the
  # website, as a pair. `fill` is the ground of its flyer and banner, under
  # paper type; `hi` is the same hue lifted for type and marks on ink.
  #
  # A new Challenge gets a curated tint (Tint.fallback): holly for an
  # Assignment Challenge (Secret Santa's own), otherwise one of the other
  # seven, turning through them by id so neighbouring Challenges differ. The
  # Host, or staff, may set another (Tint.parse): a curated tint by name, any
  # pair that keeps type readable, or null for the curated one back.
  #
  # The website samples game tints from cover art in its own server
  # (lib/achievements/tint.ts); the API has no image decoding, so it does not
  # sample Challenge art.
  module Tint
    Pair = Data.define(:fill, :hi) do
      def as_json(*) = { fill: fill, hi: hi }
    end

    # The curated tints, as DESIGN.md lists them. None is masthead red,
    # feature violet, highlighter yellow or signal orange.
    CURATED = {
      "teal" => Pair.new(fill: "#1f6b67", hi: "#6fd6cc"),
      "cobalt" => Pair.new(fill: "#2c4f8e", hi: "#9ab8f2"),
      "holly" => Pair.new(fill: "#1c6545", hi: "#3fbf8a"),
      "umber" => Pair.new(fill: "#7a531c", hi: "#e0b56e"),
      "moss" => Pair.new(fill: "#3b5a2b", hi: "#a9cf86"),
      "azure" => Pair.new(fill: "#2a5ea6", hi: "#9cc2f5"),
      "slate" => Pair.new(fill: "#3a3a52", hi: "#b4b4d6"),
      "ochre" => Pair.new(fill: "#8a6417", hi: "#e6c36a")
    }.freeze
    SECRET_SANTA = "holly"
    # The order new Challenges turn through (the migration that added the
    # tint backfilled with the same order).
    ROTATION = (CURATED.keys - [ SECRET_SANTA ]).freeze

    # The website's paper type and its two inks, which type on a fill and a
    # hi on ink must stay readable against (WCAG AA, 4.5:1).
    PAPER = "#f4f4f0"
    INKS = %w[#0b0b0d #141417].freeze
    MIN_CONTRAST = 4.5

    HEX = /\A#\h{6}\z/

    # The curated tint for `challenge`, which needs its id.
    def self.fallback(challenge)
      return CURATED.fetch(SECRET_SANTA) if challenge.challenge_format == Formats::Assignment::KEY

      CURATED.fetch(ROTATION[challenge.id % ROTATION.size])
    end

    # A tint from a request: a curated tint's name, `{ fill, hi }` as
    # #rrggbb, or nil (the Challenge's curated tint; returns nil). Raises
    # Challenges::Invalid for anything else, or a pair whose type would not
    # be readable.
    def self.parse(value)
      return nil if value.nil?
      return CURATED.fetch(value) { raise Invalid, unknown_name(value) } if value.is_a?(String)
      raise Invalid, "tint must be a curated tint's name or { fill, hi }" unless value.is_a?(Hash)

      fill, hi = value.stringify_keys.values_at("fill", "hi").map { |color| color.to_s.strip.downcase }
      raise Invalid, "tint fill and hi must each be a colour as #rrggbb" unless [ fill, hi ].all? { |color| HEX.match?(color) }

      readable!(Pair.new(fill: fill, hi: hi))
    end

    def self.unknown_name(value)
      "#{value} is not a curated tint: use one of #{CURATED.keys.join(', ')}, or { fill, hi }"
    end
    private_class_method :unknown_name

    def self.readable!(pair)
      if contrast(PAPER, pair.fill) < MIN_CONTRAST
        raise Invalid, "The tint's fill is too light for paper type on it: pick a darker fill"
      end
      if INKS.any? { |ink| contrast(pair.hi, ink) < MIN_CONTRAST }
        raise Invalid, "The tint's hi is too dark to read on ink: pick a lighter hi"
      end

      pair
    end
    private_class_method :readable!

    # The WCAG contrast ratio of two #rrggbb colours.
    def self.contrast(first, second)
      lighter, darker = [ luminance(first), luminance(second) ].sort.reverse
      (lighter + 0.05) / (darker + 0.05)
    end

    def self.luminance(hex)
      red, green, blue = hex.delete_prefix("#").scan(/../).map do |channel|
        value = channel.to_i(16) / 255.0
        value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    end
    private_class_method :luminance
  end
end
