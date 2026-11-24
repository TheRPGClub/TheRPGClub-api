# frozen_string_literal: true

# Renders a model validation refusal as 422 `{ error: <code>, message: }`
# when every error on the record is one of the given detail codes (the
# `finished_in_future` / `started_after_finished` / `started_in_future` /
# `added_in_future` date checks, spec api#451). A record with any other error
# re-raises to the usual RecordInvalid handler, which lists them all, so a
# coded refusal never hides another problem.
module CodedRefusals
  extend ActiveSupport::Concern

  private

  def render_coded_refusal(error, codes)
    record = error.record
    found = record.errors.details.flat_map do |attribute, details|
      details.map { |detail| [ attribute, detail[:error] ] }
    end
    raise error unless found.any? && found.all? { |(_, code)| codes.include?(code) }

    attribute, code = found.first
    render json: { error: code.to_s, message: record.errors.full_messages_for(attribute).first },
      status: :unprocessable_content
  end
end
