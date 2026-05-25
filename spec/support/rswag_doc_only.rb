# frozen_string_literal: true

# Makes the rswag `response` DSL register a no-op rspec example automatically
# so `rswag:specs:swaggerize` emits the metadata for documentation-only specs
# (i.e. specs that do not call `run_test!`).
module RswagDocOnly
  def response(code, description, metadata = {}, &block)
    super(code, description, metadata) do
      module_eval(&block) if block
      it('documents the response') { }
    end
  end
end

Rswag::Specs::ExampleGroupHelpers.prepend(RswagDocOnly) if defined?(Rswag::Specs::ExampleGroupHelpers)
