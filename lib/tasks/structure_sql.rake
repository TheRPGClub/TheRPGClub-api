# db/structure.sql is dumped from the Neon database, whose `public` schema is
# owned by a non-default role, so `pg_dump` emits `CREATE SCHEMA public;`. That
# bare CREATE fails to load into a freshly-created database (which already has a
# `public` schema) under psql's ON_ERROR_STOP — which breaks `db:test:prepare`
# both in CI and locally.
#
# `db:schema:dump` runs after every `db:migrate`, so guard the line each time the
# structure dump is regenerated, keeping the committed file loadable regardless
# of which database it was dumped from.
if Rake::Task.task_defined?("db:schema:dump")
  Rake::Task["db:schema:dump"].enhance do
    path = Rails.root.join("db/structure.sql")
    if File.exist?(path)
      original = File.read(path)
      guarded = original.sub(/^CREATE SCHEMA public;$/, "CREATE SCHEMA IF NOT EXISTS public;")
      File.write(path, guarded) unless guarded == original
    end
  end
end
