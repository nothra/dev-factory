#!/usr/bin/env bash
# factory-lock.sh – Bibliothek für Abholung und Integritäts-Gate (gesourct, nicht ausgeführt).
#
# Gemeinsame Bausteine von scripts/factory-sync.sh (Abholen) und scripts/checks/factory-integrity-check.sh
# (Gate); Entscheidung: Factory-ADR-063, Nachtrag 2026-10-25 (E1–E8). Stellt bereit:
#   fl_hash_paths <basis>            liest Pfade (eine je Zeile) von stdin, gibt `<sha256><TAB><pfad>` aus
#                                    (ein Hash-Aufruf für alle Dateien; Fehler oder Zählabweichung → Rückgabe 1)
#   fl_validate_manifest <datei> [<repo> [<version>]]
#                                    Manifest bzw. Lock prüfen (JSON, schema 1, Pflichtfelder, Pfadform,
#                                    keine Duplikate; mit Argumenten zusätzlich repo/version); Funde auf stderr
#   fl_protected_findings <datei>    Pfade des Manifests in einem Projektbereich oder an einer Anpassungsstelle
#                                    (`<pfad><TAB><grund>`); Rückgabe 2, wenn die Liste der Anpassungsstellen fehlt
#   fl_manifest_tsv <datei>          Soll-Tabelle `<sha256><TAB><pfad>` (sortiert) aus Manifest/Lock
#   fl_diff_hashes <soll> <ist>      Pfade der Ist-Tabelle, deren Hash nicht der Soll-Tabelle entspricht (je Zeile ein Pfad)
#   fl_upstream_repo                 Quell-Repo aus `upstream.repo` der Config (Slug-geprüft)
#   fl_fetch_manifest <repo> <tag> <ziel>   Manifest des Release-Assets holen (ohne Token)
#   fl_git_url <repo>                Klon-URL des Quell-Repos
# Test-Seams: FACTORY_UPSTREAM_GIT_URL, FACTORY_RELEASE_BASE_URL (beide `file://`-fähig).
#
# Erwartet vom Aufrufer FACTORY_DIR (Projektwurzel, für die Config). Fail-closed: jedes Werkzeug, das fehlt oder
# scheitert, liefert einen Fehlercode – nie ein leeres „alles in Ordnung“.

FL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-config.sh
source "$FL_LIB_DIR/gate-config.sh" || return 1

FL_CUSTOMIZATION_POINTS_FILE="${CUSTOMIZATION_POINTS_FILE:-$FL_LIB_DIR/../checks/customization-points.txt}"
# Verzeichnisse, in die die Factory nie liefert (ADR-063 E6) – bewusst nicht in customization-points.txt (ADR-064 D4).
FL_PROJECT_AREAS="scripts/project/
docs/project/
docs/adr/
docs/specs/
tasks/"
FL_VERSION_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
FL_SLUG_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
FL_TAB="$(printf '\t')"

# Wählt das Hash-Werkzeug (macOS: shasum, Linux: sha256sum); gleiche Reihenfolge wie factory-release-manifest.sh.
fl_pick_hash_tool() {
  if command -v shasum >/dev/null 2>&1; then FL_HASH_CMD=(shasum -a 256)
  elif command -v sha256sum >/dev/null 2>&1; then FL_HASH_CMD=(sha256sum)
  else echo "weder shasum noch sha256sum gefunden" >&2; return 1; fi
}

fl_hash_paths() {
  local base="$1" input out n_in n_out
  input="$(cat)"
  [ -n "$input" ] || return 0
  fl_pick_hash_tool || return 1
  # `./`-Präfix: ein Pfad mit führendem `-` käme sonst als Option beim Hash-Werkzeug an.
  out="$(printf '%s\n' "$input" | sed 's|^|./|' | tr '\n' '\0' | (cd "$base" && xargs -0 "${FL_HASH_CMD[@]}"))" || return 1
  n_in="$(printf '%s\n' "$input" | grep -c '')"
  n_out="$(printf '%s\n' "$out" | grep -c '')"
  [ "$n_in" = "$n_out" ] || return 1
  out="$(printf '%s\n' "$out" | sed -E "s|^([0-9a-f]{64}) [ *]\./(.*)\$|\1${FL_TAB}\2|")"
  # Eine Zeile ohne Hash-Form (z. B. Fehlermeldung des Werkzeugs auf stdout) ist ein Messfehler, kein Treffer.
  [ "$(printf '%s\n' "$out" | grep -cvE "^[0-9a-f]{64}${FL_TAB}")" = 0 ] || return 1
  printf '%s\n' "$out"
}

