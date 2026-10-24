#!/usr/bin/env bash
# factory-release-check.sh – Voraussetzungen eines Releases prüfen (Factory-ADR-063 D6, Q1)
#
# Verwendung:
#   bash scripts/factory-release-check.sh <tag>          # Version in FACTORY.md == Tag und CHANGELOG-Abschnitt zum Tag
#   bash scripts/factory-release-check.sh --notes <tag>  # den CHANGELOG-Abschnitt zum Tag ausgeben (Release Notes)
#
# Der Tag hat die Form vX.Y.Z. Die Versionsangabe steht in der ersten Zeile von docs/factory/FACTORY.md
# (`# Development Factory · vX.Y.Z`); der CHANGELOG-Abschnitt beginnt mit `## vX.Y.Z` und endet vor der
# nächsten `## `-Überschrift. release.yml ruft das Skript vor dem Anlegen des Release auf: weicht etwas ab,
# entsteht kein Release (der Tag wird gelöscht und neu gesetzt).
#
# Umgebung: FACTORY_DIR (Repo-Wurzel, Default: eine Ebene über scripts/).
# Exit: 0 = ok, 1 = Abweichung (Version oder CHANGELOG), 2 = Aufruf-/Umgebungsfehler (fail-closed).

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FACTORY_MD="$FACTORY_DIR/docs/factory/FACTORY.md"
CHANGELOG="$FACTORY_DIR/CHANGELOG.md"

die() { local code="$1"; shift; echo "factory-release-check: $*" >&2; exit "$code"; }

MODE=check
if [ "${1:-}" = "--notes" ]; then MODE=notes; shift; fi
TAG="${1:-}"
[ -n "$TAG" ] || die 2 "Verwendung: factory-release-check.sh [--notes] <tag>"
printf '%s' "$TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' || die 2 "Tag muss die Form vX.Y.Z haben: $TAG"
[ -r "$CHANGELOG" ] || die 2 "CHANGELOG.md nicht lesbar: $CHANGELOG"

# changelog_section <tag> – Abschnittsinhalt ohne Überschrift; leer, wenn der Abschnitt fehlt.
changelog_section() {
  awk -v h="## $1" '
    index($0, h) == 1 && (length($0) == length(h) || substr($0, length(h) + 1, 1) == " ") { found = 1; next }
    found && index($0, "## ") == 1 { exit }
    found { print }
  ' "$CHANGELOG"
}
has_section() { grep -qE "^## $1( |\$)" "$CHANGELOG"; }

if [ "$MODE" = notes ]; then
  has_section "$TAG" || die 1 "CHANGELOG.md hat keinen Abschnitt zu $TAG"
  changelog_section "$TAG"
  exit 0
fi

[ -r "$FACTORY_MD" ] || die 2 "FACTORY.md nicht lesbar: $FACTORY_MD"
VERSION="$(head -1 "$FACTORY_MD" | sed -nE 's/^# Development Factory · (v[0-9]+\.[0-9]+\.[0-9]+)$/\1/p')"
[ -n "$VERSION" ] || die 2 "keine Versionsangabe in der ersten Zeile von FACTORY.md"
[ "$VERSION" = "$TAG" ] || die 1 "Version in FACTORY.md ($VERSION) stimmt nicht mit dem Tag ($TAG) überein"
has_section "$TAG" || die 1 "CHANGELOG.md hat keinen Abschnitt zu $TAG"
echo "factory-release-check: $TAG ok (FACTORY.md-Version und CHANGELOG-Abschnitt stimmen)"
