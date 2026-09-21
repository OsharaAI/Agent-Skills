#!/usr/bin/env bash
# Stop hook: never leave a stale QA report behind.
#
# If the suite ran more recently than the report was rendered, re-render it. The
# report is then always the same shape, always current, and nobody has to
# remember the command.
set -uo pipefail

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$project_dir" || exit 0

results=".artifacts/results.json"
report="reports/QA-REPORT.md"

[[ -f "$results" ]] || exit 0
[[ -f "testcases/catalog.json" ]] || exit 0

# Regenerate only when the run is strictly newer than the report. Comparing the
# other way round never no-ops, because a report written in the same second as
# results.json is not "newer than" it.
[[ -f "$report" ]] && ! [[ "$results" -nt "$report" ]] && exit 0

if out=$(node scripts/qa-report.mjs 2>&1); then
  verdict=$(printf '%s' "$out" | head -1)
  jq -n --arg msg "QA report refreshed — $verdict" \
    '{hookSpecificOutput: {hookEventName: "Stop", systemMessage: $msg}}'
fi
exit 0
