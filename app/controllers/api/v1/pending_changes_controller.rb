# frozen_string_literal: true

module Api
  module V1
    # Pending Changes (GLOSSARY.md "Pending Change"; spec api#510, ticket
    # api#514) and the current versions.
    #
    # Intake is the versioning job's only door: it signs in with its own
    # release token (RPGCLUB_RELEASE_API_TOKEN), which nothing else accepts,
    # and the bot's token and member sessions are refused here. It records
    # one Pending Change per repo and pull request, and a repeat changes
    # nothing. It collects whatever the Feature's state, so nothing that
    # ships before launch is missed.
    #
    # Anyone reads the versions, Visitors included and whatever the Feature's
    # state: they are what a member quotes in a bug report.
    #
    # Admins and Superadmins signed in on the website list, dismiss and undo,
    # and set which ones a Patch covers, behind the Patch Notes Feature gate.
    #
    # Refusals carry `{ error, message }` (403 `forbidden`, 422
    # `invalid_pending_change`, `invalid_pending_changes`, `already_dismissed`,
    # `not_dismissed`, `covered`, `dismissed`, `covered_elsewhere`).
    class PendingChangesController < ApplicationController
      feature :patch_notes, except: %i[create versions]

      INTAKE_FIELDS = %w[repo pr_number type title version patch_note].freeze
      STATUS_FILTERS = (PendingChange::STATUSES + %w[all]).freeze
      FORBIDDEN = "Only Admins can manage Pending Changes."

      skip_before_action :require_authentication!, only: %i[create versions]
      before_action :require_release!, only: :create
      before_action :require_writer!, except: %i[create versions]

      # POST /api/v1/pending_changes (release token only)
      # Body: { "data": { "repo", "pr_number", "type", "title", "version", "patch_note" } }
      #
      # 201 with the new Pending Change, or 200 with the one already recorded
      # for that repo and pull request, unchanged. Other keys are ignored.
      def create
        data = request_data
        existing = PendingChange.find_by(repo: data["repo"].to_s, pr_number: data["pr_number"]) if data["pr_number"].is_a?(Integer)
        return render_change(existing) if existing

        attributes = intake_attributes(data)
        return if performed?

        render_change(PendingChange.create!(attributes), status: :created)
      rescue ActiveRecord::RecordNotUnique
        render_change(PendingChange.find_by!(repo: data["repo"], pr_number: data["pr_number"]))
      end

      # GET /api/v1/versions
      def versions
        render json: { data: PendingChange.versions }
      end

      # GET /api/v1/pending_changes?status=&patch=&page=&per=
      #
      # Newest first. `status` is open (the default), covered, dismissed or
      # all; `patch` keeps the ones that Patch number covers.
      def index
        status = params[:status].presence || PendingChange::OPEN
        unless STATUS_FILTERS.include?(status)
          return render json: { error: "invalid_status", message: "status must be one of #{STATUS_FILTERS.join(', ')}" },
            status: :bad_request
        end

        scope = PendingChange.includes(:patch)
        scope = { PendingChange::OPEN => scope.waiting, PendingChange::COVERED => scope.covered,
                  PendingChange::DISMISSED => scope.dismissed }.fetch(status, scope)
        scope = scope.where(patch: Patch.where(number: params[:patch])) if params[:patch].present?
        render_collection(scope, resource: PendingChangeResource, default_order: { created_at: :desc, id: :desc })
      end

      # POST /api/v1/pending_changes/:id/dismiss
      def dismiss
        change = PendingChange.find(params[:id])
        return refuse("covered", "Patch #{change.patch_number} covers it; uncover it first.") if change.patch_id
        return refuse("already_dismissed", "It is already dismissed.") if change.dismissed_at

        change.update!(dismissed_at: Time.current)
        render_change(change)
      end

      # POST /api/v1/pending_changes/:id/undismiss
      def undismiss
        change = PendingChange.find(params[:id])
        return refuse("not_dismissed", "It is not dismissed.") unless change.dismissed_at

        change.update!(dismissed_at: nil)
        render_change(change)
      end

      # PUT /api/v1/patches/:number/pending_changes
      # Body: { "data": { "ids": [ ... ] } }
      #
      # Sets the whole list a Patch covers: the ids given become covered by
      # it and the ones it covered before but left out open again. Refused
      # whole, changing nothing, for a dismissed one or one another Patch
      # covers.
      def cover
        patch = Patch.find_by!(number: params[:number])
        ids = request_data["ids"]
        unless ids.is_a?(Array) && ids.all?(Integer)
          return refuse("invalid_pending_changes", "ids must be a list of Pending Change ids")
        end

        changes = PendingChange.where(id: ids).to_a
        raise ActiveRecord::RecordNotFound, "not_found" if changes.size < ids.uniq.size
        return refuse("dismissed", "Undo a dismissal before covering it.") if changes.any?(&:dismissed_at)
        if changes.any? { |change| change.patch_id && change.patch_id != patch.id }
          return refuse("covered_elsewhere", "Another Patch covers one of them.")
        end

        PendingChange.transaction do
          PendingChange.where(patch: patch).where.not(id: ids).update_all(patch_id: nil, updated_at: Time.current)
          PendingChange.where(id: ids, patch_id: nil).update_all(patch_id: patch.id, updated_at: Time.current)
        end
        covered = PendingChange.includes(:patch).where(patch: patch).order(created_at: :desc, id: :desc)
        render json: { data: PendingChangeResource.new(covered).serializable_hash }
      end

      private

      def require_release!
        return if warden.authenticate(:release_token, store: false)&.release?
        return render(json: { error: "unauthorized" }, status: :unauthorized) if current_principal.nil?

        render json: { error: "forbidden", message: "Only the versioning job reports Pending Changes." },
          status: :forbidden
      end

      def require_writer!
        forbid unless current_principal&.discord_user? && admin_or_above?
      end

      # The Pending Change attributes `data` gives; 422
      # `invalid_pending_change` and nil when a field is missing or wrong.
      def intake_attributes(data)
        fields = data.slice(*INTAKE_FIELDS)
        wrong = %w[repo type title version].find { |field| !fields[field].is_a?(String) }
        wrong ||= "pr_number" unless fields["pr_number"].is_a?(Integer)
        wrong ||= "patch_note" unless fields["patch_note"].nil? || fields["patch_note"].is_a?(String)
        return refuse("invalid_pending_change", "#{wrong} is missing or not the right kind") if wrong

        change = PendingChange.new(fields.except("type").merge(change_type: fields["type"]))
        return refuse("invalid_pending_change", change.errors.full_messages.to_sentence) unless change.valid?
        if fields.values.grep(String).any? { |value| value.include?("\u0000") }
          return refuse("invalid_pending_change", "A Pending Change can't hold NUL characters")
        end

        change.attributes.slice("repo", "pr_number", "change_type", "title", "version", "patch_note")
      end

      def render_change(change, status: :ok)
        render json: { data: PendingChangeResource.new(change).serializable_hash }, status: status
      end

      # Renders 422 `error`; nil, so a caller can return it as "no attributes".
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
