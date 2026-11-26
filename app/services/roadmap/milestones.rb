# frozen_string_literal: true

module Roadmap
  # Staff changes to Milestones (spec api#505, ticket api#507).
  #
  # All Milestones share one position order, Reached or not (api#506). A
  # reorder names only the open ones and hands them the positions they held
  # between them, so each Reached one keeps its place and un-reach returns it
  # there.
  module Milestones
    FIELDS = %w[name blurb target_date date_precision].freeze

    module_function

    # A new Milestone, last in the order.
    def create!(attributes)
      Roadmap.write do
        position = (RoadmapMilestone.maximum(:position) || 0) + 1
        RoadmapMilestone.create!(attributes.slice(*FIELDS).merge("position" => position))
      end
    end

    def update!(milestone, attributes)
      milestone.update!(attributes.slice(*FIELDS))
      milestone
    end

    # Refused while it has Roadmap Items: staff move or delete them first.
    def destroy!(milestone)
      Roadmap.write do
        next if milestone.destroy

        raise Refused.new("milestone_has_items",
          "This Milestone still has Roadmap Items: move or delete its Roadmap Items first.")
      end
    end

    # `ids` names every open Milestone once, first to last.
    def reorder!(ids)
      Roadmap.write do
        open = RoadmapMilestone.open.pluck(:id, :position)
        ids = Roadmap.full_order!(ids, open.map(&:first), "milestone_ids must list every open Milestone exactly once.")
        Roadmap.set_positions!(RoadmapMilestone, ids.zip(open.map(&:last).sort).to_h)
      end
    end

    # Marks `milestone` Reached. Its Roadmap Items that aren't Shipped move,
    # in order, to the end of `destination_id`'s Milestone, by default the
    # next open one in order (or, for the last, the open one before it).
    def reach!(milestone, destination_id)
      Roadmap.write do
        milestone.lock!
        raise Refused.new("already_reached", "This Milestone is already Reached.") if milestone.reached?

        unshipped = milestone.items.where(shipped_at: nil).to_a
        # A destination sent is checked even when nothing moves to it.
        target = destination(milestone, destination_id) if unshipped.any? || destination_id.present?
        move_to!(unshipped, target) if unshipped.any?
        milestone.update!(reached_at: Time.current)
      end
    end

    # Puts a Reached Milestone back among the open ones, at its place.
    def unreach!(milestone)
      Roadmap.write do
        milestone.lock!
        raise Refused.new("not_reached", "This Milestone is not Reached.") unless milestone.reached?

        milestone.update!(reached_at: nil)
      end
    end

    def destination(milestone, destination_id)
      open = RoadmapMilestone.open.where.not(id: milestone.id)
      if destination_id.present?
        found = open.find_by(id: destination_id)
        return found if found

        raise Refused.new("invalid_destination", "Its Roadmap Items can only move to another open Milestone.")
      end

      after = open.where("position > :p OR (position = :p AND id > :id)", p: milestone.position, id: milestone.id)
      after.first || open.last || raise(Refused.new("no_destination",
        "Its Roadmap Items that aren't Shipped need an open Milestone to move to: add one first."))
    end

    def move_to!(items, destination)
      last = destination.items.maximum(:position) || 0
      positions = items.each_with_index.to_h { |item, index| [ item.id, last + index + 1 ] }
      RoadmapItem.where(id: positions.keys).update_all(milestone_id: destination.id, updated_at: Time.current)
      Roadmap.set_positions!(RoadmapItem, positions)
    end
    private_class_method :destination, :move_to!
  end
end
