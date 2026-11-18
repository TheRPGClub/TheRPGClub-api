# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/codex/fun_facts', type: :request do
  acting_user_id = {
    type: :string,
    description: 'Service only, required on every write: the Discord user id of the member the bot acts for. ' \
                 'Their stored roles decide what they may do, and the Feature Flag applies to them.'
  }
  body = {
    type: :string, maxLength: CodexEntry::FUN_FACT_MAX,
    description: 'The Fun Fact: one or two sentences, up to 300 characters with its mention tokens. Mention ' \
                 'members as `<@discord_id>`; every save pulls them into `mentions`, and an id that is not a ' \
                 'known member stays as text. Surrounding spaces are dropped.'
  }
  refusal = 'Refusals carry `{ error, message }`; `message` is written for members (403 `forbidden`, 422 ' \
            '`invalid_entry`).'
  gate = 'Belongs to the Club Codex Feature: not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but a bot write gets 403 `feature_unavailable` when the Flag hides the ' \
         'Feature from the member it acts for.'
  one_entry = { type: :object, properties: { data: { '$ref' => '#/components/schemas/CodexEntry' } } }

  path '/api/v1/codex/fun_facts' do
    get 'List Fun Facts' do
      tags 'Club Codex'
      description 'Members (any signed-in caller). Newest first. Each carries `viewer` for the acting member; the ' \
                  "bot may name the member it reads for with `acting_user_id`, without which `viewer` is all false. " \
                  '`q` keeps the Fun Facts whose text matches, any case, its characters taken literally. ' \
                  '`editable=true` keeps those the acting member may edit: their own, or every one for a ' \
                  'Moderator and above (the bot must name the member, else 400 `acting_user_id required`). ' \
                  "#{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :q, in: :query, required: false, schema: { type: :string },
        description: 'Words to find in the Fun Fact text.'
      parameter name: :editable, in: :query, required: false, schema: { type: :boolean },
        description: 'true: only the Fun Facts the acting member may edit.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Fun Facts' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CodexEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', '`editable=true` and the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add a Fun Fact' do
      tags 'Club Codex'
      description 'Regulars, Moderators, Admins and Superadmins (a member without the Regulars role gets 403 ' \
                  '"You need the Regulars role to add to the Club Codex."). Published at once, credited to the ' \
                  "acting member. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: { acting_user_id: acting_user_id, body: body }, required: %w[body] }
        },
        required: %w[data]
      }

      response '201', 'added' do
        schema one_entry
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not a Regular or staff, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_entry: `body` blank, not text, over 300 characters or holding a NUL character, ' \
                       'or a field a Fun Fact does not take' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/fun_facts/draw' do
    post 'Draw the next Fun Fact' do
      tags 'Club Codex'
      description 'Members (any signed-in caller); the bot calls it for the member using /funfact, naming them ' \
                  'with `data.acting_user_id`. Returns the next Fun Fact in the queue and marks it shown: never-' \
                  'shown Fun Facts first, newest first; then the one shown longest ago; ties go to the lowest id. ' \
                  'So every Fun Fact is shown once before any repeats, and a new one goes next. Editing a Fun ' \
                  'Fact keeps its place; the Daily Fun Fact draws from the same queue. Concurrent draws get ' \
                  'different Fun Facts while there are enough to go round. `{ "fun_fact": null }` when there are ' \
                  "none. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { acting_user_id: acting_user_id } } }
      }

      response '200', 'the drawn Fun Fact, or null when there are none' do
        schema type: :object, properties: {
          fun_fact: { allOf: [ { '$ref' => '#/components/schemas/CodexEntry' } ], nullable: true }
        }, required: %w[fun_fact]
      end

      response '400', 'the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', '(bot) `feature_unavailable`: the Flag hides the Feature from the member it acts for' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/fun_facts/today' do
    get "Today's Daily Fun Fact" do
      tags 'Club Codex'
      description 'Members (any signed-in caller); the bot may name the member it reads for with ' \
                  '`acting_user_id`, without which `viewer` is all false. The Fun Fact the Daily Fun Fact posted ' \
                  'for the club date (America/New_York). Before today\'s post (15:00 New York) it is the latest ' \
                  'earlier one, so `club_date` is the day it was posted for, which may be before today. ' \
                  '`{ "fun_fact": null, "club_date": null }` when nothing has been posted yet, or when that Fun Fact ' \
                  'has since been deleted. A pure read: it draws nothing, so the Fun Fact queue does not move. ' \
                  "#{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the posted Fun Fact and its club date, or both null' do
        schema type: :object, properties: {
          fun_fact: { allOf: [ { '$ref' => '#/components/schemas/CodexEntry' } ], nullable: true },
          club_date: { type: :string, format: :date, nullable: true,
                       description: 'The club date (America/New_York) the Daily Fun Fact was posted for.' }
        }, required: %w[fun_fact club_date]
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/fun_facts/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a Fun Fact' do
      tags 'Club Codex'
      description "Members (any signed-in caller). #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Fun Fact' do
        schema one_entry
      end

      response '404', 'no such Fun Fact, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Edit a Fun Fact' do
      tags 'Club Codex'
      description 'Its author, or a Moderator and above, for anyone\'s (403 "Only its author or a Moderator can ' \
                  'edit this."). A mentioned member gets no say. Mentions are pulled again from the new `body`. ' \
                  "Editing doesn't move the Fun Fact in the queue. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { acting_user_id: acting_user_id, body: body } } },
        required: %w[data]
      }

      response '200', 'edited' do
        schema one_entry
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not its author or a Moderator, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Fun Fact, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_entry: `body` blank, not text, over 300 characters or holding a NUL character, ' \
                       'or a field a Fun Fact does not take' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Fun Fact' do
      tags 'Club Codex'
      description 'Its author, or a Moderator and above, for anyone\'s (403 "Only its author or a Moderator can ' \
                  'delete this."). A hard delete: its mentions go with it, and the author isn\'t told. The bot ' \
                  "sends `acting_user_id` as a query parameter. #{refusal} #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'deleted' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } },
                  required: %w[id deleted] }
        }
      end

      response '400', 'the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not its author or a Moderator, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Fun Fact, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
