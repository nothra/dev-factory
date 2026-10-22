#!/usr/bin/env bash
# pre-commit.sh – Quality Gate vor jedem Commit
#
# Wird ausgeführt: git commit (über .git/hooks/pre-commit)
# Blockiert den Commit wenn ein Check fehlschlägt.
#
# Lint-Befehl: factory.config.yml → commands.lint (Env FACTORY_LINT_COMMAND hat Vorrang).
# Projekteigene Checks: ausführbare Skripte in scripts/project/checks/pre-commit.d/.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=../lib/gate-config.sh
source "$FACTORY_DIR/scripts/lib/gate-config.sh"

echo ""
echo -e "${YELLOW}Pre-Commit Checks...${NC}"

FAILED=0

# ─── Check 1: Keine ungelösten Merge-Konflikte ───────────────────────────────
if git diff --cached | grep -qE "^[+](<<<<<<<|=======|>>>>>>>)"; then
  echo -e "  ${RED}✗${NC} Ungelöste Merge-Konflikte gefunden"
  FAILED=1
else
  echo -e "  ${GREEN}✓${NC} Keine Merge-Konflikte"
fi

# ─── Check 2: Keine Debug-Statements ─────────────────────────────────────────
if git diff --cached | grep -qE "^\+.*(console\.log|System\.out\.print|debugger;|binding\.pry|pdb\.set_trace)"; then
  echo -e "  ${RED}✗${NC} Debug-Statements gefunden (console.log / System.out.print / debugger)"
  echo -e "     Bitte vor dem Commit entfernen"
  FAILED=1
else
  echo -e "  ${GREEN}✓${NC} Keine Debug-Statements"
fi

# ─── Check 3: Keine TODO ohne Ticket-Referenz ────────────────────────────────
if git diff --cached | awk '/^\+.*TODO/ && !/#[0-9]/ {f=1} END{exit !f}'; then
  echo -e "  ${YELLOW}⚠${NC}  TODO ohne Ticket-Referenz gefunden"
  echo -e "     Format: // TODO #123 oder // TODO(username): mit Ticket"
  # Nur Warnung, kein Block
fi

# ─── Check 4: Keine Secrets/Keys hardkodiert ─────────────────────────────────
if git diff --cached | grep -qiE "^\+.*(password|secret|api_key|apikey|private_key)[[:space:]]*=[[:space:]]*['\"][^'\"]{8,}['\"]"; then
  echo -e "  ${RED}✗${NC} Mögliche hardkodierte Credentials gefunden"
  echo -e "     Bitte prüfen und ggf. durch Environment-Variablen ersetzen"
  FAILED=1
else
  echo -e "  ${GREEN}✓${NC} Keine offensichtlichen Credentials"
fi

# ─── Check 5: Linting ────────────────────────────────────────────────────────
# Kommando aus factory.config.yml (commands.lint) bzw. FACTORY_LINT_COMMAND – kein
# stiller Default: fehlt beides, blockiert das Gate und nennt den Schlüssel.
if LINT_COMMAND="$(gate_command lint required)"; then
  echo -e "  ${YELLOW}→${NC} Lint: $LINT_COMMAND"
  if eval "$LINT_COMMAND" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Lint bestanden"
  else
    echo -e "  ${RED}✗${NC} Lint fehlgeschlagen – commit blockiert"
    echo -e "     Ausführen für Details: $LINT_COMMAND"
    FAILED=1
  fi
else
  echo -e "  ${RED}✗${NC} Lint: Kommando nicht konfiguriert – commit blockiert (commands.lint)"
  FAILED=1
fi

# ─── Check 6: Projekt-Erweiterungspunkt ──────────────────────────────────────
# Ausführbare Skripte aus scripts/project/checks/pre-commit.d/ (lexikalisch). Fehlendes
# oder leeres Verzeichnis ist kein Fehler; Fehlschlag oder fehlendes Ausführbar-Bit blockiert.
run_project_checks "$FACTORY_DIR/scripts/project/checks/pre-commit.d" || FAILED=1

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 1 ]; then
  echo -e "${RED}Pre-Commit fehlgeschlagen. Commit blockiert.${NC}"
  exit 1
else
  echo -e "${GREEN}Pre-Commit bestanden.${NC}"
  exit 0
fi