# Pfade, die nicht relativ-und-sauber sind: absolut, `.`/`..`-Segment, leeres Segment, Backslash, Steuerzeichen.
FL_BAD_PATH_JQ='.files[].path | select(startswith("/") or test("(^|/)\\.\\.?(/|$)") or test("//") or test("/$") or test("\\\\") or test("[[:cntrl:]]") or . == "")'

fl_validate_manifest() {
  local file="$1" repo="${2:-}" version="${3:-}" bad rc=0
  command -v jq >/dev/null 2>&1 || { echo "jq nicht gefunden" >&2; return 1; }
  [ -r "$file" ] || { echo "nicht lesbar: $file" >&2; return 1; }
  jq -e . "$file" >/dev/null 2>&1 || { echo "kein gültiges JSON: $file" >&2; return 1; }
  jq -e '.schema == 1' "$file" >/dev/null 2>&1 || { echo "unbekanntes oder fehlendes schema (erwartet 1): $file" >&2; return 1; }
  jq -e '(.repo | type == "string" and length > 0) and (.version | type == "string" and test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
         and (.commit | type == "string" and test("^[0-9a-f]{40}$"))
         and (.files | type == "array" and length > 0 and all(.[]; (.path | type == "string") and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))))' \
    "$file" >/dev/null 2>&1 || { echo "Pflichtfelder fehlen oder haben die falsche Form (repo, version, commit, files[].path/sha256): $file" >&2; return 1; }
  bad="$(jq -r "$FL_BAD_PATH_JQ" "$file")"
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | sed 's/^/ungültiger Pfad (absolut, mit ..\/Sonderzeichen): /' >&2; rc=1
  fi
  bad="$(jq -r '[.files[].path] | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$file")"
  if [ -n "$bad" ]; then printf '%s\n' "$bad" | sed 's/^/Pfad doppelt: /' >&2; rc=1; fi
  if [ -n "$repo" ] && [ "$(jq -r .repo "$file")" != "$repo" ]; then
    echo "repo im Manifest ($(jq -r .repo "$file")) ≠ Quell-Repo ($repo)" >&2; rc=1
  fi
  if [ -n "$version" ] && [ "$(jq -r .version "$file")" != "$version" ]; then
    echo "version im Manifest ($(jq -r .version "$file")) ≠ angeforderter Tag ($version)" >&2; rc=1
  fi
  return "$rc"
}

fl_manifest_tsv() { jq -r '.files[] | "\(.sha256)\t\(.path)"' "$1" | LC_ALL=C sort; }

fl_diff_hashes() { awk -F'\t' 'NR == FNR { want[$2] = $1; next } want[$2] != $1 { print $2 }' "$1" "$2"; }

fl_protected_findings() {
  local file="$1" points
  [ -r "$FL_CUSTOMIZATION_POINTS_FILE" ] || { echo "Liste der Anpassungsstellen nicht lesbar: $FL_CUSTOMIZATION_POINTS_FILE" >&2; return 2; }
  points="$(tr -d '\r' < "$FL_CUSTOMIZATION_POINTS_FILE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -vE '^(#|$)')"
  [ -n "$points" ] || { echo "Liste der Anpassungsstellen ohne Eintrag (fail-closed)" >&2; return 2; }
  jq -r --arg areas "$FL_PROJECT_AREAS" --arg pts "$points" '
    ($areas | split("\n")) as $A | ($pts | split("\n")) as $P |
    .files[].path as $f |
    if any($A[]; . as $a | $f | startswith($a)) then "\($f)\tProjektbereich"
    elif ($P | index($f)) != null then "\($f)\tAnpassungsstelle"
    else empty end' "$file"
}

fl_upstream_repo() {
  local repo
  repo="$(factory_cfg upstream.repo)" || return 1
  # Die Segmente `.` und `..` passen auf das Zeichenmuster, sind aber kein Repo-Name (die URL liefe aus dem Owner-Pfad hinaus).
  case "/$repo/" in */./*|*/../*) repo="" ;; esac
  printf '%s' "$repo" | grep -qE "$FL_SLUG_RE" || { echo "upstream.repo fehlt oder ist kein <owner>/<repo>-Slug: '$repo'" >&2; return 1; }
  printf '%s' "$repo"
}

fl_fetch_manifest() {
  local repo="$1" tag="$2" dest="$3" base
  command -v curl >/dev/null 2>&1 || { echo "curl nicht gefunden" >&2; return 1; }
  base="${FACTORY_RELEASE_BASE_URL:-https://github.com/$repo/releases/download}"
  curl -fsSL --max-time 60 -o "$dest" "$base/$tag/factory-release.json"
}

fl_git_url() { printf '%s' "${FACTORY_UPSTREAM_GIT_URL:-https://github.com/$1.git}"; }
