#!/usr/bin/env bash
# ownership-check.sh – jede getrackte Datei gehört genau einer Seite (factory | project)
#
# Quelle der Zuordnung: docs/factory/OWNERSHIP.md (ADR-063 D3/D11, Spec #426 AK-A1…A6).
# Das Zeilenformat ist dort beschrieben; dieses Skript ist sein einziger Parser – T1b erzeugt
# die filter-repo-Allowlist über `--list factory`, nicht über ein zweites Format.
#
# Verwendung:
#   bash scripts/checks/ownership-check.sh              # prüfen (Exit 0 = vollständig und eindeutig)
#   bash scripts/checks/ownership-check.sh --list SEITE # Dateien einer Seite ausgeben (factory|project)
#
# Umgebung (nur für Tests): FACTORY_DIR, OWNERSHIP_FILE, OWNERSHIP_FILE_LIST (Dateiliste statt
# `git ls-files`).
#
# Fail-closed: nicht lesbare Tabelle, leere Tabelle oder nicht ermittelbare Dateiliste → Exit 2.
# Fehlende oder doppelte Zuordnung → Exit 1, jede Datei namentlich.

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OWNERSHIP_FILE="${OWNERSHIP_FILE:-$FACTORY_DIR/docs/factory/OWNERSHIP.md}"
LIST_SIDE=""

case "${1:-}" in
  "") ;;
  --list)
    LIST_SIDE="${2:-}"
    case "$LIST_SIDE" in
      factory|project) ;;
      *) echo "ownership-check: --list erwartet 'factory' oder 'project'" >&2; exit 2 ;;
    esac
    ;;
  *) echo "ownership-check: unbekannter Parameter: $1" >&2; exit 2 ;;
esac

if [ ! -r "$OWNERSHIP_FILE" ]; then
  echo "ownership-check: Zuordnungstabelle nicht lesbar: $OWNERSHIP_FILE" >&2
  exit 2
fi

if [ -n "${OWNERSHIP_FILE_LIST:-}" ]; then
  if [ ! -r "$OWNERSHIP_FILE_LIST" ]; then
    echo "ownership-check: Dateiliste nicht lesbar: $OWNERSHIP_FILE_LIST" >&2
    exit 2
  fi
  TRACKED_FILES="$(cat "$OWNERSHIP_FILE_LIST")"
else
  TRACKED_FILES="$(git -C "$FACTORY_DIR" ls-files)" || {
    echo "ownership-check: git ls-files fehlgeschlagen in $FACTORY_DIR" >&2
    exit 2
  }
fi

if [ -z "$TRACKED_FILES" ]; then
  echo "ownership-check: keine getrackten Dateien gefunden (fail-closed)" >&2
  exit 2
fi

# Pass 1 liest die Tabelle (Zeilen `| factory | muster | begründung |`), Pass 2 die Dateiliste.
# Glob → ERE: `**` = beliebig tief, `*` = innerhalb eines Pfadsegments, alles andere wörtlich.
printf '%s\n' "$TRACKED_FILES" | awk -F'|' -v list_side="$LIST_SIDE" -v table="$OWNERSHIP_FILE" '
  function glob_to_ere(glob,    out, i, c, nxt) {
    out = "^"
    for (i = 1; i <= length(glob); i++) {
      c = substr(glob, i, 1)
      nxt = substr(glob, i + 1, 1)
      if (c == "*" && nxt == "*") { out = out ".*"; i++ }
      else if (c == "*") { out = out "[^/]*" }
      else if (index("\\.+?(){}[]^$|", c) > 0) { out = out "\\" c }
      else { out = out c }
    }
    return out "$"
  }
  function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
  BEGIN {
    FS = "|"
    while ((getline line < table) > 0) {
      if (line !~ /^\| *(factory|project) *\|/) continue
      n = split(line, cell, "|")
      side = trim(cell[2]); pattern = trim(cell[3])
      if (pattern == "") continue
      rows++
      row_side[rows] = side; row_pattern[rows] = pattern; row_ere[rows] = glob_to_ere(pattern)
    }
    close(table)
    if (rows == 0) { print "ownership-check: Zuordnungstabelle enthält keine Zeilen (fail-closed)" > "/dev/stderr"; exit 2 }
  }
  NF == 1 && $0 != "" {
    file = $0; total++
    delete hit
    for (r = 1; r <= rows; r++)
      if (file ~ row_ere[r] && !(row_side[r] in hit)) hit[row_side[r]] = row_pattern[r]
    if (("factory" in hit) && ("project" in hit)) {
      bad++; print "✗ " file ": mehreren Seiten zugeordnet (factory: " hit["factory"] ", project: " hit["project"] ")"
    } else if (!("factory" in hit) && !("project" in hit)) {
      bad++; print "✗ " file ": keiner Seite zugeordnet"
    } else if ("factory" in hit) { nf++; if (list_side == "factory") print file }
    else { np++; if (list_side == "project") print file }
  }
  END {
    if (list_side != "") { exit (bad > 0 ? 1 : 0) }
    if (bad > 0) {
      print "ownership-check: " bad " von " total " Dateien ohne eindeutige Zuordnung – docs/factory/OWNERSHIP.md ergänzen." > "/dev/stderr"
      exit 1
    }
    print "✓ Zuordnung vollständig und eindeutig: " total " Dateien (factory: " nf ", project: " np ")"
  }
'
