# frozen_string_literal: true

# Renders a model validation refusal as 422 `{ error: <code>, message: }`
# when the record's errors carry one of the given detail codes (the
# `finished_in_future` / `started_after_finished` / `added_in_future` date
# checks, spec api#451). Any other invalid record re-raises to the usual
# RecordInvalid handler.
module CodedRefusals
  extend ActiveSupport::Concern

  private

  def render_coded_refusal(error, codes)
    record = error.record
    match = record.errors.details.flat_map do |attribute, details|
      details.map { |detail| [ attribute, detail[:error] ] }
    end.find { |(_, code)| codes.include?(code) }
    raise error unless match

    attribute, code = match
    render json: { error: code.to_s, message: record.errors.full_messages_for(attribute).first },
      status: :unprocessable_content
  end
end
