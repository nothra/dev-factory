#!/usr/bin/env bash
# run-tests.sh (Projekt-Suite) – Prüfungen, die den Zustand des Factory-Repos selbst voraussetzen
#
# Verwendung: bash scripts/project/tests/run-tests.sh
# Exit-Code 0 = alle Tests grün, 1 = mindestens ein Test rot.
#
# Diese Suite gehört dem Repo (Seite `project` in docs/factory/OWNERSHIP.md) und wird nicht ausgeliefert. Die
# ausgelieferte Suite `scripts/checks/tests/run-tests.sh` ist konsumenten-neutral (Factory-ADR-064 D6); alles, was
# `ci.yml`, `release.yml`, `OWNERSHIP.md` oder den Release-Stand dieses Repos liest, läuft nur hier.
# Aufruf im Repo: lokal über scripts/project/checks/pre-push.d/, in CI über einen Job in ci.yml.

set -uo pipefail

PROJECT_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_ROOT="$(cd "$PROJECT_TESTS_DIR/../../.." && pwd)"
CHECKS_DIR="$FACTORY_ROOT/scripts/checks"

# Geteilte Helfer (Zähler, assert_*, print_summary) – relativ zum Skript gesourct, nicht zu FACTORY_DIR (nothra/tch-gastro-services#431)
source "$CHECKS_DIR/tests/lib/assert-helpers.sh"

# ─── Factory-Issue #22 · Anpassungsstellen-Liste gegen OWNERSHIP.md und PROJECT-CONTEXT.md (AK2.15b-2, AK2.15d-0) ───
# Die Liste (scripts/checks/customization-points.txt, Seite `factory`) ist eine TEILMENGE der `project`-Zeilen der
# Tabelle (ADR-064 D4): `tasks/**`, `docs/specs/**` sind `project`, aber keine Anpassungsstellen. Der Guard prüft darum
# beide Richtungen einzeln: (1) jeder Eintrag steht laut Tabelle auf Seite `project`, (2) jede in PROJECT-CONTEXT.md
# unter „Eigene Anpassungsstellen" genannte Datei steht in der Liste.
echo "Anpassungsstellen-Liste (Drift-Guard):"

# points_drift_22 <liste> <tabelle> <kontext> → gibt je Verstoß eine Zeile `✗ <pfad>: …` aus, Exit 1 bei Verstoß,
# Exit 2 bei nicht lesbarer Quelle (fail-closed, nie „kein Verstoß" aus einer fehlenden Datei).
points_drift_22() {
  local points="$1" table="$2" context="$3" f wrong=0 work entry named
  for f in "$points" "$table" "$context"; do
    [ -r "$f" ] || { echo "✗ Quelle nicht lesbar: $f"; return 2; }
  done
  work="$(mktemp -d)"
  grep -vE '^[[:space:]]*(#|$)' "$points" > "$work/entries.txt"
  [ -s "$work/entries.txt" ] || { echo "✗ Liste ohne Einträge: $points"; rm -rf "$work"; return 2; }
  # Richtung 1: Seite `project` laut Tabelle (Tabellenmodus erzwingen: kein Lock)
  FACTORY_LOCK_FILE=/nicht/vorhanden/factory.lock OWNERSHIP_FILE="$table" OWNERSHIP_FILE_LIST="$work/entries.txt" \
    bash "$CHECKS_DIR/ownership-check.sh" --list project > "$work/project-side.txt" 2>/dev/null || true
  while IFS= read -r entry; do
    grep -qxF -- "$entry" "$work/project-side.txt" || { echo "✗ $entry: Anpassungsstelle steht in OWNERSHIP.md nicht auf Seite project"; wrong=1; }
  done < "$work/entries.txt"
  # Richtung 2: jede in PROJECT-CONTEXT.md genannte Anpassungsstelle (Backtick-Pfade des Aufzählungspunkts) steht in der Liste
  named="$(awk '/^- \*\*Eigene Anpassungsstellen\*\*/ {on = 1; print; next} on && /^- \*\*/ {exit} on {print}' "$context" \
    | grep -o '`[^`]*`' | tr -d '`' | grep -vx 'project' || true)"
  [ -n "$named" ] || { echo "✗ keine Anpassungsstellen in $context gefunden"; rm -rf "$work"; return 2; }
  while IFS= read -r entry; do
    grep -qxF -- "$entry" "$work/entries.txt" || { echo "✗ $entry: in PROJECT-CONTEXT.md genannt, fehlt in customization-points.txt"; wrong=1; }
  done <<< "$named"
  rm -rf "$work"
  return "$wrong"
}

POINTS_22="$CHECKS_DIR/customization-points.txt"
TABLE_22="$FACTORY_ROOT/docs/factory/OWNERSHIP.md"
CONTEXT_22="$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md"

# AK2.15b-2: gegen die ECHTEN Dateien (kein Fixture)
out_22="$(points_drift_22 "$POINTS_22" "$TABLE_22" "$CONTEXT_22")"
assert_exit 0 $? "#22 AK2.15b-2: Liste, OWNERSHIP.md und PROJECT-CONTEXT.md sind in beiden Richtungen deckungsgleich"
[ -z "$out_22" ] || echo "$out_22" | head -10 | sed 's/^/      /'

