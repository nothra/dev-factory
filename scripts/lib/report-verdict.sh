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
# Der Verdict wird AUSSCHLIESSLICH aus der ersten nicht-leeren Zeile unter der
# verbindlichen Anker-Überschrift gelesen (review → '## Empfehlung',
# security-review → '## Ergebnis'; .claude/commands/review.md / security-review.md).
# Eine Fließtext-Erwähnung eines Verdict-Wortes an anderer Stelle im Report darf das
# Ergebnis nicht mehr verfälschen (#211: ein Volltext-Grep wertete bei #206 ein
# NEEDS_REWORK-Review wegen einer späteren APPROVED-Erwähnung fälschlich als bestanden).
# Fail-closed: fehlender Anker, kein oder mehrdeutiges Token → leeres Verdict, kein Raten.
# Case-sensitiv wie im Report; nur POSIX-Regex / portables awk, macOS/BSD + GNU/Alpine
# (clean-code.md „Portabilität in Gate-Skripten").

report_verdict() {
  local skill="$1" task_id="$2" tasks_dir="${3:-${FACTORY_DIR:-.}/tasks}"
  # pass_token = bestandener Verdict, fail_token = Rework/Fixes-Verdict (je Skill genau diese zwei).
  local file header pass_token fail_token
  case "$skill" in
    review)          file="$tasks_dir/review-${task_id}.md";   header='## Empfehlung'; pass_token='APPROVED'; fail_token='NEEDS_REWORK' ;;
    security-review) file="$tasks_dir/security-${task_id}.md"; header='## Ergebnis';   pass_token='PASSED';   fail_token='NEEDS_FIXES' ;;
    *) return 0 ;;
  esac
  [ -f "$file" ] || return 0
  awk -v header="$header" -v pass="$pass_token" -v fail="$fail_token" '
    # Anker-Überschrift exakt (umgebender Whitespace erlaubt); erstes Vorkommen zählt.
    !found && $0 ~ ("^[[:space:]]*" header "[[:space:]]*$") { found = 1; next }
    found {
      if ($0 ~ /^[[:space:]]*$/) next            # Leerzeilen bis zum Verdict überspringen
      hasPass = index($0, pass) > 0
      hasFail = index($0, fail) > 0
      if (hasPass && !hasFail) print pass        # genau ein gültiges Token → Verdict
      else if (hasFail && !hasPass) print fail
      exit                                       # nur die erste nicht-leere Zeile zählt
    }
  ' "$file" 2>/dev/null || true
}
