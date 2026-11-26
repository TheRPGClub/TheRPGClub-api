# frozen_string_literal: true

# The website's address, as the API knows it. The one setting is
# DISCORD_OAUTH_SUCCESS_REDIRECT, the website's sign-in callback, so its
# origin is the website. Read through here by the sign-in redirects
# (Auth::DiscordController), the Feedback Board link (RpgClubFeedback) and the
# Share Card refresh (ShareCard::RefreshJob).
module Website
  ADDRESS_VARIABLE = "DISCORD_OAUTH_SUCCESS_REDIRECT"

  module_function

  # The configured address as a URI, or nil when it is missing or not an
  # absolute http(s) URL: a relative one would point at the API's own host.
  # A fresh URI each call, so a caller may change it.
  def address
    uri = URI.parse(ENV.fetch(ADDRESS_VARIABLE, ""))
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # The website page at `path` with `query`, or nil without an address.
  def url(path, **query)
    uri = address
    return if uri.nil?

    uri.path = path
    uri.query = query.compact.to_query.presence
    uri.fragment = nil
    uri.to_s
  end
end
