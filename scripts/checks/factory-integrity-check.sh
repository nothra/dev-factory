#!/usr/bin/env bash
# factory-integrity-check.sh – übernommene Factory-Dateien sind unverändert (Factory-ADR-063 D4, Nachtrag E8)
#
# Verwendung:
#   bash scripts/checks/factory-integrity-check.sh         # lokale Stufe (offline): pre-commit, pre-push
#   bash scripts/checks/factory-integrity-check.sh --ci    # zusätzlich: Lock gegen das Release-Manifest des Tags (CI-Job `factory-integrity`)
#
# Moduswahl: Existiert `factory.lock` (`-e` oder `-L`: ein hängender Symlink ist ein Lock, kein „kein Lock“), wird geprüft;
# sonst ist das Skript ein No-op mit Hinweis (Factory-Repo selbst), Exit 0.
#
# Lokale Stufe: Der Lock ist gültig; jede Lock-Datei existiert, ist eine reguläre Datei und hat den eingetragenen
# SHA-256 (ein Hash-Aufruf für alle Dateien); `factory-sync.sh --compose --check` ist grün (zusammengesetzte Dateien
# entsprechen den Fragmenten). Die Stufe braucht nur jq und ein Hash-Werkzeug – kein Netz.
# `--ci`: dazu das Manifest von `lock.version` aus `upstream.repo` holen und mit dem Lock vergleichen (ganzes Dokument,
# mit `jq -S .` normalisiert). Das fängt auch eine Änderung von Datei UND Hash im Lock. Der Lock gilt nie als Quelle des
# Repos: `lock.repo` muss `upstream.repo` gleichen, sonst ließe ein PR den Lock auf ein anderes Repo zeigen.
#
# Umgebung (Tests): FACTORY_DIR (Projektwurzel), FACTORY_LOCK_FILE, FACTORY_UPSTREAM_GIT_URL/FACTORY_RELEASE_BASE_URL (Lib).
# Exit: 0 = ok bzw. No-op, 1 = Abweichung (jede Datei namentlich), 2 = Umgebungs-/Netzfehler oder ungültiger Lock (fail-closed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_DIR="${FACTORY_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
LOCK_FILE="${FACTORY_LOCK_FILE:-$FACTORY_DIR/factory.lock}"
SYNC_SCRIPT="$SCRIPT_DIR/../factory-sync.sh"
UPSTREAM_NAME="nothra/dev-factory"

# shellcheck source=../lib/factory-lock.sh
source "$SCRIPT_DIR/../lib/factory-lock.sh" || { echo "factory-integrity: Lib scripts/lib/factory-lock.sh nicht ladbar (fail-closed)" >&2; exit 2; }

CI_MODE=0
case "${1:-}" in
  "") ;;
  --ci) CI_MODE=1 ;;
  *) echo "factory-integrity: unbekannter Parameter: $1 (Verwendung: [--ci])" >&2; exit 2 ;;
esac

