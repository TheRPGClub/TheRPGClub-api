# frozen_string_literal: true

# Members' `discord_avatar` was only written at website login, so anyone who
# changed their Discord avatar since kept a hash Discord no longer serves and
# showed initials. Take the bot's latest logged hash where it is newer than
# the login (`last_fetched_at`, which only login sets) or there was none.
# From here on UserAvatarHistoryController#create keeps it current.
class RefreshDiscordAvatarFromHistory < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE rpg_club_users u
      SET discord_avatar = h.avatar_hash
      FROM (
        SELECT DISTINCT ON (user_id) user_id, avatar_hash, changed_at
        FROM rpg_club_user_avatar_history
        WHERE avatar_hash ~ '^(a_)?[0-9a-f]{32}$'
        ORDER BY user_id, changed_at DESC, event_id DESC
      ) h
      WHERE u.user_id = h.user_id
        AND (u.last_fetched_at IS NULL OR h.changed_at > u.last_fetched_at)
        AND u.discord_avatar IS DISTINCT FROM h.avatar_hash
    SQL
  end

  def down
    # Data only: the hashes it replaced were stale.
  end
end
