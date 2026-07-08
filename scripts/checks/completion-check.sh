#!/usr/bin/env bash
# completion-check.sh – Prüft ob offene Checkboxen existieren
#
# Wird durch Claude Code Stop-Hook aufgerufen (settings.json).
# Verhindert dass Claude eine Task als "fertig" markiert wenn noch
# Checkboxen in der Task-Datei offen sind.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YELLOW='\033[1;33m'
NC='\033[0m'

# Prüfe alle Task-Dateien auf offene Checkboxen
OPEN_CHECKBOXES=$(find "$FACTORY_DIR/tasks" -name "task-*.md" -exec grep -l "^- \[ \]" {} \; 2>/dev/null || true)

if [ -n "$OPEN_CHECKBOXES" ]; then
  echo ""
  echo -e "${YELLOW}Hinweis: Offene Checkboxen in Task-Dateien:${NC}"
  for task_file in $OPEN_CHECKBOXES; do
    echo "  $task_file:"
    grep "^- \[ \]" "$task_file" | head -5 | sed 's/^/    /'
  done
  echo ""
  echo "Bitte alle Punkte abschließen oder bewusst offene Punkte als nächste Task erfassen."
  # Exit 0: Nur Hinweis, kein harter Block beim Stop-Hook
  # Für harten Block: auf exit 1 ändern
  exit 0
fi

exit 0
