#!/usr/bin/env bash
# factory-sync.sh – setzt zusammengesetzte Dateien aus Factory- und Projekt-Fragment zusammen
#
# Verwendung:
#   bash scripts/factory-sync.sh --compose          schreibt .claude/settings.json und .gitignore
#   bash scripts/factory-sync.sh --compose --check  schreibt nichts; exit 1, wenn eine committete
#                                                   Datei von der Zusammensetzung abweicht
#   bash scripts/factory-sync.sh <version> [--adopt] holt die Version <version> (Tag vX.Y.Z) aus dem Factory-Repo:
#                                                   Dateien gegen das Release-Manifest prüfen, atomar übernehmen,
#                                                   zusammengesetzte Dateien neu zusammensetzen, factory.lock schreiben
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
# Abholen (Factory-ADR-063, Nachtrag 2026-10-25 E1–E4), in zwei Phasen:
#   1. Prüfen, im Repo wird nichts geschrieben: Vorbedingung im Arbeitsbaum (mit Lock: lokale Stufe des Integritäts-Gates
#      grün, sonst Abbruch mit Dateiliste; ohne Lock: abweichende Dateien an Manifest-Pfaden nur mit --adopt), Manifest
#      holen und prüfen, Tag klonen (HEAD == commit, jede Datei hat den Manifest-Hash), Zusammensetzen im Temp-Baum.
#   2. Übernehmen mit Backup und Rückbau (trap): neue/geänderte Dateien, entfallene löschen, zusammengesetzte Dateien,
#      zuletzt factory.lock als Byte-Kopie des Manifests.
# --adopt gilt nur für die Erstabholung ohne factory.lock; mit Lock wird er abgelehnt (die Vorbedingung bleibt unumgehbar).
#
# Projektwurzel: FACTORY_DIR (Tests/Override), sonst eine Ebene über scripts/. Test-Seams: FACTORY_UPSTREAM_GIT_URL,
# FACTORY_RELEASE_BASE_URL (scripts/lib/factory-lock.sh).
# Fail-closed: fehlendes Fragment, fehlendes Werkzeug oder ungültige Eingabe → exit 1, nichts geschrieben.

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FACTORY_DIR="$ROOT"

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

# ─── Abholen ─────────────────────────────────────────────────────────────────────────────────────────────────────────

LOCK_TARGET="factory.lock"
FACTORY_MD="docs/factory/FACTORY.md"
INTEGRITY_CHECK="$(dirname "$SELF")/checks/factory-integrity-check.sh"
WORK=""            # Temp-Verzeichnis der Abholung
APPLYING=0         # 1 = Phase 2 läuft, Rückbau bei Abbruch
APPLIED=0          # 1 = Phase 2 vollständig, kein Rückbau mehr

# shellcheck source=lib/factory-lock.sh
source "$(dirname "$SELF")/lib/factory-lock.sh" || die "scripts/lib/factory-lock.sh nicht ladbar (fail-closed)"

# Stellt den Stand vor Phase 2 wieder her: gesicherte Dateien zurück, neu angelegte entfernen.
rollback() {
  local p
  while IFS= read -r p; do
    mkdir -p "$ROOT/$(dirname "$p")" && cp -p "$WORK/backup/$p" "$ROOT/$p"
  done < "$WORK/backed.txt"
  while IFS= read -r p; do
    rm -f "$ROOT/$p"
    (cd "$ROOT" && rmdir -p "$(dirname "$p")" 2>/dev/null)
  done < "$WORK/created.txt"
}

cleanup_pull() {
  if [ "$APPLYING" -eq 1 ] && [ "$APPLIED" -eq 0 ]; then
    echo "✗ factory-sync: Abbruch während der Übernahme – stelle den vorherigen Stand wieder her" >&2
    rollback
  fi
  [ -z "$WORK" ] || rm -rf "$WORK"
}

require_pull_tools() {
  local tool
  for tool in jq git curl yq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool nicht gefunden (fail-closed)"
  done
  fl_pick_hash_tool 2>/dev/null || die "weder shasum noch sha256sum gefunden (fail-closed)"
}

# Ein Pfad im Repo darf nicht über einen Symlink aus dem Repo hinaus schreiben und muss, wenn er existiert, eine reguläre Datei sein.
check_target_path() {
  local p="$1" dir
  dir="$(dirname "$p")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    [ ! -L "$ROOT/$dir" ] || die "Zielverzeichnis ist ein Symlink: $dir (Pfad $p) – Abbruch, nichts geändert"
    dir="$(dirname "$dir")"
  done
  if [ -L "$ROOT/$p" ] || { [ -e "$ROOT/$p" ] && [ ! -f "$ROOT/$p" ]; }; then
    die "Ziel ist keine reguläre Datei: $p – Abbruch, nichts geändert"
  fi
}

