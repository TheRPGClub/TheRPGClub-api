# frozen_string_literal: true

class UserGameReview < ApplicationRecord
  self.table_name = "user_game_reviews"
  self.primary_key = "review_id"

  # The review scorecard catalogue, mirrored by `www/lib/reviews/facets.ts`.
  # The web side owns the human labels and hints; this side owns validity.
  # Adding a facet or a template means adding it in both places.
  FACET_KEYS = %w[
    story characters combat world music visuals pacing gameplay
    replayability difficulty writing performance value art_direction
    voice_acting
  ].freeze
  # Which preset the card was last built from — provenance, not a constraint.
  # Every preset is editable, so a card tagged "rpg" may legitimately no longer
  # look like the RPG preset, and `order` is never checked against it.
  # "quick" is deliberately absent: a quick take stores `facets: nil`, so "no
  # scorecard" has exactly one representation.
  FACET_TEMPLATES = %w[rpg general custom].freeze
  # A category the reviewer invented on this card, carrying whatever name they
  # gave it in `labels`. Numbered rather than slugged from the name: a slug
  # would have to change on every rename and drag the row's score and weight
  # with it. The number is arbitrary and stable; the label carries the meaning.
  CUSTOM_FACET_KEY = /\Acustom:[1-9][0-9]{0,3}\z/
  # The longest preset is 7, so the ceiling only ever binds on a custom card.
  MAX_FACETS = 12
  # The budget a weighted scorecard splits across its facets. Weights are
  # optional; when present they must cover `order` exactly and sum to this.
  WEIGHT_TOTAL = 100
  MAX_LABEL_LENGTH = 40
  FACET_ATTRIBUTES = %w[template order scores labels weights].freeze

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :reviews
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :reviews

  # `{"order": []}` is a scorecard with nothing on it, which is a quick take
  # wearing a different shape. Collapse it before validating so the two can't
  # both persist.
  before_validation :nullify_empty_facets

  validates :user_id, :gamedb_game_id, presence: true
  validates :rating,
            presence: true,
            numericality: { only_integer: true, in: 0..100 }
  validates :user_id, uniqueness: { scope: :gamedb_game_id }
  # The reviews controller writes `params.require(:data).permit!`, so this is
  # the only thing between a client and arbitrary jsonb the web app renders.
  validate :facets_shape

  # The mean of the scored facets, rounded, or nil when none are scored.
  # Weighted by the card's own split where it has one. Mirrors `facetAverage`
  # in `www/lib/reviews/facets.ts`.
  #
  # Unscored facets are left out of both the sum and the divisor, so a
  # half-filled card averages what is actually on it rather than counting the
  # blanks as zero.
  #
  # Only ever a derived reading: the overall `rating` stays authored, and the
  # gap between the two is usually the interesting part of a review. This is
  # the natural hook for the per-game facet aggregates (#8).
  def facet_average
    data = facets.is_a?(Hash) ? facets.stringify_keys : {}
    order = data["order"]
    scores = data["scores"]
    return nil unless order.is_a?(Array) && scores.is_a?(Hash)

    scores = scores.stringify_keys
    scored = order.select { |key| scores[key].is_a?(Integer) }
    return nil if scored.empty?

    weights = data["weights"]
    if weights.is_a?(Hash)
      weights = weights.stringify_keys
      total = scored.sum { |key| weights[key].is_a?(Integer) ? weights[key] : 0 }
      # Every scored facet weighted at zero leaves nothing to divide by. That
      # is reachable (weight the blanks, score the rest at 0%), so it falls
      # back to the plain mean rather than reporting no average at all.
      if total.positive?
        weighted = scored.sum { |key| scores[key] * (weights[key].is_a?(Integer) ? weights[key] : 0) }
        return (weighted.to_f / total).round
      end
    end

    (scored.sum { |key| scores[key] }.to_f / scored.length).round
  end

  private

  def nullify_empty_facets
    return unless facets.is_a?(Hash)

    order = facets.stringify_keys["order"]
    return unless order.is_a?(Array) && order.empty?

    self.facets = nil
  end

  # A scorecard read back from jsonb is always string-keyed; one assigned in
  # Ruby need not be, so every check reads the stringified copy.
  def facets_shape
    return if facets.nil?

    unless facets.is_a?(Hash)
      return errors.add(:facets, "must be an object")
    end

    data = facets.stringify_keys
    unknown = data.keys - FACET_ATTRIBUTES
    errors.add(:facets, "has unknown keys: #{unknown.sort.join(', ')}") if unknown.any?

    validate_facet_template(data["template"])
    order = validate_facet_order(data["order"])
    labels = validate_facet_labels(data["labels"], order)
    validate_custom_facet_labels(order, labels)
    validate_facet_scores(data["scores"], order)
    validate_facet_weights(data["weights"], order)
  end

  def validate_facet_template(template)
    return if FACET_TEMPLATES.include?(template)

    errors.add(:facets, "template must be one of: #{FACET_TEMPLATES.join(', ')}")
  end

  # Returns the validated order, or nil when it is unusable — the scores check
  # only reports strays against an order it can trust.
  def validate_facet_order(order)
    unless order.is_a?(Array)
      errors.add(:facets, "order must be an array")
      return nil
    end

    unknown = order.reject { |key| catalogue_facet?(key) || custom_facet?(key) }
    errors.add(:facets, "order has unknown facets: #{unknown.map(&:to_s).uniq.sort.join(', ')}") if unknown.any?
    errors.add(:facets, "order has duplicate facets") if order.uniq.length != order.length
    errors.add(:facets, "order may not exceed #{MAX_FACETS} facets") if order.length > MAX_FACETS

    order
  end

  def catalogue_facet?(key) = FACET_KEYS.include?(key)

  def custom_facet?(key) = key.is_a?(String) && CUSTOM_FACET_KEY.match?(key)

  # Display names, stored only where they say something the catalogue doesn't.
  # A catalogue row *may* carry one — it is an override, and the key stays
  # canonical, which is the point: a row renamed "Job System" still counts as
  # `combat` for any future club-wide averages. Returns the validated labels,
  # or nil when there is nothing usable to check custom rows against.
  def validate_facet_labels(labels, order)
    return nil if labels.nil?

    unless labels.is_a?(Hash)
      errors.add(:facets, "labels must be an object")
      return nil
    end

    labels = labels.stringify_keys

    if order.is_a?(Array)
      strays = labels.keys - order
      errors.add(:facets, "labels has facets missing from order: #{strays.sort.join(', ')}") if strays.any?
    end

    blank = labels.reject { |_key, value| value.is_a?(String) && value.strip.present? }
    errors.add(:facets, "labels must be non-empty strings: #{blank.keys.sort.join(', ')}") if blank.any?

    long = labels.select { |_key, value| value.is_a?(String) && value.strip.length > MAX_LABEL_LENGTH }
    if long.any?
      errors.add(:facets,
        "labels may not exceed #{MAX_LABEL_LENGTH} characters: #{long.keys.sort.join(', ')}")
    end

    labels
  end

  # A custom row is nothing but its name: without one there is nothing to
  # render and no way to say what the score meant. Rejected rather than
  # dropped, so a reviewer never silently loses a row they filled in.
  def validate_custom_facet_labels(order, labels)
    return unless order.is_a?(Array)

    named = (labels || {}).select { |_key, value| value.is_a?(String) && value.strip.present? }.keys
    unnamed = order.select { |key| custom_facet?(key) } - named
    return if unnamed.empty?

    errors.add(:facets, "custom facets need a label: #{unnamed.sort.join(', ')}")
  end

  def validate_facet_scores(scores, order)
    return if scores.nil?

    unless scores.is_a?(Hash)
      return errors.add(:facets, "scores must be an object")
    end

    scores = scores.stringify_keys

    # A stray score renders nowhere yet would still land in an average, so it
    # is rejected rather than dropped.
    if order.is_a?(Array)
      strays = scores.keys - order
      errors.add(:facets, "scores has facets missing from order: #{strays.sort.join(', ')}") if strays.any?
    end

    invalid = scores.reject { |_key, value| value.is_a?(Integer) && value.between?(0, 100) }
    return if invalid.empty?

    errors.add(:facets, "scores must be integers in 0..100: #{invalid.keys.sort.join(', ')}")
  end

  # A weighted card splits WEIGHT_TOTAL across every facet on it. The rule is
  # exact rather than lenient, and a violation is rejected rather than
  # repaired: a split that doesn't add up means something different depending
  # on who reads it, and the composer already blocks on this client-side, so
  # anything arriving broken is a bug or a hand-rolled request.
  def validate_facet_weights(weights, order)
    # Absent means unweighted — every scored facet counts once. That is what
    # most cards store, and what every card stored before weights existed.
    return if weights.nil?

    unless weights.is_a?(Hash)
      return errors.add(:facets, "weights must be an object")
    end

    weights = weights.stringify_keys
    # Without a usable order there is nothing to check the key set against;
    # `order`'s own error is the one worth reporting.
    return unless order.is_a?(Array)

    missing = order - weights.keys
    strays = weights.keys - order
    errors.add(:facets, "weights is missing facets from order: #{missing.map(&:to_s).sort.join(', ')}") if missing.any?
    errors.add(:facets, "weights has facets missing from order: #{strays.sort.join(', ')}") if strays.any?

    invalid = weights.reject { |_key, value| value.is_a?(Integer) && value.between?(0, WEIGHT_TOTAL) }
    if invalid.any?
      return errors.add(:facets,
        "weights must be integers in 0..#{WEIGHT_TOTAL}: #{invalid.keys.sort.join(', ')}")
    end

    total = weights.values.sum
    return if total == WEIGHT_TOTAL

    errors.add(:facets, "weights must sum to #{WEIGHT_TOTAL} (got #{total})")
  end
end
