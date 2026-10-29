# frozen_string_literal: true

# The review shape of the Completionator import workflow (#291), built from
# an Imports::CompletionatorWorkflow::Review: the item, what the member
# should do next (`next_step`), the matched game or the GameDB candidates,
# the existing completion with its diff, and the add-form defaults.
# Documented as the CompletionatorReview OpenAPI component.
class CompletionatorReviewPayload
  def initialize(review)
    @review = review
  end

  def as_json(*)
    review = @review
    {
      item: review.item && CompletionatorImportItemResource.new(review.item).serializable_hash,
      next_step: review.next_step,
      game: review.game && GameSummaryResource.new(review.game).serializable_hash,
      candidates: review.candidates.map { |candidate| { game_id: candidate.game_id, title: candidate.title } },
      existing_completion: review.existing_completion && CompletionEntryResource.new(review.existing_completion).serializable_hash,
      diff: review.diff,
      form: form
    }
  end

  private

  def form
    form = @review.form
    return unless form

    form.merge(platforms: PlatformResource.new(form[:platforms]).serializable_hash)
  end
end
