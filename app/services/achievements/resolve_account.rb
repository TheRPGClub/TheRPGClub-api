# frozen_string_literal: true

module Achievements
  # Turns what a member types when linking (an RA username, a Steam vanity
  # name, profile URL or SteamID64, or a PSN online ID) into the Provider's
  # stable identity: `{ external_id:, display_name: }`. external_id is the RA
  # ULID, the SteamID64 or the PSN accountId, never a renameable name.
  #
  # Raises Providers::NotFound or Providers::Private for the member to fix,
  # and Unavailable for anything else (rate limits, auth, a missing Provider
  # configuration, a network failure), which is not the member's fault.
  class ResolveAccount
    class Unavailable < StandardError; end

    def self.call(provider, identifier)
      new(provider).call(identifier)
    end

    def initialize(provider)
      @provider = provider.to_s
      @client = Providers.client_for(@provider)
    end

    def call(identifier)
      identity = resolve(identifier.to_s.strip)
      { external_id: identity.fetch(:external_id).to_s, display_name: identity[:display_name].presence }
    rescue Providers::NotFound, Providers::Private
      raise
    rescue StandardError => error
      Rails.logger.warn("Linked Account resolution failed (#{@provider}): #{error.class}: #{error.message}")
      raise Unavailable, error.message
    end

    private

    def resolve(identifier)
      case @provider
      when "retroachievements" then @client.user_profile(identifier)
      when "steam" then resolve_steam(identifier)
      when "psn" then @client.resolve_account(identifier)
      end
    end

    # A malformed identifier, or a vanity name Steam can't resolve, is NotFound;
    # so is a SteamID64 Steam lists no player for.
    def resolve_steam(identifier)
      steam_id64 = @client.resolve_profile(identifier).fetch(:steam_id64)
      name = @client.player_summary(steam_id64)[:profile_name]
      raise Providers::NotFound, "No Steam profile #{identifier}." if name.blank?

      { external_id: steam_id64, display_name: name }
    rescue Steam::Client::Error => error
      case error.code
      when "invalid_identifier" then raise Providers::NotFound, error.message
      when "private_profile" then raise Providers::Private, error.message
      else raise
      end
    end
  end
end
