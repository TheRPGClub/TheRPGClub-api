# frozen_string_literal: true

module Roadmap
  # Staff changes to Roadmap Items (spec api#505, ticket api#507). An item
  # only ever goes into an open Milestone: only Shipped items stay with a
  # Reached one, which Reach (Roadmap::Milestones.reach!) sees to.
  module Items
    FIELDS = %w[title blurb area github_issue_url].freeze
    REACHED = "Roadmap Items can't go into a Reached Milestone."

    module_function

    # A new item, last in its open Milestone.
    def create!(attributes)
      Roadmap.write do
        milestone = open_milestone!(attributes["milestone_id"])
        position = (milestone.items.maximum(:position) || 0) + 1
        RoadmapItem.create!(attributes.slice(*FIELDS).merge("milestone" => milestone, "position" => position))
      end
    end

    def update!(item, attributes)
      item.update!(attributes.slice(*FIELDS))
      item
    end

    def destroy!(item)
      Roadmap.write { item.destroy! }
    end

    # `ids` names every item of `milestone` once, first to last.
    def reorder!(milestone, ids)
      Roadmap.write do
        current = milestone.items.pluck(:id)
        ids = Roadmap.full_order!(ids, current, "item_ids must list every Roadmap Item of the Milestone exactly once.")
        Roadmap.set_positions!(RoadmapItem, ids.each_with_index.to_h { |id, index| [ id, index + 1 ] })
      end
    end

    # Moves `item` to `position` (from 1; past the end means last) in the
    # open Milestone `milestone_id`, its own or another. The destination's
    # items are numbered 1.. afterwards.
    def move!(item, milestone_id, position)
      position = Integer(position.to_s, 10, exception: false)
      unless position&.positive?
        raise Refused.new("invalid_position", "position must be a whole number from 1.")
      end

      Roadmap.write do
        milestone = open_milestone!(milestone_id)
        ids = milestone.items.where.not(id: item.id).pluck(:id)
        ids.insert([ position - 1, ids.size ].min, item.id)
        item.update!(milestone: milestone) unless item.milestone_id == milestone.id
        Roadmap.set_positions!(RoadmapItem, ids.each_with_index.to_h { |id, index| [ id, index + 1 ] })
      end
    end

    # Marks it Shipped now; an item already Shipped keeps its date.
    def ship!(item)
      item.update!(shipped_at: Time.current) unless item.shipped?
      item
    end

    # Clears its Shipped date. Refused in a Reached Milestone, which keeps
    # only Shipped items: staff move it out or un-reach the Milestone first.
    def unship!(item)
      Roadmap.write do
        if item.milestone.reached?
          raise Refused.new("milestone_reached",
            "Only Shipped items stay with a Reached Milestone: move it to an open one or un-reach the Milestone first.")
        end

        item.update!(shipped_at: nil)
      end
      item
    end

    def open_milestone!(id)
      milestone = RoadmapMilestone.find_by(id: id) if id.present?
      raise Refused.new("milestone_not_found", "That Milestone doesn't exist.") unless milestone
      raise Refused.new("milestone_reached", REACHED) if milestone.reached?

      milestone
    end
    private_class_method :open_milestone!
  end
end
