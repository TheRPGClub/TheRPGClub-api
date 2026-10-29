# frozen_string_literal: true

# The `csv_text` upload checks shared by the collection CSV (#290) and
# Completionator (#291) import creates: a size cap, and the 422
# `{error: "invalid_csv", errors: [{row_index, column, message}]}` response.
#
#   text = checked_csv_text(data["csv_text"]) or return
#   render_invalid_csv([ csv_file_error("CSV file is empty.") ])
module ImportCsvUpload
  extend ActiveSupport::Concern

  # Upper bound on an uploaded `csv_text`, so one request can't parse an
  # arbitrarily large file.
  MAX_CSV_BYTES = 2.megabytes

  private

  # The text, or nil after rendering invalid_csv when it is over MAX_CSV_BYTES.
  def checked_csv_text(raw)
    text = raw.to_s
    return text if text.bytesize <= MAX_CSV_BYTES

    render_invalid_csv([ csv_file_error("CSV file is larger than #{MAX_CSV_BYTES / 1.megabyte} MB.") ])
  end

  # An error about the whole file: row 1, column "file".
  def csv_file_error(message)
    { row_index: 1, column: "file", message: message }
  end

  # Renders the 422 and returns nil.
  def render_invalid_csv(errors)
    render json: { error: "invalid_csv", errors: errors }, status: :unprocessable_content
    nil
  end
end
