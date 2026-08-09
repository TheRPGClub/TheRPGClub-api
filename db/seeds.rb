# Keep production seeds limited to universally required reference data. The
# sample records used for local API development must never enter production.
if Rails.env.development?
  load Rails.root.join("db/seeds/development.rb")
else
  puts "No seed data defined for #{Rails.env}"
end