# Phase 1a, ohne Lock: Dateien an Manifest-Pfaden mit abweichendem Inhalt sammeln → Liste in $WORK/diverging.txt.
collect_diverging() {
  local path
  : > "$WORK/existing.txt"; : > "$WORK/diverging.txt"
  while IFS= read -r path; do
    check_target_path "$path"
    [ ! -e "$ROOT/$path" ] || printf '%s\n' "$path" >> "$WORK/existing.txt"
  done < "$WORK/manifest-paths.txt"
  fl_hash_paths "$ROOT" < "$WORK/existing.txt" > "$WORK/local.tsv" || die "Hashen der vorhandenen Dateien fehlgeschlagen (fail-closed)"
  fl_manifest_tsv "$WORK/manifest.json" > "$WORK/want.tsv"
  fl_diff_hashes "$WORK/want.tsv" "$WORK/local.tsv" > "$WORK/diverging.txt"
}

# Phase 1a: Vorbedingung im Arbeitsbaum (F2 bzw. AK2.2e) – offline, vor jedem Netzzugriff soweit möglich.
precheck_local_state() {
  local out
  if [ -e "$ROOT/$LOCK_TARGET" ] || [ -L "$ROOT/$LOCK_TARGET" ]; then
    [ -f "$INTEGRITY_CHECK" ] || die "scripts/checks/factory-integrity-check.sh fehlt (fail-closed) – Abholung abgebrochen, nichts geändert"
    if ! out="$(FACTORY_DIR="$ROOT" bash "$INTEGRITY_CHECK" 2>&1)"; then
      printf '%s\n' "$out" >&2
      die "übernommene Dateien lokal geändert oder Lock ungültig – Abholung abgebrochen, nichts geändert. Änderungen gehören nach dem Factory-Repo."
    fi
  fi
}

report_diverging() {
  local path
  if [ "$ADOPT" -eq 0 ]; then
    while IFS= read -r path; do echo "✗ $path: weicht von der Version ab" >&2; done < "$WORK/diverging.txt"
    die "$(grep -c '' "$WORK/diverging.txt") Datei(en) im Repo weichen von der Version ab (kein factory.lock) – mit --adopt überschreiben, nichts geändert"
  fi
  echo "⚠ --adopt: folgende Dateien werden überschrieben:"
  sed 's/^/  - /' "$WORK/diverging.txt"
}

# Phase 1b: Manifest holen und prüfen.
fetch_and_check_manifest() {
  local repo="$1" version="$2" findings rc
  fl_fetch_manifest "$repo" "$version" "$WORK/manifest.json" \
    || die "Release-Manifest zu $version aus $repo nicht abrufbar (Tag ohne Release oder Factory-Repo nicht erreichbar) – nicht eingebunden"
  fl_validate_manifest "$WORK/manifest.json" "$repo" "$version" || die "Release-Manifest zu $version ungültig – Abbruch, nichts geändert"
  findings="$(fl_protected_findings "$WORK/manifest.json")"; rc=$?
  [ "$rc" -eq 0 ] || die "Anpassungsstellen nicht prüfbar (fail-closed)"
  if [ -n "$findings" ]; then
    printf '%s\n' "$findings" | sed 's/^/✗ /; s/\t/: liefert eine geschützte Stelle (/; s/$/)/' >&2
    die "Manifest würde Projektbesitz überschreiben – abgelehnt, nichts geändert"
  fi
  jq -r '.files[].path' "$WORK/manifest.json" > "$WORK/manifest-paths.txt"
}

