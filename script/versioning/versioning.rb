# frozen_string_literal: true

require "json"

# The club's versioning rules (spec api#510, ticket api#515; ADR 0016).
#
# Each repo (api, bot, www) versions itself on every merge to main. The
# version comes from the merged pull request's typed title:
#
#   type(scope)!: description
#
# with type one of TYPES, an optional scope and an optional "!". feat bumps
# the minor number, fix and perf the patch number, and "!" or a
# "BREAKING CHANGE:" line in the pull request body the major number (for any
# type). refactor, chore, docs, test and ci make no version. Versioning starts
# only once a repo has a vX.Y.Z tag; until then nothing happens.
#
# The shared workflows (.github/workflows/versioning-reusable.yml and
# pr-title-reusable.yml) run this file with plain Ruby, no gems:
#
#   ruby versioning.rb check-title "<title>"   # exit 1 with the rule when bad
#   ruby versioning.rb plan < input.json       # prints the plan as JSON
#   ruby versioning.rb pr-number < message     # the PR number of a merge commit
#
# where input.json is { "tags": [{ "name", "sha" }], "sha", "title", "body" }.
module Versioning
  TYPES = %w[feat fix perf refactor chore docs test ci].freeze
  MINOR_TYPES = %w[feat].freeze
  PATCH_TYPES = %w[fix perf].freeze
  # Pending Change intake refuses a longer Patch note line.
  PATCH_NOTE_MAX = 500

  TITLE_FORMAT = /\A(?<type>[a-z]+)(?:\((?<scope>[^()\s]+)\))?(?<bang>!)?: +(?<description>\S.*)\z/
  TAG_FORMAT = /\Av(\d+)\.(\d+)\.(\d+)\z/
  BREAKING_LINE = /^[ \t]*BREAKING[ -]CHANGE:/
  PATCH_NOTE_LINE = /^[ \t]*patch note:[ \t]*(\S.*?)[ \t]*\r?$/i
  MERGE_MESSAGE = /\AMerge pull request #(\d+) /
  COMMENT = /<!--.*?-->/m

  TITLE_RULE = "A pull request title must read `type(scope)!: description`: type is one of " \
               "#{TYPES.join(', ')}; the (scope) and the ! (a breaking change, which bumps the major " \
               "version) are optional; then a colon, a space and the description."

  Title = Struct.new(:type, :scope, :breaking, :description, keyword_init: true)

  module_function

  # The typed title, or nil when it doesn't follow the rule.
  def parse_title(title)
    match = TITLE_FORMAT.match(title.to_s.strip)
    return unless match && TYPES.include?(match[:type])

    Title.new(type: match[:type], scope: match[:scope], breaking: !match[:bang].nil?,
              description: match[:description].strip)
  end

  # nil for a good title, else the rule to show the author.
  def title_error(title)
    parse_title(title) ? nil : TITLE_RULE
  end

  # The highest vX.Y.Z tag by number, or nil when there is none.
  def latest_tag(tags)
    tags.select { |tag| TAG_FORMAT.match?(tag) }.max_by { |tag| TAG_FORMAT.match(tag).captures.map(&:to_i) }
  end

  # The version after latest_tag for a merged pull request, as "x.y.z", or nil
  # when there is no version tag yet, the title is malformed or its type makes
  # no version.
  def next_version(latest_tag:, title:, body:)
    part = bump_part(title, body)
    match = TAG_FORMAT.match(latest_tag.to_s)
    return unless part && match

    major, minor, patch = match.captures.map(&:to_i)
    case part
    when :major then "#{major + 1}.0.0"
    when :minor then "#{major}.#{minor + 1}.0"
    else "#{major}.#{minor}.#{patch + 1}"
    end
  end

  # :major, :minor, :patch or nil.
  def bump_part(title, body)
    parsed = parse_title(title)
    return unless parsed
    return :major if parsed.breaking || breaking_line?(body)
    return :minor if MINOR_TYPES.include?(parsed.type)

    :patch if PATCH_TYPES.include?(parsed.type)
  end

  def breaking_line?(body)
    BREAKING_LINE.match?(uncommented(body))
  end

  # The pull request's optional "Patch note:" line (the first filled one), or nil.
  def patch_note(body)
    note = uncommented(body).scan(PATCH_NOTE_LINE).flatten.first
    return unless note
    return note if note.length <= PATCH_NOTE_MAX

    "#{note[0, PATCH_NOTE_MAX - 3].rstrip}..."
  end

  # The pull request number in a GitHub merge commit message, or nil.
  def pr_number_from_message(message)
    match = MERGE_MESSAGE.match(message.to_s)
    match && match[1].to_i
  end

  # What the versioning job does for the merge commit sha, given the repo's
  # tags ({ "name", "sha" }) and the merged pull request's title and body:
  #
  #   "release" - tag "tag" on sha, create its GitHub Release, report "version"
  #   "report"  - sha already carries "tag" (a re-run): only report "version"
  #   "none"    - nothing to do, "reason" says why
  def plan(tags:, sha:, title:, body:)
    names = tags.map { |tag| tag["name"] }
    latest = latest_tag(names)
    return none("no v* tag yet, so versioning has not started") unless latest

    parsed = parse_title(title)
    return none("#{title.inspect} is not a typed title") unless parsed

    note = patch_note(body)
    existing = latest_tag(tags.select { |tag| tag["sha"] == sha }.map { |tag| tag["name"] })
    if existing
      return { "action" => "report", "version" => existing.delete_prefix("v"), "tag" => existing,
               "type" => parsed.type, "patch_note" => note, "reason" => "#{existing} already tags this commit" }
    end

    version = next_version(latest_tag: latest, title: title, body: body)
    return none("#{parsed.type} makes no version") unless version

    { "action" => "release", "version" => version, "tag" => "v#{version}", "type" => parsed.type,
      "patch_note" => note, "reason" => "#{reason(title, body)} version" }
  end

  def none(reason)
    { "action" => "none", "reason" => reason }
  end

  def reason(title, body)
    parsed = parse_title(title)
    part = bump_part(title, body)
    return "#{parsed.breaking ? '!' : 'a BREAKING CHANGE line'} bumps the major" if part == :major

    "#{parsed.type} bumps the #{part}"
  end

  def uncommented(body)
    body.to_s.gsub(COMMENT, "")
  end

  def main(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
    case argv.first
    when "check-title"
      error = title_error(argv[1])
      return 0 unless error

      stderr.puts("#{argv[1].inspect}: #{error}")
      1
    when "pr-number"
      number = pr_number_from_message(stdin.read)
      stdout.print(number) if number
      0
    when "plan"
      input = JSON.parse(stdin.read)
      stdout.puts(JSON.generate(plan(tags: input.fetch("tags"), sha: input.fetch("sha"),
                                     title: input["title"], body: input["body"])))
      0
    else
      stderr.puts("usage: versioning.rb check-title TITLE | plan < input.json | pr-number < message")
      2
    end
  end
end

exit(Versioning.main(ARGV)) if $PROGRAM_NAME == __FILE__
