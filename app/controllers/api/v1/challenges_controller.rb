# frozen_string_literal: true

module Api
  module V1
    # Challenges (GLOSSARY.md, "Challenges"; spec #376, ticket #377). Members
    # list and read them; Regulars and staff create them; the Host and staff
    # change them as Challenges::Actor decides. Gated by the `challenges`
    # Feature.
    #
    # The bot acts for a Discord user with the service token and names them
    # (`acting_user_id`: a query parameter on reads, `data.acting_user_id` on
    # writes); the API then decides from that member's stored roles, and
    # applies the Feature Flag to them, since the service passes the feature
    # gate (docs/adr/0005). A write without an acting member is a 400.
    class ChallengesController < ApplicationController
      include ChallengeActing

      feature :challenges

      WRITES = %i[create update destroy hide unhide change_host change_tint].freeze

      before_action :require_acting_member!, only: WRITES

      rescue_from Challenges::Invalid do |error|
        render json: { error: "invalid_challenge", message: error.message }, status: :unprocessable_content
      end
      rescue_from Challenges::RulesLocked do |error|
        render json: { error: "rules_locked", message: error.message, fields: error.fields }, status: :conflict
      end

      # GET /api/v1/challenges?open=true&challenge_format=pool&q=final
      #
      # Newest first. `open` (true or false) narrows to the Challenges Open or
      # Closed today; `challenge_format` to one Challenge Format; `q` to those
      # whose name contains it, ignoring case (the bot's autocomplete). Hidden
      # Challenges are listed only for Moderators and above, and for their
      # Host. Each carries its Run and Finished counts and its first Pool
      # games, read for the whole page at once (Challenges::Overview).
      def index
        scope = visible_challenges
        scope = scope.where(challenge_format: format_filter) if params[:challenge_format].present?
        return if performed?

        scope = open_filter(scope)
        return if performed?

        scope = name_filter(scope)

        render_collection(ChallengeResource.preloaded(scope), resource: ChallengeResource,
          default_order: { created_at: :desc, id: :desc }, params: { today: Challenges.today },
          prepare: ->(challenges) { { overview: Challenges::Overview.of(challenges) } })
      end

      # GET /api/v1/challenges/:id
      def show
        render_challenge(find_visible)
      end

      # POST /api/v1/challenges
      # Body: { "data": { name, description, challenge_format, schedule,
      # ends_on, season, pool, hosted_by_club } }
      #
      # The acting member becomes the Host, or the club when
      # `hosted_by_club` is true (Moderator and above). A name another
      # Challenge already has is allowed, with a `duplicate_name` warning in
      # `meta.warnings`. Queues a `challenge_announce` bot job.
      def create
        data = request_data
        return forbid(Challenges::Refusals::CREATE) unless actor.can_create?

        club = ActiveModel::Type::Boolean.new.cast(data["hosted_by_club"]) ? true : false
        return forbid(Challenges::Refusals::CLUB_HOSTED) if club && !actor.can_host_for_club?

        challenge = Challenge.new(host_user_id: club ? nil : actor.user_id, created_by: actor.user_id,
          updated_by: actor.user_id)
        Challenge.transaction do
          Challenges::Form.new(challenge, data.except("hosted_by_club", "acting_user_id")).save!
          Challenges::Announcements.challenge_created!(reload(challenge), by: actor.user_id)
        end
        render_challenge(challenge, status: :created, meta: { warnings: duplicate_warnings(challenge) })
      end

      # PATCH /api/v1/challenges/:id
      # Body: { "data": { ...any of create's fields but hosted_by_club } }
      def update
        challenge = find_visible
        return forbid(Challenges::Refusals::EDIT) unless actor.can_edit?(challenge)

        challenge.updated_by = actor.user_id
        Challenges::Form.new(challenge, request_data.except("acting_user_id")).save!
        render_challenge(challenge)
      end

      # DELETE /api/v1/challenges/:id
      #
      # The Host deletes their own while it has no Runs; a Moderator or
      # above removes any, with its Runs.
      def destroy
        challenge = find_visible
        return forbid(Challenges::Refusals::DELETE) unless actor.can_delete?(challenge)

        challenge.with_lock do
          if !actor.moderator_or_above? && challenge.runs?
            return render json: { error: "has_runs", message: Challenges::Refusals::DELETE_WITH_RUNS },
              status: :conflict
          end

          challenge.destroy!
        end
        render json: { data: { id: challenge.id, deleted: true } }
      end

      # POST /api/v1/challenges/:id/hide and /unhide (Moderator and above).
      def hide = moderate { |challenge| challenge.update!(hidden: true, updated_by: actor.user_id) }

      def unhide = moderate { |challenge| challenge.update!(hidden: false, updated_by: actor.user_id) }

      # PUT /api/v1/challenges/:id/host (Moderator and above)
      # Body: { "data": { "host_user_id": "..." } } or { "data": { "hosted_by_club": true } }
      #
      # Hands the Challenge to another member, who need not hold any role,
      # or to the club.
      def change_host
        data = request_data
        moderate do |challenge|
          host_id = ActiveModel::Type::Boolean.new.cast(data["hosted_by_club"]) ? nil : data["host_user_id"].presence&.to_s
          if host_id.nil? && !ActiveModel::Type::Boolean.new.cast(data["hosted_by_club"])
            raise Challenges::Invalid, "host_user_id or hosted_by_club is required"
          end
          if host_id && !RpgClubUser.where(user_id: host_id, is_bot: false).exists?
            raise Challenges::Invalid, "#{host_id} is not a member"
          end

          challenge.update!(host_user_id: host_id, updated_by: actor.user_id)
        end
      end

      # PUT /api/v1/challenges/:id/tint
      # Body: { "data": { "tint": "teal" | { "fill": "#rrggbb", "hi": "#rrggbb" } | null } }
      #
      # The Host changes their own Challenge's tint (as PATCH can), and a
      # Moderator or above any Challenge's, which PATCH does not let them
      # edit. Null gives the Challenge its curated tint back.
      def change_tint
        data = request_data
        challenge = find_visible
        return forbid(Challenges::Refusals::TINT) unless actor.can_change_tint?(challenge)
        raise Challenges::Invalid, "tint is required: a curated tint's name, { fill, hi } or null" unless data.key?("tint")

        challenge.update!(tint: Challenges::Tint.parse(data["tint"]), updated_by: actor.user_id)
        render_challenge(challenge)
      end

      # POST /api/v1/challenges/pool_preview
      # Body: { "data": { franchise_ids, collection_ids, included_game_ids, excluded_game_ids } }
      #
      # The games a draft Pool definition resolves to, oldest release first,
      # so the bot and the website can show them before saving.
      def pool_preview
        definition = Challenges::PoolDefinition.parse(request_data.except("acting_user_id"))
        errors = definition.errors
        raise Challenges::Invalid, errors.join(". ") if errors.any?

        games = definition.games.preload(:images)
        render_collection(games, resource: GameSummaryResource,
          default_order: Arel.sql("gamedb_games.initial_release_date ASC NULLS LAST, gamedb_games.title ASC"))
      end

      # GET /api/v1/challenges/pool_sources?q=final
      #
      # The GameDB franchises and collections whose name matches `q`, with
      # how many games each has, for building a Pool. At most 25 of each.
      def pool_sources
        query = params[:q].to_s.strip
        return render(json: { error: "q is required" }, status: :bad_request) if query.empty?

        render json: { data: pool_sources_for(query) }
      end

      private

      def moderate
        challenge = find_visible
        return forbid(Challenges::Refusals::MODERATE) unless actor.can_moderate?

        yield challenge
        render_challenge(challenge)
      end

      # A Challenge the actor may see; a hidden one is not found for others.
      def find_visible
        visible_challenges.find(params[:id])
      end

      def reload(challenge)
        ChallengeResource.preloaded(Challenge.where(id: challenge.id)).first!
      end

      def render_challenge(challenge, status: :ok, meta: nil)
        challenge = reload(challenge)
        body = { data: ChallengeResource.new(challenge, params: { detail: true }).serializable_hash }
        body[:meta] = meta if meta
        render json: body, status: status
      end

      # Other Challenges the actor can see with the same name, ignoring case.
      def duplicate_warnings(challenge)
        same = visible_challenges.where.not(id: challenge.id).where("lower(name) = lower(?)", challenge.name)
          .order(:id).pluck(:id)
        return [] if same.empty?

        [ { code: "duplicate_name", challenge_ids: same,
            message: "A Challenge named \"#{challenge.name}\" already exists. You may want to join it instead." } ]
      end

      def format_filter
        format = params[:challenge_format].to_s
        return format if Challenge::FORMATS.include?(format)

        render json: { error: "unknown challenge_format: #{format}" }, status: :bad_request
        nil
      end

      def open_filter(scope)
        case params[:open].presence
        when nil then scope
        when "true" then scope.open_on(Challenges.today)
        when "false" then scope.closed_on(Challenges.today)
        else render(json: { error: "open must be true or false" }, status: :bad_request) && nil
        end
      end

      def name_filter(scope)
        query = params[:q].to_s.strip
        return scope if query.empty?

        scope.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      end

      def pool_sources_for(query)
        like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        franchises = GamedbFranchise.where("name ILIKE ?", like).order(:name).limit(25)
        franchise_counts = GamedbGameFranchise.where(franchise_id: franchises.map(&:franchise_id)).group(:franchise_id).count
        collections = GamedbCollection.where("name ILIKE ?", like).order(:name).limit(25)
        collection_counts = GamedbGame.where(collection_id: collections.map(&:collection_id)).group(:collection_id).count

        franchises.map do |row|
          { kind: "franchise", id: row.franchise_id, name: row.name, game_count: franchise_counts.fetch(row.franchise_id, 0) }
        end + collections.map do |row|
          { kind: "collection", id: row.collection_id, name: row.name,
            game_count: collection_counts.fetch(row.collection_id, 0) }
        end
      end
    end
  end
end
