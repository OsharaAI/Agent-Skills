#!/usr/bin/env bash
# PostToolUse: run the tests affected by the file that just changed.
#
# Exit 2 hands stderr back to Claude as a blocking error, so a regression
# surfaces immediately in the same turn rather than whenever someone
# remembers to run the suite.
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

[[ -z "$file_path" ]] && exit 0
cd "$project_dir" || exit 0

# Load BASE_URL and friends; the target is an external API.
[[ -f .env ]] && set -a && . ./.env && set +a

# Decide what to run based on what changed.
case "$file_path" in
  *"/tests/"*.spec.ts)
    target="${file_path#"$project_dir"/}"
    label="$(basename "$target")"
    ;;
  */playwright.config.ts|*/CLAUDE.md)
    # Config or the rules themselves changed: fall back to the smoke set.
    target="--grep @smoke"
    label="smoke suite"
    ;;
  *)
    exit 0
    ;;
esac

if [[ -z "${BASE_URL:-}" ]]; then
  echo "Skipped $label: BASE_URL is not set. Copy .env.example to .env and fill it in." >&2
  exit 0
fi

# shellcheck disable=SC2086
output=$(npx playwright test $target --reporter=line 2>&1)
status=$?

if [[ $status -eq 0 ]]; then
  summary=$(printf '%s' "$output" | grep -E '[0-9]+ passed' | tail -1)
  jq -n --arg msg "Tests passed for ${label}: ${summary:-ok}" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", systemMessage: $msg}}'
  exit 0
fi

{
  echo "Tests failed after editing ${label}."
  echo
  printf '%s\n' "$output" | grep -vE '^\s*$' | tail -40
  echo
  echo "Per CLAUDE.md: classify this as a product defect, a test defect, or an"
  echo "environment issue before changing anything. Do not weaken the assertion"
  echo "to make it pass — delegate to the qa-failure-analyst subagent if the"
  echo "cause is not obvious."
} >&2

exit 2
