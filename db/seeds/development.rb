# frozen_string_literal: true

puts "Seeding development data..."

# A club-sized cast: enough distinct members that a nomination round (one
# nomination per user per round) and a vote tally have something to show.
users = [
  { username: "dev_admin",      global_name: "Dev Admin",      role_admin: true, role_moderator: true, role_member: true },
  { username: "party_member",   global_name: "Party Member",   role_regular: true, role_member: true },
  { username: "tavern_keeper",  global_name: "Tavern Keeper",  role_moderator: true, role_member: true },
  { username: "dice_goblin",    global_name: "Dice Goblin",    role_regular: true, role_member: true },
  { username: "loot_hoarder",   global_name: "Loot Hoarder",   role_member: true },
  { username: "crit_fisher",    global_name: "Crit Fisher",    role_regular: true, role_member: true },
  { username: "save_scummer",   global_name: "Save Scummer",   role_member: true },
  { username: "lore_reader",    global_name: "Lore Reader",    role_regular: true, role_member: true },
  { username: "speedrunner",    global_name: "Speedrunner",    role_member: true },
  { username: "backlog_slayer", global_name: "Backlog Slayer", role_member: true, role_newcomer: true },
  { username: "couch_coop",     global_name: "Couch Co-op",    role_member: true },
  { username: "night_owl",      global_name: "Night Owl",      role_regular: true, role_member: true }
].each_with_index.to_h do |attributes, index|
  # The 1000000000000000xx id block marks a seeded account;
  # db/seeds/development/voting.rb selects on it to avoid dragging real
  # bot-synced Discord users into a nomination round.
  attributes = attributes.merge(
    user_id: format("1000000000000000%02d", index + 1),
    server_joined_at: (24 - index).months.ago
  )
  user = RpgClubUser.find_or_initialize_by(user_id: attributes.fetch(:user_id))
  user.update!(attributes)
  [ attributes.fetch(:username), user ]
end

platforms = [
  { platform_code: "PC", platform_name: "PC" },
  { platform_code: "PS5", platform_name: "PlayStation 5" },
  { platform_code: "SWITCH", platform_name: "Nintendo Switch" },
  { platform_code: "XSX", platform_name: "Xbox Series X|S" }
].to_h do |attributes|
  platform = GamedbPlatform.find_or_initialize_by(platform_code: attributes.fetch(:platform_code))
  platform.update!(attributes)
  [ attributes.fetch(:platform_code), platform ]
end

genres = [
  { igdb_genre_id: -10_001, name: "Role-playing (RPG)" },
  { igdb_genre_id: -10_002, name: "Adventure" },
  { igdb_genre_id: -10_003, name: "Strategy" },
  { igdb_genre_id: -10_004, name: "Shooter" },
  { igdb_genre_id: -10_005, name: "Platform" },
  { igdb_genre_id: -10_006, name: "Puzzle" },
  { igdb_genre_id: -10_007, name: "Racing" },
  { igdb_genre_id: -10_008, name: "Indie" },
  { igdb_genre_id: -10_009, name: "Simulator" }
].to_h do |attributes|
  genre = GamedbGenre.find_or_initialize_by(igdb_genre_id: attributes.fetch(:igdb_genre_id))
  genre.update!(attributes)
  [ attributes.fetch(:name), genre ]
end

companies = [
  { igdb_company_id: -20_001, name: "Lantern Bear Studio" },
  { igdb_company_id: -20_002, name: "Copper Lantern Games" },
  { igdb_company_id: -20_003, name: "Halfhand Interactive" },
  { igdb_company_id: -20_004, name: "Nine Volt Collective" }
].to_h do |attributes|
  company = GamedbCompany.find_or_initialize_by(igdb_company_id: attributes.fetch(:igdb_company_id))
  company.update!(attributes)
  [ attributes.fetch(:name), company ]
end

