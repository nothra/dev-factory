#!/usr/bin/env bash
# interrupt-check.sh – Prüft, ob ein Stage-3-Interrupt signalisiert wurde.
#
# Verwendung: bash scripts/checks/interrupt-check.sh <task-id>
#
# Exit 0: kein Interrupt – Pipeline darf weiterlaufen.
# Exit 1: Interrupt signalisiert – Pipeline muss hart stoppen.
# Exit 2: Aufruf-Fehler (keine Task-ID).
#
# Bei Interrupt: gibt eine actionable Meldung aus und trägt einen Blocker in
# die Task-Datei ein (gleiche Konvention wie /implement). Siehe ADR-004.
#
# Das Sentinel wird NICHT entfernt – es bleibt zur Inspektion liegen und wird
# vom Preflight des nächsten Pipeline-Laufs (run-pipeline.sh) bereinigt.

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TASK_ID="${1:-}"
if [ -z "$TASK_ID" ]; then
  echo "Verwendung: bash scripts/checks/interrupt-check.sh <task-id>" >&2
  exit 2
fi

SENTINEL="$FACTORY_DIR/tasks/INTERRUPT-${TASK_ID}.md"
[ -f "$SENTINEL" ] || exit 0

TYPE=$(grep -m1 '^Typ:' "$SENTINEL" | sed 's/^Typ:[[:space:]]*//')
MESSAGE=$(grep -m1 '^Nachricht:' "$SENTINEL" | sed 's/^Nachricht:[[:space:]]*//')
ACTION=$(grep -m1 '^Aktion:' "$SENTINEL" | sed 's/^Aktion:[[:space:]]*//')

echo ""
echo -e "${RED}[INTERRUPT] ${TYPE}: ${MESSAGE}${NC}"
echo -e "  → ${ACTION}"
echo -e "${YELLOW}Pipeline gestoppt – menschliche Entscheidung erforderlich.${NC}"

# Blocker in der Task-Datei protokollieren (idempotent – nicht doppelt eintragen)
TASK_FILE=$(find "$FACTORY_DIR/tasks" -name "task-${TASK_ID}-*.md" 2>/dev/null | head -1)
if [ -n "$TASK_FILE" ]; then
  BLOCKER="Blocker $(date +%Y-%m-%d): Pipeline pausiert – ${TYPE}: ${MESSAGE} (${ACTION})"
  if ! grep -qF "Pipeline pausiert – ${TYPE}: ${MESSAGE}" "$TASK_FILE"; then
    printf '\n%s\n' "$BLOCKER" >> "$TASK_FILE"
    echo -e "  ${YELLOW}↳${NC} Blocker in $(basename "$TASK_FILE") eingetragen."
  fi
fi

exit 1
