# frozen_string_literal: true

require "rails_helper"

# Guards the swagger.yaml ↔ config/routes.rb boundary: every path+verb the
# OpenAPI contract documents must resolve in the Rails router.
#
# The request specs here are rswag doc-only — they generate swagger.yaml but
# never exercise the routes — and CI's swaggerize drift-guard only keeps
# swagger.yaml in sync with the *specs*. Nothing checked that the documented
# paths exist, which is how #208 shipped: the bulk-sync was documented (and
# called by the bot) at PATCH /games/{id}/release_announcements while
# routes.rb spelled it .../release_announcements/sync, 404ing every bot sweep.
#
# The reverse direction (routes that exist but are undocumented) is
# deliberately not asserted — internal/auxiliary routes don't all belong in
# the public contract.
RSpec.describe "swagger.yaml route contract" do
  swagger = YAML.safe_load(
    File.read(Rails.root.join("swagger/v1/swagger.yaml")),
    aliases: true
  )

  # Placeholders like {id}/{user_id} become a concrete segment; "1" satisfies
  # any dynamic segment in this app's routes (no format constraints).
  concrete = ->(template) { template.gsub(/\{[^}]+\}/, "1") }

  swagger.fetch("paths").each do |template, operations|
    operations.each_key do |verb|
      next unless %w[get put post patch delete head].include?(verb)

      it "routes #{verb.upcase} #{template}" do
        expect {
          Rails.application.routes.recognize_path(concrete.call(template), method: verb.to_sym)
        }.not_to raise_error, "documented in swagger.yaml but not recognized by the router"
      end
    end
  end
end
