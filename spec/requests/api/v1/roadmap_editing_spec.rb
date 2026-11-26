# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/roadmap editing', type: :request do
  gate = 'Admins and Superadmins only (403 `forbidden` for Moderators and members). Belongs to the Roadmap ' \
         'Feature, so a member who cannot use it gets 404 `not_found` first.'
  roadmap = { type: :object, properties: { data: { '$ref' => '#/components/schemas/Roadmap' } }, required: %w[data] }
  one_milestone = { type: :object, properties: { data: { '$ref' => '#/components/schemas/RoadmapMilestone' } },
                    required: %w[data] }
  one_item = { type: :object, properties: { data: { '$ref' => '#/components/schemas/RoadmapItem' } },
               required: %w[data] }
  deleted = { type: :object, required: %w[data], properties: {
    data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } },
            required: %w[id deleted] }
  } }
  error = { '$ref' => '#/components/schemas/Error' }
  refusal = { '$ref' => '#/components/schemas/RoadmapRefusal' }
  body = lambda do |properties, required = []|
    { type: :object, required: %w[data],
      properties: { data: { type: :object, properties: properties, required: required } } }
  end
  milestone_fields = {
    name: { type: :string, maxLength: RoadmapMilestone::NAME_MAX },
    blurb: { type: :string, nullable: true, maxLength: RoadmapMilestone::BLURB_MAX },
    target_date: { type: :string, format: :date, nullable: true,
                   description: 'Kept on the first day of its period at a vague Date Precision; null for TBA.' },
    date_precision: { type: :string, enum: RoadmapMilestone::DATE_PRECISIONS, description: 'tba when left out.' }
  }
  item_fields = {
    title: { type: :string, maxLength: RoadmapItem::TITLE_MAX },
    blurb: { type: :string, maxLength: RoadmapItem::BLURB_MAX },
    area: { type: :string, nullable: true, enum: [ *RoadmapItem::AREAS, nil ] },
    github_issue_url: { type: :string, nullable: true, maxLength: RoadmapItem::GITHUB_ISSUE_URL_MAX,
                        description: 'A GitHub issue URL (https://github.com/<owner>/<repo>/issues/<n>).' },
    feedback_ids: { type: :array, items: { type: :integer },
                    description: 'Sets its linked Feedback to exactly these (left alone when not sent; [] clears ' \
                                 'them). A Feedback linked to another item moves here. Refused with ' \
                                 '`feedback_not_found` or `invalid_feedback_ids`. Sends no notices.' }
  }
  refused = lambda do |group, what|
    group.response '403', 'not an Admin or Superadmin' do
      schema error
    end
    group.response '404', 'not found, or the Feature is hidden from the caller' do
      schema error
    end
    next unless what

    group.response '422', what do
      schema refusal
    end
  end
  id_param = ->(group) { group.parameter name: :id, in: :path, schema: { type: :integer }, required: true }

  path '/api/v1/roadmap/milestones' do
    post 'Create a Milestone' do
      tags 'Roadmap'
      description "Adds a Milestone last in the order. Other fields are ignored. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: body.call(milestone_fields, %w[name])

      response '201', 'the new Milestone' do
        schema one_milestone
      end
      refused.call(self, 'invalid fields (`{ error }` listing them)')
    end
  end

  path '/api/v1/roadmap/milestones/order' do
    put 'Set the open Milestones\' order' do
      tags 'Roadmap'
      description '`milestone_ids` names every open Milestone once, first to last. Reached Milestones keep their ' \
                  "places in the order, so un-reaching one puts it back where it was. Returns the Roadmap. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true,
        schema: body.call({ milestone_ids: { type: :array, items: { type: :integer } } }, %w[milestone_ids])

      response '200', 'the Roadmap in its new order' do
        schema roadmap
      end
      refused.call(self, '`invalid_order`')
    end
  end

  path '/api/v1/roadmap/milestones/{id}' do
    id_param.call(self)

    patch 'Edit a Milestone' do
      tags 'Roadmap'
      description 'Changes its name, blurb, target date and Date Precision; its place and Reached date change only ' \
                  "through the order and Reach endpoints. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: body.call(milestone_fields)

      response '200', 'the Milestone' do
        schema one_milestone
      end
      refused.call(self, 'invalid fields (`{ error }` listing them)')
    end

    delete 'Delete a Milestone' do
      tags 'Roadmap'
      description "Refused with `milestone_has_items` while it has Roadmap Items: move or delete them first. #{gate}"
      produces 'application/json'

      response '200', 'deleted' do
        schema deleted
      end
      refused.call(self, '`milestone_has_items`')
    end
  end

  path '/api/v1/roadmap/milestones/{id}/items/order' do
    id_param.call(self)

    put 'Set a Milestone\'s Roadmap Item order' do
      tags 'Roadmap'
      description '`item_ids` names every Roadmap Item of the Milestone once, first to last. To move an item to ' \
                  "another Milestone use PUT /roadmap/items/{id}/move. Returns the Roadmap. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true,
        schema: body.call({ item_ids: { type: :array, items: { type: :integer } } }, %w[item_ids])

      response '200', 'the Roadmap in its new order' do
        schema roadmap
      end
      refused.call(self, '`invalid_order`')
    end
  end

  path '/api/v1/roadmap/milestones/{id}/reach' do
    id_param.call(self)

    post 'Reach a Milestone' do
      tags 'Roadmap'
      description 'Marks it Reached (now). First its Roadmap Items that aren\'t Shipped move, in order, to the end ' \
                  'of `destination_milestone_id`: by default the next open Milestone in order, or the open one ' \
                  'before it when it is the last. Only Shipped items stay with it. Refused with ' \
                  '`already_reached`, `invalid_destination` (not another open Milestone) or `no_destination` ' \
                  "(items to move and no open Milestone to take them). Returns the Roadmap. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false,
        schema: body.call({ destination_milestone_id: { type: :integer, nullable: true } })

      response '200', 'the Roadmap' do
        schema roadmap
      end
      refused.call(self, '`already_reached`, `invalid_destination` or `no_destination`')
    end

    delete 'Un-reach a Milestone' do
      tags 'Roadmap'
      description 'Clears its Reached date: it goes back among the open Milestones at its place, and its items ' \
                  "keep their Shipped dates. Refused with `not_reached` for an open one. Returns the Roadmap. #{gate}"
      produces 'application/json'

      response '200', 'the Roadmap' do
        schema roadmap
      end
      refused.call(self, '`not_reached`')
    end
  end

  path '/api/v1/roadmap/items' do
    post 'Create a Roadmap Item' do
      tags 'Roadmap'
      description 'Adds a Roadmap Item last in an open Milestone, not Shipped. Other fields are ignored. Refused ' \
                  "with `milestone_not_found` or `milestone_reached`. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true,
        schema: body.call(item_fields.merge(milestone_id: { type: :integer }), %w[milestone_id title blurb])

      response '201', 'the new Roadmap Item' do
        schema one_item
      end
      refused.call(self, '`milestone_not_found`, `milestone_reached`, `feedback_not_found`, ' \
                           '`invalid_feedback_ids`, or invalid fields')
    end
  end

  path '/api/v1/roadmap/items/{id}' do
    id_param.call(self)

    patch 'Edit a Roadmap Item' do
      tags 'Roadmap'
      description 'Changes its title, blurb, area, GitHub issue and linked Feedback; its Milestone, place and ' \
                  "Shipped date change only through the move and ship endpoints. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: body.call(item_fields)

      response '200', 'the Roadmap Item' do
        schema one_item
      end
      refused.call(self, '`feedback_not_found`, `invalid_feedback_ids`, or invalid fields')
    end

    delete 'Delete a Roadmap Item' do
      tags 'Roadmap'
      description "Its Feedback links go with it. #{gate}"
      produces 'application/json'

      response '200', 'deleted' do
        schema deleted
      end
      refused.call(self, nil)
    end
  end

  path '/api/v1/roadmap/items/{id}/move' do
    id_param.call(self)

    put 'Move a Roadmap Item' do
      tags 'Roadmap'
      description 'Puts it at `position` (from 1; past the end means last) in an open Milestone, its own or ' \
                  'another; that Milestone\'s items are numbered from 1 again. Refused with `milestone_reached`, ' \
                  "`milestone_not_found` or `invalid_position`. Returns the Roadmap. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true,
        schema: body.call({ milestone_id: { type: :integer }, position: { type: :integer, minimum: 1 } },
          %w[milestone_id position])

      response '200', 'the Roadmap' do
        schema roadmap
      end
      refused.call(self, '`milestone_reached`, `milestone_not_found` or `invalid_position`')
    end
  end

  path '/api/v1/roadmap/items/{id}/ship' do
    id_param.call(self)

    post 'Ship a Roadmap Item' do
      tags 'Roadmap'
      description "Marks it Shipped (now). An item already Shipped keeps its date. #{gate}"
      produces 'application/json'

      response '200', 'the Roadmap Item' do
        schema one_item
      end
      refused.call(self, nil)
    end

    delete 'Un-ship a Roadmap Item' do
      tags 'Roadmap'
      description 'Clears its Shipped date. Refused with `milestone_reached` while its Milestone is Reached, which ' \
                  "keeps only Shipped items: move it to an open Milestone or un-reach that one first. #{gate}"
      produces 'application/json'

      response '200', 'the Roadmap Item' do
        schema one_item
      end
      refused.call(self, '`milestone_reached`')
    end
  end
end