# Two pools on purpose: the RPG titles are the GOTM nomination field and the
# rest are the Non-RPG GOTM field, so a seeded round never nominates an RPG
# for NR-GOTM. db/seeds/development/voting.rb reads them back by slug.
games = [
  { title: "Ashes of Asteria", slug: "ashes-of-asteria", rating: 88, released: Date.new(2024, 3, 14),
    description: "A party-based fantasy RPG used for local development.",
    platforms: %w[PC PS5], genres: [ "Role-playing (RPG)", "Adventure" ], developer: "Lantern Bear Studio" },
  { title: "Moonlit Tactics", slug: "moonlit-tactics", rating: 82, released: Date.new(2023, 10, 20),
    description: "A compact tactical RPG used to exercise collection APIs.",
    platforms: %w[PC SWITCH], genres: [ "Role-playing (RPG)", "Strategy" ], developer: "Lantern Bear Studio" },
  { title: "Clockwork Kingdom", slug: "clockwork-kingdom", rating: 76, released: Date.new(2025, 1, 9),
    description: "An adventure game available as seeded backlog data.",
    platforms: %w[PS5 SWITCH], genres: [ "Adventure" ], developer: "Copper Lantern Games" },
  { title: "Verdant Hollow", slug: "verdant-hollow", rating: 91, released: Date.new(2024, 6, 4),
    description: "An open-ended botany RPG about regrowing a dead valley.",
    platforms: %w[PC XSX], genres: [ "Role-playing (RPG)", "Adventure" ], developer: "Copper Lantern Games" },
  { title: "Iron Covenant", slug: "iron-covenant", rating: 79, released: Date.new(2022, 11, 11),
    description: "A grim tactical RPG where every recruit stays dead.",
    platforms: %w[PC PS5], genres: [ "Role-playing (RPG)", "Strategy" ], developer: "Halfhand Interactive" },
  { title: "Starfall Wardens", slug: "starfall-wardens", rating: 85, released: Date.new(2023, 5, 26),
    description: "A space-opera RPG with a rotating crew of six wardens.",
    platforms: %w[PC PS5 XSX], genres: [ "Role-playing (RPG)" ], developer: "Halfhand Interactive" },
  { title: "Emberlight Chronicles", slug: "emberlight-chronicles", rating: 73, released: Date.new(2021, 9, 30),
    description: "A slow-burn JRPG homage with a much-debated second act.",
    platforms: %w[PC SWITCH], genres: [ "Role-playing (RPG)", "Adventure" ], developer: "Nine Volt Collective" },
  { title: "The Sunken Archive", slug: "the-sunken-archive", rating: 87, released: Date.new(2025, 2, 18),
    description: "A cryptic RPG about cataloguing a drowned library.",
    platforms: %w[PC], genres: [ "Role-playing (RPG)", "Puzzle" ], developer: "Nine Volt Collective" },
  { title: "Grimoire of Tides", slug: "grimoire-of-tides", rating: 80, released: Date.new(2024, 8, 23),
    description: "A seafaring RPG where spells are written on the weather.",
    platforms: %w[PC PS5 SWITCH], genres: [ "Role-playing (RPG)" ], developer: "Lantern Bear Studio" },
  { title: "Hollow Vanguard", slug: "hollow-vanguard", rating: 68, released: Date.new(2020, 4, 17),
    description: "A divisive squad RPG the club keeps nominating anyway.",
    platforms: %w[PC XSX], genres: [ "Role-playing (RPG)", "Strategy" ], developer: "Copper Lantern Games" },
  { title: "Saltmarsh Requiem", slug: "saltmarsh-requiem", rating: 94, released: Date.new(2025, 6, 6),
    description: "The highest-rated seeded RPG, useful for sort assertions.",
    platforms: %w[PC PS5], genres: [ "Role-playing (RPG)", "Adventure" ], developer: "Halfhand Interactive" },
  { title: "Nine Lives of Rhea", slug: "nine-lives-of-rhea", rating: 77, released: Date.new(2022, 2, 22),
    description: "A short indie RPG that restarts from a different cat each run.",
    platforms: %w[SWITCH PC], genres: [ "Role-playing (RPG)", "Indie" ], developer: "Nine Volt Collective" },
  { title: "Neon Drift Rally", slug: "neon-drift-rally", rating: 81, released: Date.new(2024, 1, 30),
    description: "Arcade racing; seeded for the Non-RPG GOTM field.",
    platforms: %w[PC PS5 XSX], genres: [ "Racing" ], developer: "Nine Volt Collective" },
  { title: "Bolt & Bramble", slug: "bolt-and-bramble", rating: 89, released: Date.new(2023, 7, 12),
    description: "A two-player platformer about a robot and a hedge.",
    platforms: %w[SWITCH PC], genres: [ "Platform", "Indie" ], developer: "Copper Lantern Games" },
  { title: "Tessera", slug: "tessera", rating: 84, released: Date.new(2022, 5, 5),
    description: "A tile-laying puzzler with a hundred-hour endgame.",
    platforms: %w[PC SWITCH], genres: [ "Puzzle", "Indie" ], developer: "Halfhand Interactive" },
  { title: "Deep Signal", slug: "deep-signal", rating: 78, released: Date.new(2025, 3, 27),
    description: "A submarine shooter with no HUD and a lot of sonar.",
    platforms: %w[PC XSX PS5], genres: [ "Shooter" ], developer: "Lantern Bear Studio" },
  { title: "Harbourline", slug: "harbourline", rating: 75, released: Date.new(2021, 11, 2),
    description: "A port-logistics simulator; the club's comfort pick.",
    platforms: %w[PC], genres: [ "Simulator" ], developer: "Nine Volt Collective" },
  { title: "Paperfold Pilgrims", slug: "paperfold-pilgrims", rating: 86, released: Date.new(2024, 10, 15),
    description: "Origami puzzles wrapped around a wordless pilgrimage.",
    platforms: %w[SWITCH PC], genres: [ "Puzzle", "Indie" ], developer: "Copper Lantern Games" },
  { title: "Static Bloom", slug: "static-bloom", rating: 71, released: Date.new(2023, 2, 9),
    description: "A roguelite shooter that only seeded users seem to like.",
    platforms: %w[PC XSX], genres: [ "Shooter", "Indie" ], developer: "Halfhand Interactive" }
].each_with_index.to_h do |attributes, index|
  game = GamedbGame.find_or_initialize_by(igdb_id: -30_001 - index)
  game.update!(
    title: attributes.fetch(:title),
    slug: attributes.fetch(:slug),
    description: attributes.fetch(:description),
    total_rating: attributes.fetch(:rating),
    initial_release_date: attributes.fetch(:released)
  )

  attributes.fetch(:platforms).each do |code|
    GamedbGamePlatform.find_or_create_by!(game: game, platform: platforms.fetch(code))
  end
  attributes.fetch(:genres).each do |name|
    GamedbGameGenre.find_or_create_by!(game: game, genre: genres.fetch(name))
  end
  GamedbGameCompany.find_or_create_by!(
    game: game, company: companies.fetch(attributes.fetch(:developer)), role: "Developer"
  )

  [ attributes.fetch(:slug), game ]
