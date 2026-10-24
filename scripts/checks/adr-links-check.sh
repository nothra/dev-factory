#!/usr/bin/env bash
# adr-links-check.sh – kein toter ADR-Link im Repo
#
# Seit die Factory-ADRs unter docs/factory/adr/ liegen und die App-ADRs unter docs/adr/ (ADR-063
# D8, Spec nothra/tch-gastro-services#426 AK-B3), kann ein Verweis beim Umzug ins Leere zeigen. Geprüft werden in jeder
# getrackten Textdatei (Specs, Tasks, Lessons, Skripte inklusive):
#   1. Markdown-Links auf eine ADR-Datei im ADR-Verzeichnis – relativ zur Datei, die den Link enthält
#   2. Wurzel-relative Pfadangaben `docs/adr/NNN-….md` bzw. `docs/factory/adr/NNN-….md`
# Verzeichnis-Links (`../adr/`) sind kein Dateiverweis und werden nicht geprüft.
#
# Verwendung: bash scripts/checks/adr-links-check.sh
# Exit 0 = alle Ziele existieren, 1 = mindestens ein toter Link (Quelle:Zeile und Ziel genannt),
# 2 = Prüfung nicht möglich (git ls-files fehlgeschlagen) – fail-closed.

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

if ! git -C "$FACTORY_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  echo "adr-links-check: kein git-Repo: $FACTORY_DIR" >&2
  exit 2
fi

DEAD=0
CHECKED=0

# report_dead <datei> <zeile> <ziel>
report_dead() {
  echo "✗ $1:$2: toter ADR-Link → $3"
  DEAD=$((DEAD + 1))
}

# Binärdateien (PDF, PNG) schließt `git grep -I` aus; die Links stehen in Textdateien.
MD_LINKS="$(git -C "$FACTORY_DIR" grep -nIoE '\]\([^)#[:space:]]*adr/[^)#[:space:]]+\.md(#[^)[:space:]]*)?\)' -- . ':!tasks/patch-*.diff' 2>/dev/null)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; match="${rest#*:}"
  target="${match#\](}"; target="${target%)}"; target="${target%%#*}"
  case "$target" in
    http*|mailto:*) continue ;;
    /*) resolved="$FACTORY_DIR$target" ;;
    *) resolved="$FACTORY_DIR/$(dirname "$file")/$target" ;;
  esac
  CHECKED=$((CHECKED + 1))
  [ -e "$resolved" ] || report_dead "$file" "$line" "$target"
done <<< "$MD_LINKS"

ROOT_PATHS="$(git -C "$FACTORY_DIR" grep -nIoE 'docs/(factory/)?adr/[0-9]{3}-[A-Za-z][A-Za-z0-9._-]*\.md' -- . ':!tasks/patch-*.diff' 2>/dev/null)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; target="${rest#*:}"
  CHECKED=$((CHECKED + 1))
  [ -e "$FACTORY_DIR/$target" ] || report_dead "$file" "$line" "$target"
done <<< "$ROOT_PATHS"

if [ "$DEAD" -gt 0 ]; then
  echo "adr-links-check: $DEAD toter/tote ADR-Link(s) von $CHECKED geprüften." >&2
  exit 1
fi
echo "✓ Kein toter ADR-Link ($CHECKED geprüft)"
