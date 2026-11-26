# frozen_string_literal: true

# The consumer-audited user column allowlist (#36), shared by the embedded
# user shape (UserSummaryResource) and the full profile payload (UserResource)
# so the two never drift apart.
#
# The web frontend reads exactly these columns: the identity/name fields,
# `is_bot` and `server_left_at` (the members list filters out bots and departed
# members), and the six role flags the members list sorts into its tiers
# (Admins, Moderators, Devs, Regulars, Members, Newcomers). The avatar is fetched from `/users/:id/avatar`, not a column, so
# image/bookkeeping columns (`discord_avatar`, `*_at` timestamps,
# `message_count`, …) are dropped.
module UserFields
  extend ActiveSupport::Concern

  included do
    attributes :user_id, :username, :global_name, :is_bot,
               :role_admin, :role_moderator, :role_regular,
               :role_dev, :role_member, :role_newcomer,
               :server_left_at
  end
end
