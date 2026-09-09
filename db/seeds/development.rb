# frozen_string_literal: true

puts "Seeding development data..."

users = [
  {
    user_id: "100000000000000001",
    username: "dev_admin",
    global_name: "Dev Admin",
    role_admin: true,
    role_moderator: true,
    role_member: true,
    server_joined_at: 2.years.ago
  },
  {
    user_id: "100000000000000002",
    username: "party_member",
    global_name: "Party Member",
    role_regular: true,
    role_member: true,
    server_joined_at: 1.year.ago
  }
].to_h do |attributes|
  user = RpgClubUser.find_or_initialize_by(user_id: attributes.fetch(:user_id))
  user.update!(attributes)
  [ attributes.fetch(:username), user ]
end

platforms = [
  { platform_code: "PC", platform_name: "PC" },
  { platform_code: "PS5", platform_name: "PlayStation 5" },
  { platform_code: "SWITCH", platform_name: "Nintendo Switch" }
].to_h do |attributes|
  platform = GamedbPlatform.find_or_initialize_by(platform_code: attributes.fetch(:platform_code))
  platform.update!(attributes)
  [ attributes.fetch(:platform_code), platform ]
end

genres = [
  { igdb_genre_id: -10_001, name: "Role-playing (RPG)" },
  { igdb_genre_id: -10_002, name: "Adventure" },
  { igdb_genre_id: -10_003, name: "Strategy" }
].to_h do |attributes|
  genre = GamedbGenre.find_or_initialize_by(igdb_genre_id: attributes.fetch(:igdb_genre_id))
  genre.update!(attributes)
  [ attributes.fetch(:name), genre ]
end

studio = GamedbCompany.find_or_initialize_by(igdb_company_id: -20_001)
studio.update!(name: "Lantern Bear Studio")

games = [
  {
    igdb_id: -30_001,
    title: "Ashes of Asteria",
    slug: "ashes-of-asteria",
    description: "A party-based fantasy RPG used for local development.",
    total_rating: 88,
    initial_release_date: Date.new(2024, 3, 14),
    platforms: %w[PC PS5],
    genres: [ "Role-playing (RPG)", "Adventure" ]
  },
  {
    igdb_id: -30_002,
    title: "Moonlit Tactics",
    slug: "moonlit-tactics",
    description: "A compact tactical RPG used to exercise collection APIs.",
    total_rating: 82,
    initial_release_date: Date.new(2023, 10, 20),
    platforms: %w[PC SWITCH],
    genres: [ "Role-playing (RPG)", "Strategy" ]
  },
  {
    igdb_id: -30_003,
    title: "Clockwork Kingdom",
    slug: "clockwork-kingdom",
    description: "An adventure game available as seeded backlog data.",
    total_rating: 76,
    initial_release_date: Date.new(2025, 1, 9),
    platforms: %w[PS5 SWITCH],
    genres: [ "Adventure" ]
  }
].to_h do |attributes|
  platform_codes = attributes.delete(:platforms)
  genre_names = attributes.delete(:genres)
  game = GamedbGame.find_or_initialize_by(igdb_id: attributes.fetch(:igdb_id))
  game.update!(attributes)

  platform_codes.each do |code|
    GamedbGamePlatform.find_or_create_by!(game: game, platform: platforms.fetch(code))
  end
  genre_names.each do |name|
    GamedbGameGenre.find_or_create_by!(game: game, genre: genres.fetch(name))
  end
  GamedbGameCompany.find_or_create_by!(game: game, company: studio, role: "Developer")

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

gotm_entry = GotmEntry.find_or_initialize_by(round_number: 1, game_index: 1)
gotm_entry.update!(
  month_year: "March 2024",
  game: ashes
)
nr_gotm_entry = NrGotmEntry.find_or_initialize_by(round_number: 1, game_index: 1)
nr_gotm_entry.update!(
  month_year: "October 2023",
  game: moonlit
)

puts "Seeded #{RpgClubUser.count} users, #{GamedbGame.count} games, and #{GamedbPlatform.count} platforms"
