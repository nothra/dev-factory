#!/usr/bin/env bash
# ownership-check.sh – jede getrackte Datei gehört genau einer Seite (factory | project)
#
# Quelle der Zuordnung: docs/factory/OWNERSHIP.md (ADR-063 D3/D11, Spec nothra/tch-gastro-services#426 AK-A1…A6).
# Das Zeilenformat ist dort beschrieben; dieses Skript ist sein einziger Parser – T1b erzeugt
# die filter-repo-Allowlist über `--list factory`, nicht über ein zweites Format.
#
# Verwendung:
#   bash scripts/checks/ownership-check.sh              # prüfen (Exit 0 = vollständig und eindeutig)
#   bash scripts/checks/ownership-check.sh --list SEITE # Dateien einer Seite ausgeben (factory|project)
#
# Zwei Modi (Factory-ADR-064 D2, kein Mischmodus): Existiert `factory.lock` im Repo-Wurzelverzeichnis, gilt
# allein der Lock – Seite `factory` = seine Pfadmenge, alles andere `project`; sonst gilt die Tabelle.
# Der Lock ist das Release-Manifest (JSON, `schema` 1) und wird mit `jq` gelesen.
#
# Umgebung (nur für Tests): FACTORY_DIR, OWNERSHIP_FILE, OWNERSHIP_FILE_LIST (Dateiliste statt
# `git ls-files`), FACTORY_LOCK_FILE, CUSTOMIZATION_POINTS_FILE.
#
# Fail-closed: nicht lesbare Tabelle, leere Tabelle oder nicht ermittelbare Dateiliste → Exit 2.
# Fehlende oder doppelte Zuordnung → Exit 1, jede Datei namentlich.
# Lock-Modus: unlesbarer/ungültiger Lock, fehlendes `jq`, fehlende oder leere Anpassungsstellen-Liste → Exit 2
# (nie Rückfall in den Tabellenmodus); fehlender, doppelter oder als Anpassungsstelle geführter Lock-Pfad → Exit 1.
# Unterschied zum Tabellenmodus: Im Lock-Modus gehen alle Fehlermeldungen nach stderr, bei `--list` bleibt stdout dann leer
# (der Tabellenmodus druckt seine `✗`-Zeilen nach stdout).

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OWNERSHIP_FILE="${OWNERSHIP_FILE:-$FACTORY_DIR/docs/factory/OWNERSHIP.md}"
LOCK_FILE="${FACTORY_LOCK_FILE:-$FACTORY_DIR/factory.lock}"
CUSTOMIZATION_POINTS_FILE="${CUSTOMIZATION_POINTS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/customization-points.txt}"
LIST_SIDE=""
WORK_DIR=""   # Temp-Verzeichnis des Lock-Modus, gesetzt in lock_open_workspace

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

load_tracked_files() {
  if [ -n "${OWNERSHIP_FILE_LIST:-}" ]; then
    if [ ! -r "$OWNERSHIP_FILE_LIST" ]; then
      echo "ownership-check: Dateiliste nicht lesbar: $OWNERSHIP_FILE_LIST" >&2
      exit 2
    fi
    TRACKED_FILES="$(cat "$OWNERSHIP_FILE_LIST")"
  else
    TRACKED_FILES="$(git -C "$FACTORY_DIR" -c core.quotepath=false ls-files)" || {
      echo "ownership-check: git ls-files fehlgeschlagen in $FACTORY_DIR" >&2
      exit 2
    }
  fi

  if [ -z "$TRACKED_FILES" ]; then
    echo "ownership-check: keine getrackten Dateien gefunden (fail-closed)" >&2
    exit 2
  fi
}

# ─── Lock-Modus (ADR-064 D3) ─────────────────────────────────────────────────────────────────────────────────────────
# Seite `factory` = `files[].path` des Locks, Rest = `project`. Pfade werden wörtlich verglichen (der Lock nennt Pfade,
# keine Globs). Alle Funde einer Klasse werden gesammelt, nicht nur der erste. Eindeutigkeit der Zuordnung gilt hier per
# Konstruktion (es gibt nur einen Zweig); geprüft wird, dass Lock, Repo-Inhalt und Anpassungsstellen zusammenpassen.

# Fail-closed (Exit 2): jq, lesbarer und gültiger Lock, lesbare Liste der Anpassungsstellen.
lock_require_inputs() {
  command -v jq >/dev/null 2>&1 || { echo "ownership-check: Lock-Modus braucht jq (nicht gefunden)" >&2; exit 2; }
  [ -r "$LOCK_FILE" ] || { echo "ownership-check: factory.lock nicht lesbar: $LOCK_FILE" >&2; exit 2; }
  [ -r "$CUSTOMIZATION_POINTS_FILE" ] || {
    echo "ownership-check: Liste der Anpassungsstellen nicht lesbar: $CUSTOMIZATION_POINTS_FILE" >&2; exit 2; }
  if ! jq -e '.schema == 1 and (.files | type == "array" and length > 0 and all(.[]; (.path | type == "string") and (.path | length > 0)))' \
      "$LOCK_FILE" >/dev/null 2>&1; then
    echo "ownership-check: factory.lock ungültig (kein JSON, schema ≠ 1 oder keine Pfadeinträge): $LOCK_FILE" >&2
    exit 2
  fi
}

