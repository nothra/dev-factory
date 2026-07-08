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

# Prüfe alle Task-Dateien auf offene Checkboxen.
# Newline-sichere Iteration (while read) statt `for f in $VAR` – sonst werden
# Pfade mit Leerzeichen am Space zerlegt (Bug #8: "…/TCH Gastro Services").
# head -5 kann SIGPIPE auslösen → Pipeline mit `|| true` gegen pipefail absichern.
found_open=0
while IFS= read -r task_file; do
  [ -z "$task_file" ] && continue
  if [ "$found_open" -eq 0 ]; then
    echo ""
    echo -e "${YELLOW}Hinweis: Offene Checkboxen in Task-Dateien:${NC}"
    found_open=1
  fi
  echo "  ${task_file}:"
  grep "^- \[ \]" "$task_file" 2>/dev/null | head -5 | sed 's/^/    /' || true
done < <(find "$FACTORY_DIR/tasks" -name "task-*.md" -exec grep -l "^- \[ \]" {} \; 2>/dev/null || true)

if [ "$found_open" -eq 1 ]; then
  echo ""
  echo "Bitte alle Punkte abschließen oder bewusst offene Punkte als nächste Task erfassen."
fi

# Exit 0: Nur Hinweis, kein harter Block beim Stop-Hook (für harten Block: exit 1).
exit 0
