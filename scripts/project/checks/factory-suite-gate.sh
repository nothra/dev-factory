#!/usr/bin/env bash
# factory-suite-gate.sh – commands.test des Factory-Repos: ausgelieferte Suite, außer bei reinem Spec-/Task-Diff
#
# Verwendung: bash scripts/project/checks/factory-suite-gate.sh   (über commands.test in factory.config.yml)
#
# Warum es das gibt (Factory-Issue #51, Spec docs/specs/spec-51-pre-push-suite-skip.md): Die ausgelieferte Suite
# dauert lokal ~9,5 min und lief bei jedem Push, auch wenn der Branch nur eine Task-Datei und eine Spec enthält.
# Fail-closed ist ohnehin der Required Check `factory-self-test` in CI, der die Suite immer ausführt. Lokale Gates
# (pre-push-Hook, Quality-Gates von run-pipeline.sh) überspringen sie deshalb, wenn die Änderungsmenge gegenüber
# dem Merge-Base mit origin/main ausschließlich unter tasks/ oder docs/specs/ liegt. Andere docs/-Bereiche zählen
# nicht: die Suite enthält Doku-Guards über docs/factory/.
#
# Bewusst kein ADR und keine Änderung an pre-push.sh: die Regel gilt nur für dieses Repo (in Konsumenten ist
# commands.test die Produkt-Suite) und ist mit einer Config-Zeile umkehrbar – Begründung in tasks/task-51-*.md.
#
# Änderungsmenge = committete Änderungen seit dem Merge-Base + staged/unstaged + untracked (nicht ignoriert);
# Umbenennungen zählen mit Quell- und Zielpfad. Im Zweifel läuft die Suite: fehlende Merge-Base, jeder
# Git-Fehler und eine leere Änderungsmenge führen zum vollen Lauf. FACTORY_FORCE_FULL_SUITE (nicht leer)
# erzwingt ihn. Die Suite wird per exec gestartet – ihr Exit-Code ist der des Wrappers.

set -uo pipefail

ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
SUITE="$ROOT/scripts/checks/tests/run-tests.sh"
CHANGES_FILE=""
FAILED_STEP=""

run_full_suite() {
  echo "Factory-Suite läuft vollständig: $1"
  [ -z "$CHANGES_FILE" ] || rm -f "$CHANGES_FILE"
  exec bash "$SUITE"
}

# collect_changes <basis> <ausgabe-datei> – NUL-getrennte Änderungsmenge; jeder Befehl mit eigenem Exit-Check,
# bei Fehler steht der Schritt in FAILED_STEP.
collect_changes() {
  local base="$1" out="$2"
  git -C "$ROOT" diff --name-only -z --no-renames "$base" HEAD > "$out" \
    || { FAILED_STEP="git diff (committet)"; return 1; }
  git -C "$ROOT" diff --name-only -z --no-renames HEAD >> "$out" \
    || { FAILED_STEP="git diff (Working Tree)"; return 1; }
  git -C "$ROOT" ls-files -z --others --exclude-standard >> "$out" \
    || { FAILED_STEP="git ls-files (untracked)"; return 1; }
}

# first_outside_path <datei> – gibt den ersten Pfad außerhalb von tasks/ und docs/specs/ aus (Exit 0), sonst Exit 1.
# Der Schrägstrich im Muster schließt tasks-old/ und docs/specs-archive/ aus.
first_outside_path() {
  local path
  while IFS= read -r -d '' path; do
    case "$path" in
      tasks/*|docs/specs/*) ;;
      *) printf '%s' "$path"; return 0 ;;
    esac
  done < "$1"
  return 1
}

main() {
  local base outside
  [ -z "${FACTORY_FORCE_FULL_SUITE:-}" ] || run_full_suite "Override FACTORY_FORCE_FULL_SUITE gesetzt"

  base="$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null)" && [ -n "$base" ] \
    || run_full_suite "Merge-Base mit origin/main nicht bestimmbar"

  CHANGES_FILE="$(mktemp)" || run_full_suite "temporäre Datei für die Änderungsmenge nicht anlegbar"
  collect_changes "$base" "$CHANGES_FILE" || run_full_suite "Git-Fehler bei $FAILED_STEP"

  [ -s "$CHANGES_FILE" ] || run_full_suite "leere Änderungsmenge (kein Beleg für reine Spec-/Task-Änderung)"

  if outside="$(first_outside_path "$CHANGES_FILE")"; then
    run_full_suite "Datei außerhalb von tasks/ und docs/specs/: $outside"
  fi

  rm -f "$CHANGES_FILE"
  echo "Factory-Suite übersprungen: nur Spec-/Task-Dateien geändert (tasks/, docs/specs/)."
  echo "  CI (factory-self-test) führt die Suite weiterhin aus; voller Lauf lokal: FACTORY_FORCE_FULL_SUITE=1"
  exit 0
}

main "$@"
