# frozen_string_literal: true

module Api
  module V1
    # Patches (GLOSSARY.md "Patch"; spec api#510, ticket api#511), found by
    # their number.
    #
    # Anyone reads the published Patches, Visitors included, so the reads
    # need no sign-in; the feature gate treats a signed-out caller like any
    # non-staff member, who finds Patch Notes only when Live. Drafts are
    # hidden from every read except an Admin's or Superadmin's.
    #
    # Only Admins and Superadmins signed in on the website write: Moderators,
    # members and the bot's service token are refused.
    #
    # Posting to Discord (ticket api#513): writers queue the bot's post of a
    # published Patch and its later edits; unpublishing a posted Patch queues
    # the post's removal. The bot (service token only) records the message it
    # posted or removed through `discord_post`.
    #
    # Refusals carry `{ error, message }` (403 `forbidden`, 422
    # `invalid_patch`, `already_published`, `not_published`, `published`,
    # `already_posted`, `post_queued`, `not_posted`, `invalid_post`).
    class PatchesController < ApplicationController
      feature :patch_notes

      READS = %i[index show].freeze
      TEXT_FIELDS = %w[title body cut_body].freeze
      # Fields a Patch's text needs; `title` may be null.
      REQUIRED_TEXT = %w[body cut_body].freeze
      STATUS_FILTERS = %w[published draft all].freeze
      FORBIDDEN = "Only Admins can write Patches."
      BOT_RECORDS = %i[record_post clear_post].freeze
      DISCORD_ID = /\A\d{1,30}\z/

      skip_before_action :require_authentication!, only: READS
      before_action :require_writer!, except: READS + BOT_RECORDS
      before_action :require_service!, only: BOT_RECORDS

      # GET /api/v1/patches?status=&page=&per=
      #
      # Newest first. `status` is `published` (the default); `draft` and `all`
      # are for writers.
      def index
        status = params[:status].presence || "published"
        unless STATUS_FILTERS.include?(status)
          return render json: { error: "invalid_status", message: "status must be one of #{STATUS_FILTERS.join(', ')}" },
            status: :bad_request
        end
        return forbid unless status == "published" || writer?

        scope = status == "all" ? Patch.all : Patch.where(status: status)
        render_collection(scope, resource: PatchResource, default_order: { number: :desc })
      end

      # GET /api/v1/patches/:number
      def show
        render_patch(find_patch(drafts: writer?), neighbours: true)
      end

      # POST /api/v1/patches
      # Body: { "data": { "title", "rich_body", "body", "cut_body" } }
      def create
        fields = patch_fields
        return if performed?

        render_patch(Patch.create!(fields), status: :created)
      end

      # PATCH /api/v1/patches/:number
      #
      # Changes only the fields given.
      def update
        patch = find_patch
        fields = patch_fields
        return if performed?

        patch.update!(fields)
        render_patch(patch)
      end

      # POST /api/v1/patches/:number/publish
      def publish
        patch = find_patch
        return refuse("already_published", "Patch #{patch.number} is already published.") if patch.published?

        patch.publish!
        render_patch(patch)
      end

      # POST /api/v1/patches/:number/unpublish
      def unpublish
        patch = find_patch
        return refuse("not_published", "Patch #{patch.number} is not published.") unless patch.published?

        patch.unpublish!(requested_by: requester_id)
        render_patch(patch)
      end

      # POST /api/v1/patches/:number/post
      #
      # 202 with the queued `patch_post` bot job. 422 `not_published` for a
      # draft, `already_posted` once posted, `post_queued` while a post is on
      # its way.
      def queue_post
        patch = find_patch
        return refuse("not_published", "Publish Patch #{patch.number} before posting it.") unless patch.published?
        return refuse("already_posted", "Patch #{patch.number} is already posted; update the post instead.") if patch.posted?
        return refuse("post_queued", "Patch #{patch.number} is already on its way to Discord.") if patch.post_queued?

        render_job(patch.queue_post!(requested_by: requester_id))
      end

      # POST /api/v1/patches/:number/update_post
      #
      # 202 with the queued `patch_edit` bot job. 422 `not_posted` unless
      # the Patch is published and posted.
      def queue_post_update
        patch = find_patch
        return refuse("not_posted", "Patch #{patch.number} is not posted.") unless patch.published? && patch.posted?

        render_job(patch.queue_post_edit!(requested_by: requester_id))
      end

      # PUT /api/v1/patches/:number/discord_post (service)
      # Body: { "data": { "channel_id": "...", "message_id": "..." } }
      #
      # The bot posted or edited the Patch's message. 422 `invalid_post`
      # unless both are Discord ids.
      def record_post
        ids = request_data.slice("channel_id", "message_id").transform_values(&:to_s)
        unless ids.size == 2 && ids.values.all?(DISCORD_ID)
          return refuse("invalid_post", "channel_id and message_id must be Discord ids")
        end

        patch = find_patch
        patch.record_post!(channel_id: ids["channel_id"], message_id: ids["message_id"])
        render_patch(patch)
      end

      # DELETE /api/v1/patches/:number/discord_post?message_id= (service)
      #
      # The bot removed message `message_id`; the Patch is no longer posted
      # unless it was posted again since.
      def clear_post
        patch = find_patch
        patch.clear_post!(message_id: params[:message_id].to_s)
        render_patch(patch)
      end

      # DELETE /api/v1/patches/:number
      #
      # Drafts only; its number is never used again.
      def destroy
        patch = find_patch
        return refuse("published", "Unpublish Patch #{patch.number} before deleting it.") if patch.published?

        patch.destroy!
        render json: { data: { number: patch.number, deleted: true } }
      end

      private

      # Admins and Superadmins signed in on the website.
      def writer? = current_principal&.discord_user? && admin_or_above? ? true : false

      def require_writer!
        return render(json: { error: "unauthorized" }, status: :unauthorized) if current_principal.nil?

        forbid unless writer?
      end

      def find_patch(drafts: true)
        scope = drafts ? Patch.all : Patch.published
        scope.find_by!(number: params[:number])
      end

      def render_patch(patch, status: :ok, neighbours: false)
        data = PatchResource.new(patch).serializable_hash
        data = data.merge(previous_number: patch.previous_number, next_number: patch.next_number) if neighbours
        data = data.merge(post_job: post_job(patch)) if writer?
        render json: { data: data }, status: status
      end

      # The latest bot job for its Discord post, for the editor.
      def post_job(patch)
        job = patch.post_job
        job && BotJobResource.new(job).serializable_hash
      end

      # 202: the bot carries the job out; poll GET /bot_jobs/:id for its outcome.
      def render_job(job)
        render json: { data: BotJobResource.new(job).serializable_hash }, status: :accepted
      end

      # The Patch fields `data` gives, as attributes; 422 `invalid_patch` and
      # nil for a field a Patch doesn't take, text that isn't text, a
      # `rich_body` that isn't a list, or a NUL character.
      def patch_fields
        data = request_data
        extra = data.keys - TEXT_FIELDS - %w[rich_body]
        return refuse("invalid_patch", "A Patch doesn't take #{extra.first}") if extra.any?

        TEXT_FIELDS.each do |field|
          next unless data.key?(field)
          next if data[field].is_a?(String) || (data[field].nil? && !REQUIRED_TEXT.include?(field))

          return refuse("invalid_patch", "#{field} must be text")
        end
        return refuse("invalid_patch", "rich_body must be a list") if data.key?("rich_body") && !data["rich_body"].is_a?(Array)
        return refuse("invalid_patch", "A Patch can't hold NUL characters") if nul?(data)

        data.slice(*TEXT_FIELDS, "rich_body")
      end

      def nul?(value)
        case value
        when String then value.include?("\u0000")
        when Hash then value.any? { |key, item| nul?(key) || nul?(item) }
        when Array then value.any? { |item| nul?(item) }
        else false
        end
      end

      # Renders 422 `error`; nil, so a caller can return it as "no fields".
      def refuse(error, message)
        render json: { error: error, message: message }, status: :unprocessable_content
        nil
      end

      def forbid
        render json: { error: "forbidden", message: FORBIDDEN }, status: :forbidden
      end
    end
  end
end
