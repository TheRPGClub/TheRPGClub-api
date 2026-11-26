# frozen_string_literal: true

module ShareCard
  # Tells the website a GOTM round was decided, so it refreshes its Share
  # Card (GLOSSARY.md, "Share Card"; spec #518): a POST to the website's
  # /api/revalidate with `Authorization: Bearer $REVALIDATE_SECRET`, which
  # revalidates the website's `gotm` reads. Queued by ShareCard.refresh_later
  # once a round's decision commits. It first clears the API's own cached
  # winners payload (Api::V1::Public::WinnersController.expire_cache), so the
  # website's refetch sees the new winners rather than a payload cached
  # before them.
  #
  # A failed POST (a network error or a non-2xx answer) is retried with
  # backoff, then given up and logged: the website re-checks the winners once
  # a day anyway. Without REVALIDATE_SECRET or the website's address
  # (Website) it does nothing but log, as in dev and test.
  class RefreshJob < ApplicationJob
    class RefreshFailed < StandardError; end

    PATH = "/api/revalidate"
    TIMEOUT_SECONDS = 10

    queue_as :default

    retry_on RefreshFailed, Faraday::Error, wait: :polynomially_longer, attempts: 5 do |_job, error|
      Rails.logger.warn({ event: "share_card.refresh_gave_up", error: "#{error.class}: #{error.message}" }.to_json)
    end

    def perform
      Api::V1::Public::WinnersController.expire_cache
      secret = ENV["REVALIDATE_SECRET"].presence
      url = Website.url(PATH)
      if secret.nil? || url.nil?
        Rails.logger.info({ event: "share_card.refresh_skipped",
          reason: secret.nil? ? "REVALIDATE_SECRET is not set" : "the website's address is not set" }.to_json)
        return
      end

      response = Faraday.default_connection.post(url) do |request|
        request.headers["Authorization"] = "Bearer #{secret}"
        request.options.timeout = TIMEOUT_SECONDS
      end
      raise RefreshFailed, "POST #{url} answered #{response.status}" unless response.success?
    end
  end
end
