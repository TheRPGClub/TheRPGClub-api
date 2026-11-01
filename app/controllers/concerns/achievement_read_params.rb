# frozen_string_literal: true

# Shared request handling for the Achievement Hub reads: validating the enum
# query params and the spoiler-blur data for the signed-in viewer.
module AchievementReadParams
  extend ActiveSupport::Concern

  class InvalidParam < ArgumentError; end

  included do
    rescue_from InvalidParam do |error|
      render json: { error: error.message }, status: :unprocessable_content
    end
  end

  private

  # The param's value, nil when blank, or a 422 when it is not one of `allowed`.
  def enum_param(name, allowed)
    value = params[name].presence
    return nil if value.nil?
    raise InvalidParam, "#{name} must be one of #{allowed.join(', ')}" unless allowed.include?(value)

    value
  end

  # The signed-in member's id, or nil for the service principal.
  def viewer_id
    current_principal.id.to_s if current_principal&.discord_user?
  end

  # Alba params for AchievementUnlockResource over the given Unlocks.
  def viewer_params(unlocks)
    { viewer_unlocked_ids: Achievements::Reads.viewer_unlocked_ids(viewer_id, unlocks.map(&:achievement_id)) }
  end
end
