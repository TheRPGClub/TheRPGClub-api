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
# A request from someone the Feature Flag does not let use that Feature gets
# 404 `{ error: "not_found" }`, as if the endpoint did not exist: non-staff
# when the Feature is Preview or Off, everyone when it is Off. Who counts as
# staff and what each state allows is Features::Access's decision.
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
    def feature(key)
      self.feature_key = Features.fetch(key).key
      before_action :require_feature!
    end
  end

  private

  # Reads only this Feature's state, and the caller's roles only when the
  # answer depends on them (Preview), since it runs on every gated request.
  def require_feature!
    return true if current_principal&.service?

    state = Features.state(feature_key)
    access = Features::Access.new(staff: state == "preview" && admin_or_above?, states: { feature_key => state })
    return true if access.can_use?(feature_key)

    render json: { error: "not_found" }, status: :not_found
    false
  end
end
