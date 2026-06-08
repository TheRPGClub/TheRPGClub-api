# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Alba is the single JSON serialization layer for the API.
#
# Responses use a custom envelope ({ data } / { data: [...], meta }) — not
# JSON:API — and the frontend consumes snake_case keys verbatim. So Alba
# renders:
#   - without a root key (the default; we never set Alba.root_key)
#   - without key inflection, preserving the snake_case keys we declare
#
# Read more: https://github.com/okuramasafumi/alba
Alba.backend = :oj
Alba.inflector = nil
