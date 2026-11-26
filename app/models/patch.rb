# frozen_string_literal: true

# A Patch (GLOSSARY.md "Patch"; spec api#510, ticket api#511): one numbered,
# dated post of Patch Notes. Admins and Superadmins write it as a draft that
# nobody else sees, then publish it to the website.
#
# `number` comes from the database's own sequence on insert, so Patches are
# numbered in order and a number is never handed out again, even once its
# Patch is unpublished or deleted.
#
# The website keeps three texts in step: `rich_body` (the Plate value it
# edits), `body` (the full text as Discord markdown) and `cut_body` (that
# markdown cut to Discord's limit, which the bot posts). The API stores them
# as given.
class Patch < ApplicationRecord
  DRAFT = "draft"
  PUBLISHED = "published"
  STATUSES = [ DRAFT, PUBLISHED ].freeze
  TITLE_MAX = 100

  validates :status, inclusion: { in: STATUSES }
  validates :title, length: { maximum: TITLE_MAX }

  normalizes :title, with: ->(value) { value.strip.presence }

  scope :published, -> { where(status: PUBLISHED) }

  def draft? = status == DRAFT
  def published? = status == PUBLISHED

  def publish!
    update!(status: PUBLISHED, published_at: Time.current)
  end

  def unpublish!
    update!(status: DRAFT, published_at: nil)
  end

  # The published Patches just before and after this one, by number.
  def previous_number = Patch.published.where(number: ...number).maximum(:number)
  def next_number = Patch.published.where("number > ?", number).minimum(:number)

  # How many changes it lists as New, Improved and Fixed (PatchNotes.counts).
  def counts = PatchNotes.counts(rich_body)
end