if [ ! -e "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ]; then
  echo "factory-integrity: kein factory.lock – nichts zu prüfen (Factory-Repo selbst bzw. Projekt ohne Einbindung)"
  exit 0
fi

WORK_DIR="$(mktemp -d)" || { echo "factory-integrity: mktemp fehlgeschlagen" >&2; exit 2; }
trap 'rm -rf "$WORK_DIR"' EXIT
FINDINGS=0   # Abweichungen (Exit 1)

fail_env() { echo "factory-integrity: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || fail_env "jq nicht gefunden (fail-closed)"
[ -r "$LOCK_FILE" ] || fail_env "factory.lock nicht lesbar: $LOCK_FILE"
fl_validate_manifest "$LOCK_FILE" 2>"$WORK_DIR/lock-errors.txt" \
  || { sed 's/^/  /' "$WORK_DIR/lock-errors.txt" >&2; fail_env "factory.lock ungültig (fail-closed): $LOCK_FILE"; }

report() { echo "✗ $1: $2"; FINDINGS=$((FINDINGS + 1)); }

# Lokale Stufe, Teil 1: Existenz, Dateityp, Hash. Ergebnis je Datei namentlich.
check_files() {
  local path
  jq -r '.files[] | "\(.sha256)\t\(.path)"' "$LOCK_FILE" | LC_ALL=C sort > "$WORK_DIR/lock.tsv"
  : > "$WORK_DIR/existing.txt"
  while IFS= read -r path; do
    if [ -L "$FACTORY_DIR/$path" ] || { [ -e "$FACTORY_DIR/$path" ] && [ ! -f "$FACTORY_DIR/$path" ]; }; then
      report "$path" "keine reguläre Datei"
    elif [ ! -e "$FACTORY_DIR/$path" ]; then
      report "$path" "gelöscht"
    else
      printf '%s\n' "$path" >> "$WORK_DIR/existing.txt"
    fi
  done < <(jq -r '.files[].path' "$LOCK_FILE")
  fl_hash_paths "$FACTORY_DIR" < "$WORK_DIR/existing.txt" > "$WORK_DIR/actual.tsv" \
    || fail_env "Hashen der Dateien fehlgeschlagen (Hash-Werkzeug fehlt oder scheitert, fail-closed)"
  while IFS= read -r path; do
    report "$path" "geändert (Hash weicht vom Lock ab)"
  done < <(awk -F'\t' 'NR == FNR { want[$2] = $1; next } want[$2] != $1 { print $2 }' "$WORK_DIR/lock.tsv" "$WORK_DIR/actual.tsv")
}

# Lokale Stufe, Teil 2: zusammengesetzte Dateien == Zusammensetzung der Fragmente (AK-28b).
check_composed() {
  local out
  [ -f "$SYNC_SCRIPT" ] || fail_env "scripts/factory-sync.sh fehlt (fail-closed)"
  if ! out="$(FACTORY_DIR="$FACTORY_DIR" bash "$SYNC_SCRIPT" --compose --check 2>&1)"; then
    printf '%s\n' "$out"
    FINDINGS=$((FINDINGS + 1))
  fi
}

# CI-Stufe: Lock == Release-Manifest des Tags aus dem Quell-Repo.
check_manifest() {
  local repo version lock_repo
  command -v yq >/dev/null 2>&1 || fail_env "yq nicht gefunden – nötig für upstream.repo (CI: scripts/install-yq.sh)"
  repo="$(FACTORY_DIR="$FACTORY_DIR" fl_upstream_repo)" || fail_env "upstream.repo nicht ermittelbar (fail-closed)"
  lock_repo="$(jq -r .repo "$LOCK_FILE")"
  if [ "$lock_repo" != "$repo" ]; then
    report "factory.lock" "repo ($lock_repo) ≠ upstream.repo ($repo)"
    return 0
  fi
  version="$(jq -r .version "$LOCK_FILE")"
  fl_fetch_manifest "$repo" "$version" "$WORK_DIR/manifest.json" \
    || fail_env "Release-Manifest zu $version aus $repo nicht abrufbar (Netz, Tag oder Release fehlt) – CI-Stufe fail-closed"
  fl_validate_manifest "$WORK_DIR/manifest.json" "$repo" "$version" 2>"$WORK_DIR/manifest-errors.txt" \
    || { sed 's/^/  /' "$WORK_DIR/manifest-errors.txt" >&2; fail_env "Release-Manifest zu $version ungültig (fail-closed)"; }
  if [ "$(jq -S . "$LOCK_FILE")" != "$(jq -S . "$WORK_DIR/manifest.json")" ]; then
    report "factory.lock" "weicht vom Release-Manifest von $version ab (Lock von Hand geändert?)"
  fi
}

check_files
check_composed
[ "$CI_MODE" -eq 0 ] || check_manifest

if [ "$FINDINGS" -gt 0 ]; then
  echo "factory-integrity: $FINDINGS Abweichung(en). Übernommene Dateien gehören der Factory – Änderung gehört nach $UPSTREAM_NAME," \
       "danach per 'bash scripts/factory-sync.sh <version>' abholen." >&2
  exit 1
fi
stage="lokale Stufe"; [ "$CI_MODE" -eq 0 ] || stage="CI-Stufe inkl. Manifest-Abgleich"
echo "✓ factory-integrity: $(jq -r '.files | length' "$LOCK_FILE") übernommene Dateien unverändert ($(jq -r .version "$LOCK_FILE"), $stage)"
