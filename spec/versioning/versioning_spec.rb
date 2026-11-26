# frozen_string_literal: true

require "stringio"
require_relative "../../script/versioning/versioning"

# The versioning rules (spec api#510, ticket api#515): the PR title parser the
# title check uses, and the pure bump function the shared versioning workflow
# runs on every merge to main. No Rails needed.
RSpec.describe Versioning do
  describe ".parse_title" do
    it "reads type, scope, the breaking marker and the description" do
      title = described_class.parse_title("feat(www)!: drop the old news page")

      expect(title.to_h).to eq(type: "feat", scope: "www", breaking: true, description: "drop the old news page")
    end

    it "takes every allowed type, with or without a scope" do
      described_class::TYPES.each do |type|
        expect(described_class.parse_title("#{type}: do a thing")&.type).to eq(type)
        expect(described_class.parse_title("#{type}(api): do a thing")&.scope).to eq("api")
      end
    end

    it "allows slashes, dots and dashes in a scope" do
      expect(described_class.parse_title("fix(patch-notes/editor.v2): keep the cut").scope).to eq("patch-notes/editor.v2")
    end

    it "ignores surrounding whitespace" do
      expect(described_class.parse_title("  fix: trim me \n").description).to eq("trim me")
    end

    [
      [ "no type", "add the patch notes page" ],
      [ "an unknown type", "feature: add the patch notes page" ],
      [ "an upper-case type", "Feat: add the patch notes page" ],
      [ "no space after the colon", "feat:add the patch notes page" ],
      [ "no description", "feat: " ],
      [ "a blank description", "feat:    " ],
      [ "an empty scope", "feat(): add it" ],
      [ "a scope with a space", "feat(patch notes): add it" ],
      [ "a nested scope", "feat((api)): add it" ],
      [ "the marker before the scope", "feat!(api): add it" ],
      [ "a space before the colon", "feat (api): add it" ],
      [ "an empty title", "" ],
      [ "nil", nil ]
    ].each do |label, title|
      it "refuses #{label}" do
        expect(described_class.parse_title(title)).to be_nil
      end
    end
  end

  describe ".title_error" do
    it "is nil for a good title" do
      expect(described_class.title_error("chore(api): tidy")).to be_nil
    end

    it "explains the rule for a bad one" do
      expect(described_class.title_error("Add things")).to include("feat, fix, perf, refactor, chore, docs, test, ci")
    end
  end

  describe ".latest_tag" do
    it "picks the highest version by number, not by name" do
      expect(described_class.latest_tag(%w[v1.9.0 v1.10.0 v1.2.3])).to eq("v1.10.0")
    end

    it "skips tags that are not plain vX.Y.Z" do
      expect(described_class.latest_tag(%w[v2.0.0-rc.1 vnext v1.0 release-3.0.0 v1.4.2])).to eq("v1.4.2")
    end

    it "is nil without a version tag" do
      expect(described_class.latest_tag([])).to be_nil
      expect(described_class.latest_tag(%w[vnext 1.0.0])).to be_nil
    end
  end

  describe ".next_version" do
    def bump(title, tag: "v1.4.2", body: "")
      described_class.next_version(latest_tag: tag, title: title, body: body)
    end

    it "bumps the minor for feat" do
      expect(bump("feat: add Patch Notes")).to eq("1.5.0")
    end

    it "bumps the patch for fix and perf" do
      expect(bump("fix: keep the cut")).to eq("1.4.3")
      expect(bump("perf: cache the list")).to eq("1.4.3")
    end

    it "does not bump refactor, chore, docs, test or ci" do
      %w[refactor chore docs test ci].each do |type|
        expect(bump("#{type}: tidy")).to be_nil
      end
    end

    it "is the same with a scope" do
      expect(bump("feat(bot): add /patch-notes")).to eq("1.5.0")
      expect(bump("fix(www): keep the cut")).to eq("1.4.3")
      expect(bump("docs(api): explain")).to be_nil
    end

    it "bumps the major for ! whatever the type" do
      expect(bump("feat!: new sign-in")).to eq("2.0.0")
      expect(bump("fix(api)!: rename a field")).to eq("2.0.0")
      expect(bump("refactor!: move routes")).to eq("2.0.0")
      expect(bump("chore(api)!: drop Ruby 3.3")).to eq("2.0.0")
    end

    it "bumps the major for a BREAKING CHANGE line in the body" do
      expect(bump("feat: new sign-in", body: "Summary\n\nBREAKING CHANGE: sessions reset")).to eq("2.0.0")
      expect(bump("refactor: move routes", body: "BREAKING-CHANGE: old routes are gone")).to eq("2.0.0")
      expect(bump("fix: x", body: "Intro\r\n  BREAKING CHANGE: windows line ends\r\n")).to eq("2.0.0")
    end

    it "ignores BREAKING CHANGE that is not a line of its own" do
      expect(bump("feat: add it", body: "This is not a BREAKING CHANGE: promise")).to eq("1.5.0")
      expect(bump("feat: add it", body: "BREAKING CHANGES are announced elsewhere")).to eq("1.5.0")
      expect(bump("feat: add it", body: "breaking change: lower case is prose")).to eq("1.5.0")
    end

    it "ignores a BREAKING CHANGE line inside a template comment" do
      expect(bump("feat: add it", body: "<!--\nBREAKING CHANGE: example\n-->")).to eq("1.5.0")
    end

    it "does nothing without a tag" do
      expect(bump("feat: add Patch Notes", tag: nil)).to be_nil
      expect(bump("feat!: add Patch Notes", tag: nil)).to be_nil
    end

    it "does nothing with a tag that is not vX.Y.Z" do
      expect(bump("feat: add it", tag: "vnext")).to be_nil
    end

    it "does nothing for a malformed title" do
      expect(bump("Add Patch Notes")).to be_nil
      expect(bump("feat:add it", body: "BREAKING CHANGE: still malformed")).to be_nil
      expect(bump(nil)).to be_nil
    end

    it "tolerates a nil body" do
      expect(bump("fix: keep the cut", body: nil)).to eq("1.4.3")
    end

    it "starts from 0.x like any other version" do
      expect(bump("feat: first", tag: "v0.0.0")).to eq("0.1.0")
      expect(bump("feat!: first", tag: "v0.3.9")).to eq("1.0.0")
    end
  end

  describe ".patch_note" do
    it "reads the Patch note line" do
      expect(described_class.patch_note("Summary\n\nPatch note: Patch Notes now show the versions.\n")).to eq("Patch Notes now show the versions.")
    end

    it "is case-insensitive about the label and trims" do
      expect(described_class.patch_note("  patch NOTE:   Faster lists  \r\n")).to eq("Faster lists")
    end

    it "takes the first filled line" do
      expect(described_class.patch_note("Patch note:\nPatch note: second\nPatch note: third")).to eq("second")
    end

    it "reads the first non-empty line after an empty Patch note line" do
      expect(described_class.patch_note("Patch note:\n\nFaster lists.\n\n## Testing")).to eq("Faster lists.")
      expect(described_class.patch_note("Patch note:\r\n<!-- hint -->\r\n  Faster lists.  \r\n")).to eq("Faster lists.")
    end

    it "is nil when the template's Patch note line is left empty, with the inline placeholder or not" do
      template = "## Summary\n\n- x\n\nPatch note: <!-- one sentence, or leave empty -->\n\n<!--\nhint\n-->\n\n## Testing\n\n- y\n"
      expect(described_class.patch_note(template)).to be_nil
      expect(described_class.patch_note("Patch note:\n\n<!-- hint -->\n\n## Testing\n\n- y")).to be_nil
    end

    it "is nil when the line is left empty, missing or only in a comment" do
      expect(described_class.patch_note("Patch note:   \n")).to be_nil
      expect(described_class.patch_note("Summary only")).to be_nil
      expect(described_class.patch_note("<!-- Patch note: an example -->")).to be_nil
      expect(described_class.patch_note(nil)).to be_nil
    end

    it "keeps within the intake limit" do
      note = described_class.patch_note("Patch note: #{'a' * 600}")

      expect(note.length).to eq(described_class::PATCH_NOTE_MAX)
      expect(note).to end_with("...")
    end
  end

  describe ".pr_number_from_message" do
    it "reads a GitHub merge commit message" do
      expect(described_class.pr_number_from_message("Merge pull request #517 from TheRPGClub/feat/x\n\nfeat: y")).to eq(517)
    end

    it "is nil for anything else" do
      expect(described_class.pr_number_from_message("feat: squash merged (#517)")).to be_nil
      expect(described_class.pr_number_from_message(nil)).to be_nil
    end
  end

  describe ".plan" do
    let(:tags) { [ { "name" => "v1.4.2", "sha" => "aaa" }, { "name" => "v1.4.1", "sha" => "bbb" } ] }

    it "plans a new version and release" do
      plan = described_class.plan(tags: tags, sha: "ccc", title: "feat(api): add it", body: "Patch note: New thing")

      expect(plan).to eq(
        "action" => "release", "version" => "1.5.0", "tag" => "v1.5.0", "type" => "feat",
        "patch_note" => "New thing", "reason" => "feat bumps the minor version"
      )
    end

    it "reports the existing version when this commit is already tagged (a re-run)" do
      plan = described_class.plan(tags: tags, sha: "aaa", title: "fix: x", body: "")

      expect(plan).to include("action" => "report", "version" => "1.4.2", "tag" => "v1.4.2", "type" => "fix")
    end

    it "does nothing without a version tag" do
      plan = described_class.plan(tags: [], sha: "ccc", title: "feat: x", body: "")

      expect(plan).to include("action" => "none", "reason" => "no v* tag yet, so versioning has not started")
    end

    it "does nothing for a type that does not bump" do
      expect(described_class.plan(tags: tags, sha: "ccc", title: "docs: x", body: "")).to include("action" => "none")
    end

    it "does nothing for a malformed title" do
      plan = described_class.plan(tags: tags, sha: "ccc", title: "Add x", body: "")

      expect(plan).to include("action" => "none", "reason" => a_string_including("not a typed title"))
    end
  end
  describe ".main" do
    def run(argv, input = "")
      out = StringIO.new
      err = StringIO.new
      status = described_class.main(argv, stdin: StringIO.new(input), stdout: out, stderr: err)
      [ status, out.string, err.string ]
    end

    it "passes a good title" do
      expect(run([ "check-title", "feat(www): add it" ])).to eq([ 0, "", "" ])
    end

    it "fails a bad title with the rule" do
      status, _out, err = run([ "check-title", "Add it" ])

      expect(status).to eq(1)
      expect(err).to include("\"Add it\"", "type(scope)!: description")
    end

    it "prints the plan as JSON" do
      input = JSON.generate(tags: [ { name: "v1.0.0", sha: "a" } ], sha: "b", title: "fix: x", body: nil)
      status, out, _err = run([ "plan" ], input)

      expect(status).to eq(0)
      expect(JSON.parse(out)).to include("action" => "release", "version" => "1.0.1")
    end

    it "prints the pull request number of a merge commit message" do
      expect(run([ "pr-number" ], "Merge pull request #12 from a/b")).to eq([ 0, "12", "" ])
      expect(run([ "pr-number" ], "fix: x")).to eq([ 0, "", "" ])
    end

    it "explains its usage otherwise" do
      expect(run([]).first).to eq(2)
    end
  end
end
