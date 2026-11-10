# frozen_string_literal: true

# The feature gate (spec #347; docs/adr/0005): unreleased work stays
# unreleased at the API, not only in the clients.
#
# A controller whose endpoints belong to a Feature declares it once, as the
# first line of the class so it runs right after authentication and before
# the controller's own role gates:
#
#   class ReviewsController < ApplicationController
#     feature :reviews
#
# `feature :key, except: %i[create]` (any before_action option) leaves the
# named actions open, for endpoints other Features depend on.
#
# A request from someone the Feature Flag does not let use that Feature gets
# 404 `{ error: "not_found" }`, as if the endpoint did not exist: non-staff
# when the Feature is Preview or Off, everyone when it is Off. Who counts as
# staff and what each state allows is Features::Access's decision.
#
# An endpoint that embeds another Feature's data (a profile's Now Playing, a
# game page's Completions, the dashboard's winners) leaves that section out
# unless `can_use_feature?(key)`, the same decision as the gate.
#
# The bot's service token is never stopped here: the bot runs its own feature
# gate for the Discord user acting through it. Feature Preferences never
# affect access, only what the website shows.
module FeatureGate
  extend ActiveSupport::Concern

  included do
    class_attribute :feature_key, instance_writer: false, default: nil
  end

  class_methods do
    # Declares the Feature this controller's endpoints belong to. Raises
    # KeyError for a key that is not in the registry (Features).
    def feature(key, **options)
      self.feature_key = Features.fetch(key).key
      before_action :require_feature!, **options
    end
  end

  private

  def require_feature!
    return true if can_use_feature?(feature_key)

    render json: { error: "not_found" }, status: :not_found
    false
  end

  # Whether the caller may use Feature `key`: always for the service token;
  # otherwise by its Feature Flag state, kept a few seconds in this process
  # (Features.cached_states), and the caller's roles only when the answer
  # depends on them (Preview), since it runs on every gated request.
  def can_use_feature?(key)
    return true if current_principal&.service?

    state = Features.cached_states.fetch(Features.fetch(key).key)
    Features::Access.new(staff: state == "preview" && admin_or_above?, states: { key.to_s => state }).can_use?(key.to_s)
  end

  # The controller's Feature's Feature Flag state.
  def feature_state
    Features.cached_states.fetch(feature_key)
  end
end