# Phase 1c: Tag klonen, HEAD == commit, jede Datei mit Manifest-Hash.
clone_and_verify() {
  local repo="$1" version="$2" commit path mism
  git clone --quiet --depth 1 --branch "$version" -- "$(fl_git_url "$repo")" "$WORK/clone" >/dev/null 2>"$WORK/clone.err" \
    || die "Tag $version aus $repo nicht klonbar (Netz oder Tag fehlt) – nichts geändert"
  commit="$(jq -r .commit "$WORK/manifest.json")"
  [ "$(git -C "$WORK/clone" rev-parse HEAD 2>/dev/null)" = "$commit" ] \
    || die "Tag $version zeigt nicht auf den Commit des Manifests ($commit) – Abbruch, nichts geändert"
  while IFS= read -r path; do
    { [ -f "$WORK/clone/$path" ] && [ ! -L "$WORK/clone/$path" ]; } || die "Datei aus dem Manifest fehlt im Tag oder ist kein regulärer Eintrag: $path"
  done < "$WORK/manifest-paths.txt"
  fl_hash_paths "$WORK/clone" < "$WORK/manifest-paths.txt" > "$WORK/clone.tsv" || die "Hashen der heruntergeladenen Dateien fehlgeschlagen (fail-closed)"
  fl_manifest_tsv "$WORK/manifest.json" > "$WORK/want.tsv"
  mism="$(fl_diff_hashes "$WORK/want.tsv" "$WORK/clone.tsv")"
  if [ -n "$mism" ]; then
    printf '%s\n' "$mism" | sed 's/^/✗ Hash weicht vom Manifest ab: /' >&2
    die "heruntergeladene Dateien stimmen nicht mit dem Release-Manifest überein – Abbruch, nichts geändert"
  fi
  if grep -qxF "$FACTORY_MD" "$WORK/manifest-paths.txt"; then
    [ "$(head -1 "$WORK/clone/$FACTORY_MD" | sed -nE 's/^# Development Factory · (v[0-9]+\.[0-9]+\.[0-9]+)$/\1/p')" = "$version" ] \
      || die "Versionszeile in $FACTORY_MD nennt nicht $version – Abbruch, nichts geändert"
  fi
}

# Phase 1d: zusammengesetzte Dateien im Temp-Baum aus neuem Factory-Fragment und aktuellen Projekt-Fragmenten.
compose_in_stage() {
  local frag src
  mkdir -p "$WORK/stage/.claude" "$WORK/stage/docs/factory"
  for frag in "$SETTINGS_FACTORY" "$GITIGNORE_FACTORY"; do
    src="$ROOT/$frag"
    if grep -qxF "$frag" "$WORK/manifest-paths.txt"; then src="$WORK/clone/$frag"; fi
    cp "$src" "$WORK/stage/$frag" 2>/dev/null || die "Factory-Fragment fehlt: $frag (weder im Manifest noch im Repo)"
  done
  cp "$ROOT/$SETTINGS_PROJECT" "$WORK/stage/$SETTINGS_PROJECT" 2>/dev/null || die "Projekt-Fragment fehlt: $SETTINGS_PROJECT"
  cp "$ROOT/$GITIGNORE_PROJECT" "$WORK/stage/$GITIGNORE_PROJECT" 2>/dev/null || die "Projekt-Fragment fehlt: $GITIGNORE_PROJECT"
  FACTORY_DIR="$WORK/stage" bash "$SELF" --compose >/dev/null || die "Zusammensetzen im Temp-Baum fehlgeschlagen – Abbruch, nichts geändert"
}

# Phase 2: Sicherung einer Zieldatei (vorhanden → Backup, sonst als neu angelegt vermerkt).
backup_target() {
  local p="$1"
  if [ -e "$ROOT/$p" ] || [ -L "$ROOT/$p" ]; then
    mkdir -p "$WORK/backup/$(dirname "$p")" && cp -p "$ROOT/$p" "$WORK/backup/$p" || die "Sicherung von $p fehlgeschlagen – Abbruch, nichts geändert"
    printf '%s\n' "$p" >> "$WORK/backed.txt"
  else
    printf '%s\n' "$p" >> "$WORK/created.txt"
  fi
}

install_file() { # $1 = Quelldatei, $2 = Pfad im Repo
  mkdir -p "$ROOT/$(dirname "$2")" && cp -p "$1" "$ROOT/$2" || die "Schreiben von $2 fehlgeschlagen"
}

