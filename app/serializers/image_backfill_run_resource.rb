# frozen_string_literal: true

# An image backfill run's progress (see ImageBackfillRun), every column.
class ImageBackfillRunResource
  include BaseResource
  columns_of ImageBackfillRun
end
