#!/usr/bin/env bash
# PreToolUse guard. CLAUDE.md says generated specs are never hand-edited, because
# the next generation run overwrites them and the fix is silently lost. This
# enforces that rule instead of trusting everyone to remember it.
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

[[ -z "$file_path" ]] && exit 0

if [[ "$file_path" == *"/tests/generated/"* ]]; then
  tag="$(basename "$file_path" .spec.ts)"
  cat >&2 <<MSG
Blocked: $(basename "$file_path") lives in tests/generated/.

These specs are derived from the versioned test-case catalogue and are rewritten
on every scaffold, so an edit here is lost silently. The assertion you want to
change lives in the case file, which is the reviewed, versioned artifact:

  testcases/${tag}/*.cases.json
  npm run cases:commit     # validate + bump the version
  npm run cases:scaffold   # re-derive the spec

If this one spec genuinely needs to diverge from its case, promote it out of the
generated tree first and edit it there:

  git mv tests/generated/$(basename "$file_path") tests/api/
MSG
  exit 2
fi

exit 0