# AK2.15b-2: Mindestinhalt der Liste (Stand PROJECT-CONTEXT „Eigene Anpassungsstellen")
for p_22 in CLAUDE.md factory.config.yml docs/factory/PROJECT-CONTEXT.md README.md CHANGELOG.md \
    .claude/settings.project.json .gitignore.project .github/workflows/ci.yml .github/workflows/release.yml; do
  grep -qxF -- "$p_22" "$POINTS_22"
  assert_exit 0 $? "#22 AK2.15b-2: $p_22 steht in der Anpassungsstellen-Liste"
done
# Kontrolle: die Liste ist eine Teilmenge – project-Zeilen wie tasks/** sind KEINE Anpassungsstellen
assert_true "$(grep -qE '^(tasks|docs/specs)/' "$POINTS_22"; echo $(( $? == 0 )))" \
  "#22 AK2.15b-2 (Kontrolle): tasks/** und docs/specs/** stehen nicht in der Liste (Teilmenge, nicht Gesamtheit)"

# Richtung 1 gebrochen: Eintrag in der Tabelle auf `factory` gesetzt → Guard nennt genau diesen Pfad
dir_22="$(mktemp -d)"
sed 's#^| project | `README.md` |#| factory | `README.md` |#' "$TABLE_22" > "$dir_22/OWNERSHIP.md"
assert_true "$(cmp -s "$TABLE_22" "$dir_22/OWNERSHIP.md"; echo $(( $? == 0 )))" "#22 AK2.15b-2 (Kontrolle): die Mutation der Tabelle hat gewirkt"
out_22="$(points_drift_22 "$POINTS_22" "$dir_22/OWNERSHIP.md" "$CONTEXT_22")"
assert_exit 1 $? "#22 AK2.15b-2: Eintrag der Liste auf factory gesetzt → Guard rot"
assert_contains_286 "$out_22" 'README.md: Anpassungsstelle steht in OWNERSHIP.md nicht auf Seite project' \
  "#22 AK2.15b-2: Richtung 1 nennt den betroffenen Pfad"
assert_absent "$out_22" 'fehlt in customization-points.txt' "#22 AK2.15b-2: Richtung 1 löst nicht das Signal von Richtung 2 aus"

# Richtung 2 gebrochen: Anpassungsstelle aus der Liste gestrichen → Guard nennt genau diesen Pfad
grep -vxF 'CHANGELOG.md' "$POINTS_22" > "$dir_22/points.txt"
out_22="$(points_drift_22 "$dir_22/points.txt" "$TABLE_22" "$CONTEXT_22")"
assert_exit 1 $? "#22 AK2.15b-2: Anpassungsstelle aus der Liste gestrichen → Guard rot"
assert_contains_286 "$out_22" 'CHANGELOG.md: in PROJECT-CONTEXT.md genannt, fehlt in customization-points.txt' \
  "#22 AK2.15b-2: Richtung 2 nennt den betroffenen Pfad"
assert_absent "$out_22" 'nicht auf Seite project' "#22 AK2.15b-2: Richtung 2 löst nicht das Signal von Richtung 1 aus"

# Fail-closed: fehlende Quelle → Exit 2, nicht „kein Verstoß"
points_drift_22 "$dir_22/fehlt.txt" "$TABLE_22" "$CONTEXT_22" > /dev/null
assert_exit 2 $? "#22 AK2.15b-2: fehlende Liste → Exit 2"
points_drift_22 "$POINTS_22" "$dir_22/fehlt.md" "$CONTEXT_22" > /dev/null
assert_exit 2 $? "#22 AK2.15b-2: fehlende Tabelle → Exit 2"
points_drift_22 "$POINTS_22" "$TABLE_22" "$dir_22/fehlt.md" > /dev/null
assert_exit 2 $? "#22 AK2.15b-2: fehlender Projekt-Kontext → Exit 2"
rm -rf "$dir_22"

# AK2.15d-0: OWNERSHIP.md gehört dem Repo – nicht Teil des Release-Manifests (Seite `factory`)
own_side_22() { local l; l="$(OWNERSHIP_FILE="$TABLE_22" FACTORY_LOCK_FILE=/nicht/vorhanden/factory.lock bash "$CHECKS_DIR/ownership-check.sh" --list "$1" 2>/dev/null)"; grep -qxF -- "$2" <<< "$l"; }
own_side_22 project docs/factory/OWNERSHIP.md
assert_exit 0 $? "#22 AK2.15d-0: docs/factory/OWNERSHIP.md steht auf Seite project"
own_side_22 factory docs/factory/OWNERSHIP.md
assert_exit 1 $? "#22 AK2.15d-0: docs/factory/OWNERSHIP.md steht nicht auf Seite factory (nicht im Release-Manifest)"
# AK2.16b-3: der Projekt-Test-Ordner trägt keine factory-Zeile
own_side_22 factory scripts/project/tests/run-tests.sh
assert_exit 1 $? "#22 AK2.16b-3: scripts/project/tests/run-tests.sh steht nicht auf Seite factory"
own_side_22 project scripts/project/tests/run-tests.sh
assert_exit 0 $? "#22 AK2.16b-3: scripts/project/tests/run-tests.sh steht auf Seite project"

# ─── Ergebnis ────────────────────────────────────────────────────────────────
print_summary
