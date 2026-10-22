#!/usr/bin/env bash
# factory-sync.sh – setzt zusammengesetzte Dateien aus Factory- und Projekt-Fragment zusammen
#
# Verwendung:
#   bash scripts/factory-sync.sh --compose          schreibt .claude/settings.json und .gitignore
#   bash scripts/factory-sync.sh --compose --check  schreibt nichts; exit 1, wenn eine committete
#                                                   Datei von der Zusammensetzung abweicht
#
# Warum es das gibt (Factory-ADR-063 D3, Q2): Claude Code liest genau eine geteilte Projekt-
# Settings-Datei, Git genau eine Wurzel-.gitignore – beide mischen Factory- und Projekt-Anteil.
# Jeder Anteil liegt deshalb in einem eigenen Fragment; diese Datei erzeugt daraus deterministisch
# die committete Datei. Ändern geht nur über das Fragment + erneutes `--compose`.
#
#   .claude/settings.json = .claude/settings.factory.json + .claude/settings.project.json
#       Hooks je Ereignis hintereinander (Factory zuerst); jedes Permission-Array vereinigt
#       und sortiert; übrige Schlüssel: Projekt überschreibt Factory.
#   .gitignore            = docs/factory/gitignore.factory, dann .gitignore.project
#
# Dieser Stand kennt nur --compose; weitere Modi (Sync/Init) folgen mit T2 (Q2).
# Projektwurzel: FACTORY_DIR (Tests/Override), sonst eine Ebene über scripts/.
# Fail-closed: fehlendes Fragment, fehlendes jq oder ungültiges JSON → exit 1, nichts geschrieben.

set -uo pipefail

ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SETTINGS_FACTORY=".claude/settings.factory.json"
SETTINGS_PROJECT=".claude/settings.project.json"
SETTINGS_TARGET=".claude/settings.json"
GITIGNORE_FACTORY="docs/factory/gitignore.factory"
GITIGNORE_PROJECT=".gitignore.project"
GITIGNORE_TARGET=".gitignore"

# jq-Programm: Hooks hintereinander, Permission-Arrays vereinigt + sortiert.
COMPOSE_SETTINGS_JQ='
  .[0] as $f | .[1] as $p |
  ($f.hooks // {}) as $fh | ($p.hooks // {}) as $ph |
  ($f.permissions // {}) as $fp | ($p.permissions // {}) as $pp |
  (($f * $p) | del(.hooks, .permissions)) as $rest |
  $rest
  + { hooks: ([$fh, $ph] | map(keys) | add | unique | map(. as $e | { key: $e, value: (($fh[$e] // []) + ($ph[$e] // [])) }) | from_entries) }
  + { permissions: ([$fp, $pp] | map(keys) | add | unique | map(. as $k | { key: $k, value: ((($fp[$k] // []) + ($pp[$k] // [])) | unique) }) | from_entries) }
'

die() { printf '✗ factory-sync: %s\n' "$1" >&2; exit 1; }

compose_settings() {
  jq -s "$COMPOSE_SETTINGS_JQ" "$SETTINGS_FACTORY" "$SETTINGS_PROJECT"
}

compose_gitignore() {
  cat "$GITIGNORE_FACTORY" "$GITIGNORE_PROJECT"
}

# require_inputs – alle Fragmente lesbar, Settings-Fragmente gültiges JSON.
require_inputs() {
  command -v jq >/dev/null 2>&1 || die "jq nicht gefunden (fail-closed)"
  local f
  for f in "$SETTINGS_FACTORY" "$SETTINGS_PROJECT" "$GITIGNORE_FACTORY" "$GITIGNORE_PROJECT"; do
    [ -f "$f" ] && [ -r "$f" ] || die "Fragment fehlt oder ist nicht lesbar: $f"
  done
  for f in "$SETTINGS_FACTORY" "$SETTINGS_PROJECT"; do
    jq -e . "$f" >/dev/null 2>&1 || die "kein gültiges JSON: $f"
  done
}

# emit <ziel> – schreibt die Zusammensetzung des Ziels auf stdout.
emit() {
  case "$1" in
    "$SETTINGS_TARGET") compose_settings ;;
    "$GITIGNORE_TARGET") compose_gitignore ;;
  esac
}

run_compose() {
  local check="$1" target tmp drift=0
  for target in "$SETTINGS_TARGET" "$GITIGNORE_TARGET"; do
    tmp="$(mktemp)" || die "mktemp fehlgeschlagen"
    emit "$target" > "$tmp" || { rm -f "$tmp"; die "Zusammensetzen von $target fehlgeschlagen"; }
    if [ "$check" -eq 1 ]; then
      if ! cmp -s "$tmp" "$target"; then
        printf '✗ factory-sync: %s weicht von der Zusammensetzung der Fragmente ab\n' "$target"
        drift=1
      fi
      rm -f "$tmp"
    else
      mv "$tmp" "$target" || die "Schreiben von $target fehlgeschlagen"
      printf '✓ %s zusammengesetzt\n' "$target"
    fi
  done
  if [ "$drift" -eq 1 ]; then
    echo "     Beheben: Fragment ändern und 'bash scripts/factory-sync.sh --compose' ausführen, dann beide committen."
    exit 1
  fi
  [ "$check" -eq 0 ] || echo "✓ settings.json und .gitignore entsprechen den Fragmenten"
}

compose=0 check=0
for arg in "$@"; do
  case "$arg" in
    --compose) compose=1 ;;
    --check) check=1 ;;
    *) die "unbekanntes Argument: $arg (Verwendung: --compose [--check])" ;;
  esac
done
[ "$compose" -eq 1 ] || die "kein Modus angegeben (Verwendung: --compose [--check])"

cd "$ROOT" 2>/dev/null || die "Projektwurzel nicht erreichbar: $ROOT"
require_inputs
run_compose "$check"
