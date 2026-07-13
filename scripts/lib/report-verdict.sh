#!/usr/bin/env bash
# report-verdict.sh – sourcebare Bibliothek: kanonische Verdict-Erkennung für die
# report-erzeugenden Skills (ADR-019 §4).
#
#   report_verdict <skill> <task_id> [tasks_dir]
#     → druckt den gültigen Verdict-String auf stdout, sonst nichts:
#         review          → APPROVED | NEEDS_REWORK   (aus tasks/review-<id>.md)
#         security-review → PASSED   | NEEDS_FIXES    (aus tasks/security-<id>.md)
#       Bei fehlender Datei, fehlendem Verdict oder jedem anderen Skill: leerer stdout.
#     → Exit immer 0; der Aufrufer entscheidet am (nicht-)leeren stdout.
#
# EINE Quelle für zwei Nutzer in scripts/run-pipeline.sh, damit sie nicht
# auseinanderdriften (ADR-019 §4 „ein Ort"):
#   - run_skill()-Report-Guard: ein non-zero Exit (inkl. „Reached max turns") gilt als
#     ERFOLG, wenn report_verdict für dieses Skill etwas liefert – der Report war fertig,
#     bevor das Turn-Limit riss. Nur für review/security-review; sonst Fehlversuch.
#   - pipeline_summary(): zeigt denselben Verdict an.
#
# Die Muster koppeln an die verbindlichen Report-Werte aus
# .claude/commands/review.md / security-review.md (wie zuvor pipeline_summary()).
# Case-sensitiv wie im Report; nur POSIX-Regex (grep -oE), portabel macOS/BSD +
# GNU/Alpine (clean-code.md „Portabilität in Gate-Skripten").

report_verdict() {
  local skill="$1" task_id="$2" tasks_dir="${3:-${FACTORY_DIR:-.}/tasks}"
  local file pattern
  case "$skill" in
    review)          file="$tasks_dir/review-${task_id}.md";   pattern='APPROVED|NEEDS_REWORK' ;;
    security-review) file="$tasks_dir/security-${task_id}.md"; pattern='PASSED|NEEDS_FIXES' ;;
    *) return 0 ;;
  esac
  [ -f "$file" ] || return 0
  # Letztes Vorkommen gewinnt. grep findet nichts → exit 1; unter pipefail muss das
  # geschluckt werden, sonst bräche der Aufrufer ab.
  grep -oE "$pattern" "$file" 2>/dev/null | tail -1 || true
}
