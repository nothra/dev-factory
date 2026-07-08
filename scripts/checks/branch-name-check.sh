#!/usr/bin/env bash
# branch-name-check.sh – Prüft Branch-Namen gegen Konvention
#
# Wird durch check.sh PreToolUse-Hook aufgerufen wenn Claude
# einen neuen Branch anlegt – via git checkout -b/-B oder git switch -c/-C.
#
# Erlaubte Präfixe laut git-workflow.md:
#   feature/, fix/, improvement/, hotfix/, chore/, docs/, test/, refactor/
#
# Claude-interne Branches (claude/) werden ebenfalls toleriert.

TOOL_INPUT="${1:-}"
RED='\033[0;31m'
NC='\033[0m'

# Branch-erzeugende Flags: checkout -b/-B, switch -c/-C
BRANCH_NAME=$(echo "$TOOL_INPUT" \
  | grep -oE '(checkout -[bB]|switch -[cC]) +[^ ",}]+' \
  | sed -E 's/^(checkout -[bB]|switch -[cC]) +//')

if [[ -z "$BRANCH_NAME" ]]; then
  exit 0
fi

VALID_PREFIXES="^(feature|fix|improvement|hotfix|chore|docs|test|refactor|claude)/"

if ! echo "$BRANCH_NAME" | grep -qE "$VALID_PREFIXES"; then
  echo ""
  echo -e "${RED}✗ Branch-Name entspricht nicht der Konvention:${NC} ${BRANCH_NAME}"
  echo -e "  Erlaubte Präfixe: feature/, fix/, improvement/, hotfix/, chore/, docs/, test/, refactor/"
  echo -e "  Beispiel:         feature/42-user-login-implementieren"
  exit 1
fi

exit 0
