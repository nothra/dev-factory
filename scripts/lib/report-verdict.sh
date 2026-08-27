#!/usr/bin/env bash
# report-verdict.sh – sourcebare Bibliothek: kanonische Verdict-Erkennung für die
# report-erzeugenden Skills (ADR-019 §4). Stellt DREI Funktionen bereit:
#
#   report_file <skill> <task_id> [tasks_dir]
#     → druckt den Pfad der Report-Datei des Skills, bei jedem anderen Skill nichts.
#       Die Skill→Datei-Zuordnung steht NUR hier (ein Ort, #310 AK9) – run-pipeline.sh
#       baut keinen Report-Pfad mehr selbst.
#
#   report_verdict <skill> <task_id> [tasks_dir]
#     → druckt den gültigen Verdict-String auf stdout, sonst nichts:
#         review          → APPROVED | NEEDS_REWORK   (aus tasks/review-<id>.md)
#         security-review → PASSED   | NEEDS_FIXES    (aus tasks/security-<id>.md)
#       Bei fehlender Datei, fehlendem Verdict oder jedem anderen Skill: leerer stdout.
#     → Exit immer 0; der Aufrufer entscheidet am (nicht-)leeren stdout.
#
#   report_fingerprint <skill> <task_id> [tasks_dir]
#     → druckt einen Fingerprint des Report-INHALTS (Änderungserkennung, #310).
#
# EINE Quelle für zwei Nutzer in scripts/run-pipeline.sh, damit sie nicht
# auseinanderdriften (ADR-019 §4 „ein Ort"):
#   - run_skill()-Report-Guard: ein non-zero Exit (inkl. „Reached max turns") gilt als
#     ERFOLG, wenn report_verdict für dieses Skill etwas liefert UND sich der Report
#     seit dem Beginn dieses Skill-Aufrufs verändert hat (report_fingerprint) – der
#     Report war fertig, bevor das Turn-Limit riss. Nur für review/security-review;
#     sonst Fehlversuch.
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

report_file() {
  local skill="$1" task_id="$2" tasks_dir="${3:-${FACTORY_DIR:-.}/tasks}"
  case "$skill" in
    review)          printf '%s\n' "$tasks_dir/review-${task_id}.md" ;;
    security-review) printf '%s\n' "$tasks_dir/security-${task_id}.md" ;;
  esac
}

# Frische-Fingerprint (#310): Der Report-Guard darf einen Verdict nur honorieren, wenn er im
# LAUFENDEN Skill-Aufruf entstanden ist. Ohne diese Prüfung gilt ein stehengebliebener Verdict
# aus einer früheren Review-Iteration desselben Laufs (#310, Task 308: Circuit Breaker trotz
# fertigem Rework) oder aus einem früheren Pipeline-Lauf (#91: fail-open ohne jedes Review) als
# frischer Erfolg. Verglichen wird der Inhalt, nicht die mtime – ein Agent, der die Datei
# unverändert neu schreibt, soll nicht schon dadurch als „fertig" gelten.
#
# POSIX-`cksum` statt SHA-256: die Prüfung erkennt nur Änderungen (keine Angreifer-Abwehr),
# und `cksum` gibt es auf macOS/BSD, GNU und busybox – das erspart eine weitere
# Capability-Prüfung à la scripts/install-yq.sh. Eingabe per stdin, damit nur der Inhalt
# zählt (mit Dateiargument druckt cksum den Namen mit).
#
# Marker statt Prüfsumme in zwei Fällen – beide fail-closed, nie ein stiller Erfolg:
#   ABSENT     – Datei existiert nicht. Eigener Wert, damit der Übergang „fehlt → vorhanden"
#                als Veränderung zählt (AK3).
#   UNREADABLE – Datei da, Prüfsumme nicht ermittelbar (Lesefehler, fehlendes Werkzeug).
#                Bleibt der Zustand bestehen, sind Vorher/Nachher gleich → stale → Fehlversuch.
report_fingerprint() {
  local skill="$1" task_id="$2" tasks_dir="${3:-${FACTORY_DIR:-.}/tasks}"
  local file checksum
  file="$(report_file "$skill" "$task_id" "$tasks_dir")"
  [ -n "$file" ] || { printf 'NO_REPORT_SKILL\n'; return 0; }
  [ -f "$file" ] || { printf 'ABSENT\n'; return 0; }
  # Reihenfolge der Redirections: die stderr-Umleitung steht VOR der Eingabe-Umleitung. Bash
  # wertet Redirections von links nach rechts aus – stünde sie danach, schriebe eine
  # scheiternde Eingabe-Umleitung ihre „Permission denied"-Meldung noch ins Pipeline-Log,
  # obwohl der Zweig sie schlucken will (#310 Review-Finding W1; das Ergebnis war schon
  # vorher fail-closed).
  checksum="$(cksum 2>/dev/null < "$file")" || checksum=""
  [ -n "$checksum" ] || { printf 'UNREADABLE\n'; return 0; }
  printf '%s\n' "$checksum"
}

report_verdict() {
  local skill="$1" task_id="$2" tasks_dir="${3:-${FACTORY_DIR:-.}/tasks}"
  # pass_token = bestandener Verdict, fail_token = Rework/Fixes-Verdict (je Skill genau diese zwei).
  local file header pass_token fail_token
  file="$(report_file "$skill" "$task_id" "$tasks_dir")"
  case "$skill" in
    review)          header='## Empfehlung'; pass_token='APPROVED'; fail_token='NEEDS_REWORK' ;;
    security-review) header='## Ergebnis';   pass_token='PASSED';   fail_token='NEEDS_FIXES' ;;
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
