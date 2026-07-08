#!/usr/bin/env bash
# metrics.sh – Prozess-/Outcome-Kennzahlen der Factory.
#
# Verwendung: bash scripts/metrics.sh [--no-api] [--quiet]
#   --no-api  überspringt die GitHub-API-Metriken (Lead-Time, CI-Quote)
#   --quiet   schreibt nur die Report-Datei, nicht nach stdout
#
# Mess-Ebene laut ADR-006: PROZESS (Git/GitHub). Token/Kosten kommen NICHT von
# hier, sondern aus der Telemetrie-Ebene (OTEL, config/otel.env.example).
#
# Local-first: Die lokalen Kennzahlen laufen immer. Die GitHub-API-Metriken
# (Lead-Time, CI-Grün-Quote) degradieren sauber, wenn gh fehlt oder nicht
# authentifiziert ist – der Report weist das dann aus.

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TASKS_DIR="$FACTORY_DIR/tasks"

USE_API=true
QUIET=false
for arg in "$@"; do
  case "$arg" in
    --no-api) USE_API=false ;;
    --quiet)  QUIET=true ;;
  esac
done

# ─── Lokale Metriken (immer verfügbar) ───────────────────────────────────────

open_interrupts=$(find "$TASKS_DIR" -maxdepth 1 -name 'INTERRUPT-*.md' 2>/dev/null | wc -l | tr -d ' ')

LOG="$TASKS_DIR/interrupt-log.jsonl"
total_interrupts=0           # Interrupt-Events über den gesamten Verlauf (Historie)
interrupted_ids=""           # eindeutige task_ids, die je einen Interrupt ausgelöst haben
if [ -f "$LOG" ]; then
  # grep -c gibt bei 0 Treffern "0" UND Exit 1 aus → kein "|| echo 0" (hängt sonst
  # ein zweites "0" an); stattdessen Leerwert über ${:-0} abfangen.
  total_interrupts=$(grep -c '"task_id"' "$LOG" 2>/dev/null); total_interrupts=${total_interrupts:-0}
  interrupted_ids=$(grep -oE '"task_id":"[^"]*"' "$LOG" 2>/dev/null | sed -E 's/.*:"([^"]*)"/\1/' | sort -u)
fi

# Autonomie-Rate schneidet die Mengen: nur Interrupts zählen, deren task_id auch
# eine existierende task-*.md hat. Sonst verfälschen Alt-/Fremd-IDs die KPI (ADR-006).
total_tasks=0
done_tasks=0
tasks_with_interrupt=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  total_tasks=$((total_tasks + 1))
  grep -qE '^- \[x\] Fertig' "$f" 2>/dev/null && done_tasks=$((done_tasks + 1))
  tid=$(basename "$f" | sed -E 's/^task-([^-]+)-.*/\1/')
  if [ -n "$interrupted_ids" ] && printf '%s\n' "$interrupted_ids" | grep -qxF "$tid"; then
    tasks_with_interrupt=$((tasks_with_interrupt + 1))
  fi
done < <(find "$TASKS_DIR" -maxdepth 1 -name 'task-*.md' 2>/dev/null)
in_progress=$((total_tasks - done_tasks))

# Anteil existierender Tasks, die nie einen Interrupt ausgelöst haben
autonomy="n/a"
if [ "$total_tasks" -gt 0 ]; then
  autonomy="$(( (total_tasks - tasks_with_interrupt) * 100 / total_tasks ))%"
fi

# ─── GitHub-API-Metriken (optional, degradieren sauber) ──────────────────────

lead_time="übersprungen"
ci_quote="übersprungen"
api_note=""

api_available() { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }

if [ "$USE_API" = true ]; then
  if api_available && command -v jq >/dev/null 2>&1; then
    # Lead-Time: Ø (mergedAt − createdAt) über die letzten gemergten PRs.
    prs=$(gh pr list --state merged --limit 20 --json createdAt,mergedAt 2>/dev/null || echo "")
    if [ -n "$prs" ]; then
      avg_h=$(printf '%s' "$prs" | jq -r '
        [ .[] | select(.mergedAt != null)
          | ((.mergedAt[0:19]+"Z")|fromdateiso8601) - ((.createdAt[0:19]+"Z")|fromdateiso8601) ]
        | if length > 0 then ((add/length)/3600) else empty end' 2>/dev/null || echo "")
      [ -n "$avg_h" ] && lead_time="$(printf '%.1f h' "$avg_h") (Ø über letzte $(printf '%s' "$prs" | jq 'length') PRs)"
    fi

    # CI-Grün-Quote: Anteil erfolgreicher Workflow-Läufe (GitHub Actions).
    runs=$(gh run list --limit 20 --json conclusion 2>/dev/null || echo "")
    if [ -n "$runs" ]; then
      total_p=$(printf '%s' "$runs" | jq 'length' 2>/dev/null || echo 0)
      green_p=$(printf '%s' "$runs" | jq '[.[]|select(.conclusion=="success")]|length' 2>/dev/null || echo 0)
      [ "$total_p" -gt 0 ] && ci_quote="$((green_p * 100 / total_p))% ($green_p/$total_p grün)"
    fi
  else
    api_note="_GitHub-API-Metriken übersprungen – gh nicht verfügbar/authentifiziert oder jq fehlt._"
  fi
else
  api_note="_GitHub-API-Metriken per --no-api übersprungen._"
fi

# ─── Report ──────────────────────────────────────────────────────────────────

today=$(date +"%Y-%m-%d")
report_file="$TASKS_DIR/metrics-${today}.md"

report=$(cat <<EOF
# Factory-Metriken – ${today}

Prozess-/Outcome-Kennzahlen (ADR-006, Prozess-Ebene). Token/Kosten siehe OTEL.

## Velocity & Qualität
| Metrik | Wert |
|--------|------|
| Lead-Time (Issue→Merge) | ${lead_time} |
| CI-Grün-Quote | ${ci_quote} |

## Autonomie
| Metrik | Wert |
|--------|------|
| Autonomie-Rate | ${autonomy} |
| Interrupt-Events (Historie) | ${total_interrupts} |
| Tasks mit Interrupt (vorhanden) | ${tasks_with_interrupt} |
| Offene Interrupts (jetzt) | ${open_interrupts} |

## Durchsatz
| Metrik | Wert |
|--------|------|
| Tasks gesamt | ${total_tasks} |
| Abgeschlossen | ${done_tasks} |
| In Arbeit | ${in_progress} |

${api_note}
EOF
)

printf '%s\n' "$report" > "$report_file"
[ "$QUIET" = false ] && printf '%s\n' "$report"
[ "$QUIET" = false ] && echo "" && echo "→ Report geschrieben: tasks/metrics-${today}.md"