apply_version() {
  local path removed=0
  : > "$WORK/backed.txt"; : > "$WORK/created.txt"
  if [ -e "$ROOT/$LOCK_TARGET" ]; then
    jq -r '.files[].path' "$ROOT/$LOCK_TARGET" | LC_ALL=C sort > "$WORK/old-paths.txt"
  else
    : > "$WORK/old-paths.txt"
  fi
  LC_ALL=C sort "$WORK/manifest-paths.txt" > "$WORK/new-sorted.txt"
  LC_ALL=C comm -23 "$WORK/old-paths.txt" "$WORK/new-sorted.txt" > "$WORK/removed.txt"
  while IFS= read -r path; do check_target_path "$path"; done < "$WORK/removed.txt"
  while IFS= read -r path; do backup_target "$path"; done < "$WORK/manifest-paths.txt"
  while IFS= read -r path; do backup_target "$path"; done < "$WORK/removed.txt"
  # Die Ziele außerhalb des Manifests (zusammengesetzte Dateien, Lock) werden geschrieben, also gilt dieselbe Pfadprüfung.
  for path in "$SETTINGS_TARGET" "$GITIGNORE_TARGET" "$LOCK_TARGET"; do check_target_path "$path"; backup_target "$path"; done

  APPLYING=1
  while IFS= read -r path; do install_file "$WORK/clone/$path" "$path"; done < "$WORK/manifest-paths.txt"
  while IFS= read -r path; do rm -f "$ROOT/$path" || die "Löschen von $path fehlgeschlagen"; removed=$((removed + 1)); done < "$WORK/removed.txt"
  install_file "$WORK/stage/$SETTINGS_TARGET" "$SETTINGS_TARGET"
  install_file "$WORK/stage/$GITIGNORE_TARGET" "$GITIGNORE_TARGET"
  FACTORY_DIR="$ROOT" bash "$SELF" --compose --check >/dev/null || die "zusammengesetzte Dateien entsprechen nach der Übernahme nicht den Fragmenten"
  install_file "$WORK/manifest.json" "$LOCK_TARGET"
  APPLIED=1
  printf '%s' "$removed" > "$WORK/removed-count.txt"
}

run_pull() {
  local version="$1" repo path
  [ "$ADOPT" -eq 0 ] || { [ ! -e "$ROOT/$LOCK_TARGET" ] && [ ! -L "$ROOT/$LOCK_TARGET" ]; } \
    || die "--adopt ist nur für die Erstabholung ohne factory.lock zulässig (lokale Änderungen werden nie überschrieben)"
  require_pull_tools
  repo="$(fl_upstream_repo)" || die "Quell-Repo nicht ermittelbar (upstream.repo, fail-closed)"
  WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"
  trap cleanup_pull EXIT
  trap 'exit 130' INT TERM

  precheck_local_state
  fetch_and_check_manifest "$repo" "$version"
  if [ ! -e "$ROOT/$LOCK_TARGET" ] && [ ! -L "$ROOT/$LOCK_TARGET" ]; then
    collect_diverging
    [ ! -s "$WORK/diverging.txt" ] || report_diverging
  else
    while IFS= read -r path; do check_target_path "$path"; done < "$WORK/manifest-paths.txt"
  fi
  clone_and_verify "$repo" "$version"
  compose_in_stage
  apply_version
  echo "✓ Factory $version abgeholt: $(grep -c '' "$WORK/manifest-paths.txt") Dateien übernommen, $(cat "$WORK/removed-count.txt") entfallene gelöscht, factory.lock geschrieben"
}

# ─── Aufruf ──────────────────────────────────────────────────────────────────────────────────────────────────────────

USAGE="Verwendung: --compose [--check]  |  <version> [--adopt]"
compose=0 check=0 ADOPT=0 version=""
for arg in "$@"; do
  case "$arg" in
    --compose) compose=1 ;;
    --check) check=1 ;;
    --adopt) ADOPT=1 ;;
    -*) die "unbekanntes Argument: $arg ($USAGE)" ;;
    *) [ -z "$version" ] || die "mehr als eine Version angegeben ($USAGE)"; version="$arg" ;;
  esac
done

if [ -n "$version" ]; then
  # Vor jedem Netzzugriff: nur eine Version der Form vX.Y.Z erreicht git/curl (kein Wert, der als Option gelesen wird).
  printf '%s' "$version" | grep -qE "$FL_VERSION_RE" || die "Version muss die Form vX.Y.Z haben: $version"
  [ "$compose" -eq 0 ] && [ "$check" -eq 0 ] || die "--compose/--check und <version> schließen sich aus ($USAGE)"
  cd "$ROOT" 2>/dev/null || die "Projektwurzel nicht erreichbar: $ROOT"
  run_pull "$version"
  exit 0
fi

[ "$ADOPT" -eq 0 ] || die "--adopt gehört zu einer Version ($USAGE)"
[ "$compose" -eq 1 ] || die "kein Modus angegeben ($USAGE)"
[ "$check" -eq 0 ] || [ "$compose" -eq 1 ] || die "--check gehört zu --compose"

cd "$ROOT" 2>/dev/null || die "Projektwurzel nicht erreichbar: $ROOT"
require_inputs
run_compose "$check"
