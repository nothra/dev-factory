#!/usr/bin/env bash
# git-context-check.sh – Kontext-Snapshot vor invasiven Git-Operationen
#
# Wird durch check.sh PreToolUse-Hook aufgerufen wenn Claude eine
# invasive Git-Operation (commit, push, rebase, reset, merge) ausführt.
#
# Zeigt: Verzeichnis, Branch, Anzahl geänderter Dateien, letzter Commit.
# Blockiert: Commit/Push direkt auf main/master.

set -uo pipefail

TOOL_INPUT="${1:-}"
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if ! git rev-parse --git-dir &>/dev/null; then
  exit 0
fi

CURRENT_DIR=$(pwd)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unbekannt")
CHANGED_FILES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "noch kein Commit")

echo ""
echo -e "${CYAN}── Git-Kontext ──────────────────────────────────────${NC}"
echo -e "  Verzeichnis:    ${CURRENT_DIR}"
echo -e "  Branch:         ${CURRENT_BRANCH}"
echo -e "  Geändert:       ${CHANGED_FILES} Datei(en)"
echo -e "  Letzter Commit: ${LAST_COMMIT}"
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  if echo "$TOOL_INPUT" | grep -qE 'git (commit|push)'; then
    echo ""
    echo -e "  ${RED}✗ Direktes Commit/Push auf '${CURRENT_BRANCH}' ist nicht erlaubt.${NC}"
    echo -e "    Feature-Branch anlegen: bash scripts/start-work.sh <id> <beschreibung>"
    exit 1
  fi
  echo -e "  ${YELLOW}⚠  Achtung: Aktiver Branch ist '${CURRENT_BRANCH}'${NC}"
fi

exit 0
