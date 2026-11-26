# frozen_string_literal: true

# The Roadmap badge on Feedback payloads (spec api#505, ticket api#508):
# `roadmap` is `{ item_id, milestone_name, shipped }` for Feedback linked to
# a Roadmap Item, or null. It is null for everything when the viewer can't
# see the Roadmap: the Feature is Off, Preview for a non-staff viewer, or
# hidden by the viewer's Feature Preferences (Features::Access#shown?). The
# bot's service token sees it unless the Feature is Off.
module FeedbackRoadmapBadges
  extend ActiveSupport::Concern

  private

  # Serializer params for `records` (a page of Feedback, or one).
  def feedback_badge_params(records)
    return { roadmap_badges: {} } unless roadmap_badge_shown?

    { roadmap_badges: FeedbackResource.roadmap_badges(Array(records).map(&:feedback_id)) }
  end

  # Decided once per request. Reads no member data when the Feature Flag
  # alone decides; otherwise reuses the member row auth already read.
  def roadmap_badge_shown?
    return @roadmap_badge_shown if defined?(@roadmap_badge_shown)

    @roadmap_badge_shown = begin
      states = Features.cached_states
      if current_principal.service?
        states.fetch("roadmap") != "off"
      elsif !can_use_feature?(:roadmap)
        false
      else
        user = current_principal.user || RpgClubUser.find_by(user_id: current_principal.id)
        Features::Access.for_viewer(user, staff: admin_or_above?, states: states).shown?("roadmap")
      end
    end
  end
end
