#!/usr/bin/env bash
# raise-interrupt.sh – Signalisiert der Stage-3-Pipeline, dass eine
# menschliche Entscheidung nötig ist (deterministischer Stopp-Punkt).
#
# Verwendung: bash scripts/raise-interrupt.sh <task-id> <typ> <nachricht> [aktion]
# Beispiel:   bash scripts/raise-interrupt.sh 42 ADR \
#               "Trigger-Kategorie 2: Wechsel auf Event-Driven-Architektur"
#
# Schreibt das Sentinel tasks/INTERRUPT-<task-id>.md. run-pipeline.sh prüft es
# nach jedem Schritt (interrupt-check.sh) und stoppt hart, wenn es existiert.
# Siehe ADR-004.
#
# Gedacht für nicht-interaktive Läufe (Stage 3): Wenn ein Agent eine nicht
# automatisierbare Entscheidung erkennt (z.B. ADR-Trigger) und niemand zum
# Fragen da ist, ruft er dieses Skript auf statt zu fragen.

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

TASK_ID="${1:-}"
TYPE="${2:-}"
MESSAGE="${3:-}"
ACTION="${4:-/architecture ausführen, dann Pipeline neu starten}"

if [ -z "$TASK_ID" ] || [ -z "$TYPE" ] || [ -z "$MESSAGE" ]; then
  echo "Verwendung: bash scripts/raise-interrupt.sh <task-id> <typ> <nachricht> [aktion]" >&2
  exit 1
fi

mkdir -p "$FACTORY_DIR/tasks"
SENTINEL="$FACTORY_DIR/tasks/INTERRUPT-${TASK_ID}.md"

{
  echo "# INTERRUPT – Task ${TASK_ID}"
  echo ""
  echo "Typ: ${TYPE}"
  echo "Nachricht: ${MESSAGE}"
  echo "Aktion: ${ACTION}"
  echo "Zeitpunkt: $(date +"%Y-%m-%d %H:%M")"
} > "$SENTINEL"

# Append-only Audit-Log: überlebt den Preflight-Sentinel-Cleanup und ist die
# Quelle der Autonomie-Rate (/daily-metrics, ADR-006). Eine JSON-Zeile pro Event.
LOG="$FACTORY_DIR/tasks/interrupt-log.jsonl"
# JSON-escape inkl. der Steuerzeichen, die JSON-Strings verbieten (Tab/Newline/CR).
# Reine Bash-Parameter-Expansion – kein jq-Zwang im Kern-Interrupt-Pfad.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}      # Backslash zuerst
  s=${s//\"/\\\"}      # Double-Quote
  s=${s//$'\t'/\\t}    # Tab
  s=${s//$'\r'/\\r}    # Carriage Return
  s=${s//$'\n'/\\n}    # Newline (zersplittert sonst den Record)
  printf '%s' "$s"
}
printf '{"ts":"%s","task_id":"%s","type":"%s","message":"%s"}\n' \
  "$(date +"%Y-%m-%dT%H:%M:%S")" \
  "$(json_escape "$TASK_ID")" \
  "$(json_escape "$TYPE")" \
  "$(json_escape "$MESSAGE")" \
  >> "$LOG"

echo "Interrupt signalisiert: tasks/INTERRUPT-${TASK_ID}.md"
echo "  Typ:       ${TYPE}"
echo "  Nachricht: ${MESSAGE}"
