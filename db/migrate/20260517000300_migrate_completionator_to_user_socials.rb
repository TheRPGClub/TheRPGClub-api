# frozen_string_literal: true

class MigrateCompletionatorToUserSocials < ActiveRecord::Migration[8.1]
  def up
    return unless column_exists?(:rpg_club_users, :completionator_url)

    execute(<<~SQL)
      WITH completionator AS (
        SELECT id AS platform_id FROM social_platforms WHERE LOWER(label) = 'completionator' LIMIT 1
      )
      INSERT INTO user_socials (user_id, platform_id, display_text, url)
      SELECT u.user_id, c.platform_id, TRIM(u.completionator_url), TRIM(u.completionator_url)
      FROM rpg_club_users u
      CROSS JOIN completionator c
      WHERE u.completionator_url IS NOT NULL
        AND TRIM(u.completionator_url) <> ''
      ON CONFLICT (user_id, platform_id, display_text) DO NOTHING;
    SQL
  end

  def down
    return unless table_exists?(:user_socials) && table_exists?(:social_platforms)

    execute(<<~SQL)
      DELETE FROM user_socials
      USING social_platforms
      WHERE user_socials.platform_id = social_platforms.id
        AND LOWER(social_platforms.label) = 'completionator';
    SQL
  end
end
