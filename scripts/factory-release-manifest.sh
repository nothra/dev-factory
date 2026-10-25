#!/usr/bin/env bash
# factory-release-manifest.sh – Release-Manifest factory-release.json erzeugen (Factory-ADR-063 Q1)
#
# Verwendung: bash scripts/factory-release-manifest.sh <ref>     # Manifest (JSON) nach stdout
#
# Das Manifest ist der Vertrag für adoptierende Projekte (Integritäts-Gate in factory-sync.sh):
#   {"schema":1,"repo":"nothra/dev-factory","version":"vX.Y.Z","commit":"<40 hex>",
#    "files":[{"path":"…","sha256":"…"}]}
# `files` = Seite `factory` laut docs/factory/OWNERSHIP.md AM <ref>, nach Pfad sortiert (LC_ALL=C); der Hash
# stammt aus dem Blob am <ref> (`git show <ref>:<pfad>`), nie aus dem Arbeitsbaum. `version` ist der Name von <ref>
# (der Tag). Die Zuordnung liest dasselbe Skript wie das lokale Gate (scripts/checks/ownership-check.sh) – ein Parser.
#
# Umgebung: FACTORY_DIR (Repo-Wurzel, Default: eine Ebene über scripts/).
# Fail-closed: Exit 2 bei fehlender/unbekannter Referenz, fehlender Zuordnungstabelle am <ref>, leerer Dateiliste
# oder fehlendem jq/Hash-Werkzeug.

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_SLUG="nothra/dev-factory"

die() { echo "factory-release-manifest: $*" >&2; exit 2; }

REF="${1:-}"
[ -n "$REF" ] || die "Verwendung: factory-release-manifest.sh <ref>"
command -v jq >/dev/null 2>&1 || die "jq nicht gefunden"
if command -v shasum >/dev/null 2>&1; then HASH_CMD=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then HASH_CMD=(sha256sum)
else die "weder shasum noch sha256sum gefunden"; fi

COMMIT="$(git -C "$FACTORY_DIR" rev-parse --verify --quiet "${REF}^{commit}")" || die "Referenz nicht auflösbar: $REF"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git -C "$FACTORY_DIR" show "$COMMIT:docs/factory/OWNERSHIP.md" > "$WORK/OWNERSHIP.md" 2>/dev/null \
  || die "docs/factory/OWNERSHIP.md fehlt am Stand $REF"
git -C "$FACTORY_DIR" ls-tree -r --name-only "$COMMIT" > "$WORK/tracked.txt" || die "Dateiliste am Stand $REF nicht ermittelbar"

# Die Tabelle AM <ref> gilt, nicht ein factory.lock im Arbeitsbaum (ownership-check.sh wählt den Modus nach dem Arbeitsbaum):
# FACTORY_LOCK_FILE zeigt deshalb auf einen Pfad, den es nicht gibt, und erzwingt den Tabellenmodus.
FILES="$(FACTORY_LOCK_FILE="$WORK/kein-lock" OWNERSHIP_FILE="$WORK/OWNERSHIP.md" OWNERSHIP_FILE_LIST="$WORK/tracked.txt" FACTORY_DIR="$FACTORY_DIR" \
  bash "$FACTORY_DIR/scripts/checks/ownership-check.sh" --list factory | LC_ALL=C sort)" \
  || die "Zuordnung am Stand $REF nicht auswertbar"
[ -n "$FILES" ] || die "keine Dateien der Seite factory am Stand $REF (fail-closed)"

while IFS= read -r path; do
  sha="$(git -C "$FACTORY_DIR" show "$COMMIT:$path" | "${HASH_CMD[@]}" | cut -d' ' -f1)"
  printf '%s\t%s\n' "$path" "$sha"
done <<< "$FILES" > "$WORK/hashes.tsv"

jq -n --arg repo "$REPO_SLUG" --arg version "$REF" --arg commit "$COMMIT" --rawfile tsv "$WORK/hashes.tsv" \
  '{schema: 1, repo: $repo, version: $version, commit: $commit,
    files: ($tsv | split("\n") | map(select(length > 0) | split("\t") | {path: .[0], sha256: .[1]}))}'