end

region = GamedbRegion.find_or_initialize_by(region_code: "WW")
region.update!(region_name: "Worldwide", igdb_region_id: -40_001)

GamedbRelease.find_or_create_by!(
  game: games.fetch("ashes-of-asteria"),
  platform: platforms.fetch("PC"),
  region: region
).update!(format: "Digital", release_date: Date.new(2024, 3, 14))

admin = users.fetch("dev_admin")
member = users.fetch("party_member")
ashes = games.fetch("ashes-of-asteria")
moonlit = games.fetch("moonlit-tactics")
clockwork = games.fetch("clockwork-kingdom")

UserGameCollection.find_or_create_by!(
  user: admin,
  game: ashes,
  platform: platforms.fetch("PC"),
  ownership_type: "Digital"
).update!(note: "Seeded collection entry")

UserGameBacklog.find_or_create_by!(
  user: admin,
  game: clockwork,
  platform: platforms.fetch("PS5")
).update!(sort_order: 1, note: "Play after the current GOTM")

UserGameFavorite.find_or_create_by!(user: admin, game: ashes).update!(sort_order: 1)
UserNowPlaying.find_or_create_by!(user: member, game: moonlit).update!(
  platform: platforms.fetch("SWITCH"),
  note: "Halfway through chapter four"
)
review = UserGameReview.find_or_initialize_by(user: member, game: ashes)
review.update!(
  rating: 90,
  body: { summary: "Great party combat and a strong soundtrack." },
  is_shared: true
)

# Give every member a small library so the per-user endpoints return something
# for whichever seeded account the client logs in as. Deterministic slicing
# (not sampling) keeps re-runs idempotent.
game_list = games.values
users.values.each_with_index do |user, index|
  owned = game_list.rotate(index * 3).first(3)
  owned.each_with_index do |game, offset|
    platform = game.platforms.first
    UserGameCollection.find_or_create_by!(
      user: user, game: game, platform: platform,
      ownership_type: offset.zero? ? "Physical" : "Digital"
    )
  end

  backlog = game_list.rotate((index * 3) + 3).first(2)
  backlog.each_with_index do |game, offset|
    UserGameBacklog.find_or_create_by!(user: user, game: game, platform: game.platforms.first)
      .update!(sort_order: offset + 1)
  end

  favorite = game_list.rotate(index * 5).first
  UserGameFavorite.find_or_create_by!(user: user, game: favorite).update!(sort_order: 1)

  finished = game_list.rotate((index * 3) + 5).first
  UserGameCompletion.find_or_create_by!(
    user: user, game: finished, platform: finished.platforms.first, completion_type: "Main Story"
  ).update!(final_playtime_hrs: 20 + index, completed_at: (index + 1).months.ago)
end

load Rails.root.join("db/seeds/development/voting.rb")

puts "Seeded #{RpgClubUser.count} users, #{GamedbGame.count} games, and #{GamedbPlatform.count} platforms"
