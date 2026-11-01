# frozen_string_literal: true

module Api
  module V1
    # A member's Linked Accounts (api-05): list, link, unlink, Retry and Sync
    # now. Owner-only (the bot service counts as the owner); an admin may also
    # unlink any member's Linked Account. Every write that makes an account
    # due kicks its Provider's tick, which drains the durable sync state
    # (ADR 0003).
    class LinkedAccountsController < ApplicationController
      before_action :require_owner!, only: %i[index create retry sync]
      before_action :require_owner_or_admin!, only: :destroy

      # A Retry restarts syncing that stopped on these statuses.
      RETRYABLE_STATUSES = %w[private not_found error].freeze
      # Sync now can't restart these; the member presses Retry instead.
      RETRY_REQUIRED_STATUSES = %w[private not_found].freeze

      # GET /api/v1/users/:user_id/linked_accounts
      # At most one per Provider, so the list is not paginated.
      def index
        accounts = member_accounts.order(:provider)
        render json: { data: serialize(accounts) }
      end

      # POST /api/v1/users/:user_id/linked_accounts
      # Body: { "data": { "provider": "steam", "identifier": "gabe" } }
      #
      # Resolves the identifier through the Provider and stores its stable id,
      # due now for a Backfill. 422 `provider_already_linked` /
      # `identity_claimed` on a conflict, `not_found` / `private` when the
      # Provider can't see the account, `invalid_provider` for an unknown one.
      def create
        data = request_data
        provider = data["provider"].to_s
        identifier = data["identifier"].to_s.strip
        raise ActionController::ParameterMissing, :identifier if identifier.empty?
        return render_reason(:invalid_provider, "Unknown Provider #{provider}.") unless
          UserLinkedAccount::PROVIDERS.include?(provider)
        return render_provider_already_linked if member_accounts.exists?(provider: provider)

        identity = Achievements::ResolveAccount.call(provider, identifier)
        return render_identity_claimed if claimed?(provider, identity[:external_id])

        account = member_accounts.create!(
          provider: provider, **identity,
          sync_status: "pending", sync_mode: "backfill", sync_due_at: Time.current
        )
        Achievements::ProviderTickJob.perform_later(provider)
        render json: { data: serialize(account) }, status: :created
      rescue Achievements::Providers::NotFound => error
        render_reason(:not_found, error.message)
      rescue Achievements::Providers::Private => error
        render_reason(:private, error.message)
      rescue Achievements::ResolveAccount::Unavailable
        render json: { error: "provider_unavailable", message: "The Provider can't be reached right now. Try again later." },
          status: :service_unavailable
      rescue ActiveRecord::RecordNotUnique
        # Lost a race on one of the two unique indexes.
        member_accounts.exists?(provider: provider) ? render_provider_already_linked : render_identity_claimed
      end

      # DELETE /api/v1/users/:user_id/linked_accounts/:id
      # Unlinks. The database cascades delete the account's Unlocks and
      # progress; the shared definitions stay.
      def destroy
        account.destroy!
        render json: { deleted: true }
      end

      # POST /api/v1/users/:user_id/linked_accounts/:id/retry
      # Only from private, not_found or error: back to pending, due now.
      def retry
        unless RETRYABLE_STATUSES.include?(account.sync_status)
          return render_reason(:retry_not_allowed, "Retry is only available when syncing has stopped.")
        end

        make_due(sync_status: "pending", sync_error: nil)
        render json: { data: serialize(account) }
      end

      # POST /api/v1/users/:user_id/linked_accounts/:id/sync
      # Sync now, at most once per UserLinkedAccount::SYNC_COOLDOWN; 429 with
      # `sync_available_at` inside it.
      def sync
        if RETRY_REQUIRED_STATUSES.include?(account.sync_status)
          return render_reason(:retry_required, "Syncing has stopped for this account. Press Retry instead.")
        end

        now = Time.current
        available_at = account.sync_available_at(now)
        if available_at > now
          return render json: {
            error: "sync_cooldown", message: "Sync now is cooling down.", sync_available_at: available_at
          }, status: :too_many_requests
        end

        make_due(sync_requested_at: now, now: now)
        render json: { data: serialize(account) }
      end

      private

      def account
        @account ||= member_accounts.find(params[:id])
      end

      # Due now, as a Backfill until one has finished, else incremental; then
      # kicks the Provider's tick.
      def make_due(now: Time.current, **attrs)
        account.update!(
          sync_due_at: now, sync_mode: account.backfilled_at ? "incremental" : "backfill", **attrs
        )
        Achievements::ProviderTickJob.perform_later(account.provider)
      end

      def require_owner_or_admin!
        return true if admin_or_service?

        require_owner!
      end

      def member_accounts
        UserLinkedAccount.where(user_id: params[:user_id])
      end

      def claimed?(provider, external_id)
        UserLinkedAccount.where(provider: provider, external_id: external_id).exists?
      end

      def render_reason(reason, message, status: :unprocessable_entity)
        render json: { error: reason.to_s, message: message }, status: status
      end

      def render_provider_already_linked
        render_reason(:provider_already_linked, "You already have a Linked Account on this Provider.")
      end

      def render_identity_claimed
        render_reason(:identity_claimed, "Another member has already linked this account.")
      end

      def serialize(account_or_accounts)
        LinkedAccountResource.new(account_or_accounts, params: { now: Time.current }).serializable_hash
      end
    end
  end
end
