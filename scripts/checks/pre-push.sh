#!/usr/bin/env bash
# pre-push.sh – Quality Gate vor jedem Push
#
# Wird ausgeführt: git push (über .git/hooks/pre-push)
# Blockiert den Push wenn Tests fehlschlagen.
#
# WICHTIG: Test-Befehl nach /setup-project mit echtem Befehl ersetzen.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}Pre-Push Checks...${NC}"

FAILED=0

# ─── Check 1: Test-Suite ausführen ───────────────────────────────────────────
# TODO nach /setup-project: Placeholder durch echten Befehl ersetzen
# Beispiele:
#   Java/Maven:     mvn test -q
#   Java/Gradle:    ./gradlew test -q
#   TypeScript:     npx vitest run
#   Go:             go test ./...
#   Python:         pytest -q

TEST_COMMAND="${FACTORY_TEST_COMMAND:-}"
if [ -n "$TEST_COMMAND" ]; then
  echo -e "  ${YELLOW}→${NC} Tests: $TEST_COMMAND"
  if eval "$TEST_COMMAND"; then
    echo -e "  ${GREEN}✓${NC} Alle Tests grün"
  else
    echo -e "  ${RED}✗${NC} Tests fehlgeschlagen – push blockiert"
    echo ""
    echo -e "  Ausführen für Details: $TEST_COMMAND"
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Tests: Noch nicht konfiguriert (nach /setup-project eintragen)"
  echo -e "     Setze FACTORY_TEST_COMMAND in scripts/checks/pre-push.sh"
  echo -e "  ${YELLOW}⚠${NC}  Push wird zugelassen (Konfiguration fehlt)"
fi

# ─── Check 2: Nicht auf main/master pushen ohne PR ───────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo -e "  ${RED}✗${NC} Direkter Push auf $CURRENT_BRANCH nicht erlaubt"
  echo -e "     Bitte einen Pull Request erstellen (gh pr create)"
  FAILED=1
else
  echo -e "  ${GREEN}✓${NC} Branch: $CURRENT_BRANCH (nicht main/master)"
fi

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 1 ]; then
  echo -e "${RED}Pre-Push fehlgeschlagen. Push blockiert.${NC}"
  exit 1
else
  echo -e "${GREEN}Pre-Push bestanden.${NC}"
  exit 0
fi
