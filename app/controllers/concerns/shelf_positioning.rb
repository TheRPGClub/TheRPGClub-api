# frozen_string_literal: true

# The `position` write param of the shelf list updates (Now Playing, Backlog,
# Favorites; spec api#451 story 15): a 1-based place in the member's list
# that moves one entry and renumbers the rest server-side (ShelfOrder).
#
# `shelf_position` returns nil when `position` is absent, the integer when it
# is valid, and otherwise renders 422 `invalid_position` (callers
# `return if performed?`). It can't be combined with `sort_order`.
module ShelfPositioning
  extend ActiveSupport::Concern

  private

  def shelf_position
    data = request_data
    raw = data["position"]
    return nil if raw.nil?
    return position_error("send position or sort_order, not both") if data.key?("sort_order")

    value = Integer(raw.to_s, 10, exception: false)
    return position_error("position must be an integer of at least 1") if value.nil? || value < 1

    value
  end

  def position_error(message)
    render json: { error: "invalid_position", message: }, status: :unprocessable_content
    nil
  end
end
