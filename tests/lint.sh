#!/usr/bin/env bash
set -euo pipefail

# Static checks for arrive-aml (fast, no side effects):
#   1. every shell script parses (bash -n)
#   2. shellcheck errors (shellcheck, or uvx shellcheck-py when not installed)
#   3. nothing user-specific: no one's name, email, folder or VM in code or docs.
#      The team org name may appear only where the org-move checklist lists it.
#
#   bash tests/lint.sh

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FAIL=0
bad() { FAIL=1; printf '\033[0;31m✗ %s\033[0m\n' "$*"; }
good() { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }

mapfile -t FILES < <(git ls-files --cached --others --exclude-standard | while read -r f; do [ -f "$f" ] && echo "$f"; done)
mapfile -t SCRIPTS < <(printf '%s\n' "${FILES[@]}" | grep -E '\.sh$')

# 1. syntax
n=0
for f in "${SCRIPTS[@]}"; do
  bash -n "$f" || { bad "syntax: $f"; continue; }
  n=$((n + 1))
done
good "bash -n: $n scripts parse"

# 2. shellcheck (errors only; style is not enforced)
SC=()
if command -v shellcheck >/dev/null 2>&1; then
  SC=(shellcheck)
elif command -v uvx >/dev/null 2>&1; then
  SC=(uvx --quiet --from shellcheck-py shellcheck)
fi
if [ "${#SC[@]}" -gt 0 ]; then
  if "${SC[@]}" -S error -x "${SCRIPTS[@]}"; then
    good "shellcheck: no errors"
  else
    bad "shellcheck reported errors"
  fi
else
  printf '  (shellcheck not available - skipped)\n'
fi

# 3. user-specific values. Team org (until the move, see docs/ORG-MOVE.md) is
#    allowed only in these files; any other "rarko" is someone's identity.
ORG_OK='^(scripts/lib/common\.sh|scripts/get-started\.sh|README\.md|docs/GETTING-STARTED\.md|docs/ORG-MOVE\.md|docs/TESTING-NEW-USER\.md|pyproject\.toml|uv\.lock|tests/sandbox-new-user\.sh|tests/lint\.sh)$'
IDENTITY_OK='^(docs/archive/|docs/plans/|tests/sandbox-new-user\.sh$|tests/lint\.sh$)'
hits=0
while IFS= read -r line; do
  f="${line%%:*}"
  rest="${line#*:*:}"
  [[ "$f" =~ $IDENTITY_OK ]] && continue
  # temporary session-resume note in README.md (remove together with it)
  [[ "$line" == *TEMP-RESUME* ]] && continue
  # strip allowed org mentions, then look for anything left
  if [[ "$f" =~ $ORG_OK ]]; then
    rest="${rest//rarko-arrive/}"
  fi
  if grep -qiE 'rarko|rick arko' <<<"$rest"; then
    bad "user-specific value: $line"
    hits=$((hits + 1))
  fi
done < <(printf '%s\n' "${FILES[@]}" | xargs -d '\n' grep -nIiE 'rarko|rick arko' 2>/dev/null || true)
[ "$hits" -eq 0 ] && good "no user-specific names, emails, folders or VMs (team org only where allowed)"

exit "$FAIL"
