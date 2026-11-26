#!/usr/bin/env bash
# The versioning job (spec api#510, ticket api#515), run by
# .github/workflows/versioning-reusable.yml after a push to main.
#
# For the pushed merge commit it finds the merged pull request, plans the next
# version with versioning.rb, tags it with a GitHub Release, and reports it to
# Pending Change intake. It does nothing while the repo has no vX.Y.Z tag, for
# a push that is not a merged pull request, and for a title that makes no
# version. A re-run of the same commit reports the version it already got
# (intake is idempotent per repo and pull request).
#
# Environment:
#   REPO               owner/name of the repo that was pushed
#   SHA                the pushed commit
#   COMMIT_MESSAGE     its message (fallback to find the pull request)
#   REPO_KEY           api, bot or www
#   API_BASE_URL       e.g. https://therpgclub-api.fly.dev
#   RELEASE_API_TOKEN  the release token (RPGCLUB_RELEASE_API_TOKEN)
#   DRY_RUN            "true" prints the release and intake instead of doing them
#   GH_TOKEN           for gh (contents: write, pull-requests: read)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?}" "${SHA:?}" "${REPO_KEY:?}" "${API_BASE_URL:?}"
dry_run="${DRY_RUN:-false}"
max_attempts=5

note() { echo "versioning: $*"; }

# Step outputs (action, version, tag) when run in GitHub Actions.
output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1" >>"$GITHUB_OUTPUT"; fi
}
output "action=none"

tags_json() {
  gh api --paginate "repos/$REPO/git/matching-refs/tags/v" \
    --jq '.[] | {name: (.ref | sub("^refs/tags/"; "")), sha: .object.sha}' | jq -s .
}

merged_pr() {
  local pr number
  pr="$(gh api "repos/$REPO/commits/$SHA/pulls" \
    --jq "[.[] | select(.merged_at != null and .merge_commit_sha == \"$SHA\")][0] // empty")"
  if [[ -z "$pr" ]]; then
    number="$(printf '%s' "${COMMIT_MESSAGE:-}" | ruby "$here/versioning.rb" pr-number)"
    if [[ -n "$number" ]]; then
      pr="$(gh api "repos/$REPO/pulls/$number" --jq "select(.merged_at != null and .merge_commit_sha == \"$SHA\")")"
    fi
  fi
  printf '%s' "$pr"
}

report() {
  local plan="$1" pr="$2" payload
  payload="$(jq -n --arg repo "$REPO_KEY" --argjson plan "$plan" --argjson pr "$pr" '{data: {
    repo: $repo, pr_number: $pr.number, type: $plan.type, title: $pr.title,
    version: $plan.version, patch_note: $plan.patch_note }}')"
  if [[ "$dry_run" == "true" ]]; then
    note "dry run: would POST $API_BASE_URL/api/v1/pending_changes $payload"
    return
  fi
  : "${RELEASE_API_TOKEN:?the release_api_token secret is not set}"
  curl --silent --show-error --fail-with-body --retry 4 --retry-connrefused --retry-delay 5 --max-time 60 \
    -X POST "$API_BASE_URL/api/v1/pending_changes" \
    -H "Authorization: Bearer $RELEASE_API_TOKEN" -H "Content-Type: application/json" \
    --data "$payload"
  echo
  note "reported $REPO_KEY $(jq -r .tag <<<"$plan") for pull request #$(jq -r .number <<<"$pr")"
}

# Creates the tag on SHA; fails when another job took that tag first.
tag_commit() {
  local tag="$1"
  if [[ "$dry_run" == "true" ]]; then
    note "dry run: would tag $tag on $SHA"
    return
  fi
  gh api --silent "repos/$REPO/git/refs" -f "ref=refs/tags/$tag" -f "sha=$SHA" || return 1
  note "tagged $tag on $SHA"
}

# Creates the tag's GitHub Release unless it exists (a re-run).
ensure_release() {
  local plan="$1" pr="$2" tag number title url
  tag="$(jq -r .tag <<<"$plan")"
  if [[ "$dry_run" == "true" ]]; then
    note "dry run: would create the GitHub Release $tag"
    return
  fi
  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    note "the GitHub Release $tag exists"
    return
  fi
  number="$(jq -r .number <<<"$pr")"
  title="$(jq -r .title <<<"$pr")"
  url="$(jq -r .html_url <<<"$pr")"
  gh release create "$tag" --repo "$REPO" --verify-tag --title "$tag" \
    --notes "$(printf '%s ([#%s](%s))\n\n%s' "$title" "$number" "$url" "$(jq -r .reason <<<"$plan")")"
}

tags="$(tags_json)"
if [[ "$(jq 'map(select(.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))) | length' <<<"$tags")" == "0" ]]; then
  note "no v* tag yet, so versioning has not started; nothing to do"
  exit 0
fi

pr="$(merged_pr)"
if [[ -z "$pr" ]]; then
  note "$SHA is not the merge commit of a merged pull request; nothing to do"
  exit 0
fi

for attempt in $(seq 1 "$max_attempts"); do
  plan="$(jq -n --argjson tags "$tags" --arg sha "$SHA" --argjson pr "$pr" \
    '{tags: $tags, sha: $sha, title: $pr.title, body: ($pr.body // "")}' | ruby "$here/versioning.rb" plan)"
  action="$(jq -r .action <<<"$plan")"
  output "action=$action"
  output "version=$(jq -r '.version // ""' <<<"$plan")"
  output "tag=$(jq -r '.tag // ""' <<<"$plan")"
  note "pull request #$(jq -r .number <<<"$pr"): $action ($(jq -r .reason <<<"$plan"))"
  case "$action" in
    none) exit 0 ;;
    report)
      ensure_release "$plan" "$pr"
      report "$plan" "$pr"
      exit 0
      ;;
    release)
      # Another merge's job may take the same tag first; then plan again from
      # the new tags.
      if tag_commit "$(jq -r .tag <<<"$plan")"; then
        ensure_release "$plan" "$pr"
        report "$plan" "$pr"
        exit 0
      fi
      note "could not create $(jq -r .tag <<<"$plan") (attempt $attempt of $max_attempts); planning again"
      sleep $((attempt * 3))
      tags="$(tags_json)"
      ;;
  esac
done
echo "::error::versioning: gave up creating a version tag after $max_attempts attempts"
exit 1
