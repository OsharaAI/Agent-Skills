#!/usr/bin/env bash
# PostToolUse: a test case changed, so re-version it and re-derive the suite.
#
# This is what makes "store it, version it" mechanical rather than a habit:
# the moment a .cases.json is written, it is validated against the six scenario
# classes and the test-case-management lint, its version is stamped, the
# Playwright specs are regenerated from it, and the affected tag is run.
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

[[ "$file_path" != *"/testcases/"*".cases.json" ]] && exit 0
cd "$project_dir" || exit 0

# Validate + version. A case that breaks a rule never reaches the suite.
if ! commit_out=$(node scripts/testcases.mjs commit 2>&1); then
  {
    echo "The test case was not versioned — it does not satisfy the catalogue rules:"
    echo
    printf '%s\n' "$commit_out"
    echo
    echo "Fix the case file itself. Do not work around this by editing"
    echo "tests/generated/ — those specs are derived from the catalogue."
  } >&2
  exit 2
fi

scaffold_out=$(node scripts/testcases.mjs scaffold 2>&1) || true
version_line=$(printf '%s' "$commit_out" | grep -E '^v[0-9]+' | head -3 | tr '\n' ';')

# Load BASE_URL and friends; the target is an external API.
[[ -f .env ]] && set -a && . ./.env && set +a

tag=$(basename "$(dirname "$file_path")")
spec="tests/generated/${tag}.spec.ts"

if [[ -z "${BASE_URL:-}" || ! -f "$spec" ]]; then
  jq -n --arg msg "Catalogue stamped: ${version_line:-no change}. Suite regenerated." \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", systemMessage: $msg}}'
  exit 0
fi

output=$(npx playwright test "$spec" --reporter=line 2>&1)
status=$?

if [[ $status -eq 0 ]]; then
  summary=$(printf '%s' "$output" | grep -E '[0-9]+ passed' | tail -1)
  jq -n --arg msg "Catalogue stamped: ${version_line:-no change}. ${summary:-suite green}" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", systemMessage: $msg}}'
  exit 0
fi

{
  echo "Catalogue stamped (${version_line:-no change}), but ${tag} is failing:"
  echo
  printf '%s\n' "$output" | grep -vE '^\s*$' | tail -30
  echo
  echo "Per CLAUDE.md: classify this as a product defect, a test defect, or an"
  echo "environment issue before changing anything. If the API disagrees with the"
  echo "document, the failing test is correct — file the defect, do not weaken the"
  echo "case. Delegate to qa-failure-analyst if the cause is not obvious."
} >&2
exit 2