# Legt die normalisierte Liste der Anpassungsstellen in $WORK_DIR/points.txt ab und bricht mit Exit 2 ab, wenn sie keinen Eintrag hat.
# Normalisiert wird (CR, Randleerraum): sonst liefe die Prüfung bei CRLF-Zeilenenden still ins Leere.
lock_load_points() {
  tr -d '\r' < "$CUSTOMIZATION_POINTS_FILE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -vE '^(#|$)' | LC_ALL=C sort -u > "$WORK_DIR/points.txt" || true
  [ -s "$WORK_DIR/points.txt" ] || {
    echo "ownership-check: Liste der Anpassungsstellen ohne Eintrag (fail-closed): $CUSTOMIZATION_POINTS_FILE" >&2; exit 2; }
}

# Legt die sortierten Pfadmengen in $WORK_DIR ab: lock.txt (mit Duplikaten), lock-unique.txt, tracked.txt.
lock_collect_sets() {
  jq -r '.files[].path' "$LOCK_FILE" | LC_ALL=C sort > "$WORK_DIR/lock.txt"
  LC_ALL=C sort -u "$WORK_DIR/lock.txt" > "$WORK_DIR/lock-unique.txt"
  printf '%s\n' "$TRACKED_FILES" | LC_ALL=C sort -u > "$WORK_DIR/tracked.txt"
}

# lock_report_class <meldung>: je Pfad auf stdin eine Zeile `✗ <pfad>: <meldung>` auf stderr; jeder Fund wird in
# $WORK_DIR/findings.txt vermerkt (gezählt wird dort, nicht über Exit-Codes: sie tragen nur 0–255, modulo 256).
lock_report_class() {
  local path
  while IFS= read -r path; do
    echo "✗ $path: $1" >&2
    echo "$path" >> "$WORK_DIR/findings.txt"
  done
}

# Scheitert eine der Vergleichs-Pipelines selbst (z. B. `comm`), ist das ein interner Fehler: Exit 2, nicht „ein Fund“.
lock_internal_error() {
  echo "ownership-check: interner Fehler beim Vergleich der Pfadmengen (fail-closed)" >&2
  exit 2
}

# Meldet alle Funde der drei Klassen; Rückgabe 0 = Lock und Repo passen zusammen, 1 = mindestens ein Fund.
lock_report_problems() {
  : > "$WORK_DIR/findings.txt"
  LC_ALL=C uniq -d "$WORK_DIR/lock.txt" | lock_report_class "mehrfach im Lock" || lock_internal_error
  LC_ALL=C comm -23 "$WORK_DIR/lock-unique.txt" "$WORK_DIR/tracked.txt" \
    | lock_report_class "nicht getrackt (Lock-Pfad ohne Datei im Repo)" || lock_internal_error
  LC_ALL=C comm -12 "$WORK_DIR/lock-unique.txt" "$WORK_DIR/points.txt" \
    | lock_report_class "Anpassungsstelle steht im Lock (gehört dem Projekt, wird nie geliefert)" || lock_internal_error
  local bad; bad="$(grep -c '' "$WORK_DIR/findings.txt")" || bad=0
  [ "$bad" -eq 0 ] && return 0
  echo "ownership-check: $bad Fund(e) im Lock-Modus – factory.lock und Repo-Inhalt passen nicht zusammen." >&2
  return 1
}

# Ausgabe je nach Aufruf: --list factory|project gibt die Pfade aus, sonst Modus- und Ergebniszeile.
lock_print_result() {
  local nf np
  case "$LIST_SIDE" in
    factory) cat "$WORK_DIR/lock-unique.txt" ;;
    project) LC_ALL=C comm -23 "$WORK_DIR/tracked.txt" "$WORK_DIR/lock-unique.txt" ;;
    *) nf="$(grep -c '' "$WORK_DIR/lock-unique.txt")"
       np="$(LC_ALL=C comm -23 "$WORK_DIR/tracked.txt" "$WORK_DIR/lock-unique.txt" | grep -c '')" || np=0
       echo "ownership-check: Modus: Lock ($LOCK_FILE)"
       echo "✓ Zuordnung vollständig und eindeutig: $((nf + np)) Dateien (factory: $nf, project: $np)" ;;
  esac
}

# Legt das Temp-Verzeichnis für die Pfadmengen an und räumt es beim Beenden des Skripts auf. WORK_DIR ist global, weil die EXIT-Trap
# nach dem Ende von lock_mode läuft; angelegt wird es erst NACH den Voraussetzungen, damit fehlendes jq vor jedem anderen Werkzeug greift.
lock_open_workspace() {
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
}

lock_mode() {
  lock_require_inputs
  load_tracked_files
  lock_open_workspace
  lock_load_points
  lock_collect_sets
  lock_report_problems || exit 1
  lock_print_result
}

# Ein hängender Symlink `factory.lock` ist auch ein Lock (-e folgt dem Link und wäre falsch): kein stiller Rückfall in die Tabelle.
if [ -e "$LOCK_FILE" ] || [ -L "$LOCK_FILE" ]; then
  lock_mode
  exit 0
fi

if [ ! -r "$OWNERSHIP_FILE" ]; then
  echo "ownership-check: Zuordnungstabelle nicht lesbar: $OWNERSHIP_FILE" >&2
  exit 2
fi

load_tracked_files

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
