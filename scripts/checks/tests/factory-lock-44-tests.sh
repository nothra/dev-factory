#!/usr/bin/env bash
# factory-lock-44-tests.sh – Testgruppe Factory-Issue #44: eine neue Factory-Lesson erreicht einen Konsumenten per factory-sync.sh
# samt „Laden bei“-Trigger (Übersichtszeile in FACTORY.md + Gruppe in lessons/INDEX.md); die Anpassungsstellen bleiben byte-gleich.
# Negativkontrolle: der alte Weg (Trigger in PROJECT-CONTEXT.md, einer Anpassungsstelle) liefert keinen Trigger aus.
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-44-tests.sh
# Fixtures und Helfer: lib/factory-lock-fixtures.sh; der Guard lessons_index_guard_44 liegt in lib/assert-helpers.sh.

set -uo pipefail

TESTS_DIR_44="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib_44 in assert-helpers test-groups factory-lock-fixtures; do
  # shellcheck source=/dev/null
  source "$TESTS_DIR_44/lib/$lib_44.sh" || { echo "$(basename "$0"): Helfer-Lib nicht ladbar: lib/$lib_44.sh (fail-closed)" >&2; exit 2; }
done

# Ohne yq entfällt die Gruppe still: die Skip-Zeile für #23/#24/#37 schreibt factory-lock-23-tests.sh
[ "$HAS_YQ" -eq 1 ] || { test_group_finish; exit $?; }
factory_lock_setup
echo ""
echo "Factory-Issue #44: Lessons-Index erreicht den Konsumenten:"

# world_44 <name> <mit-index: 1|0> – Welt mit Konsument C1 (eigene Anpassungsstellen, committet) und Upstream-Release v4.0.0 aus den
# ECHTEN Factory-Dateien plus neuer Lesson neu-44.md. mit-index=1: Übersichtszeile + INDEX-Gruppe (neuer Weg); 0: nur eine Zeile in
# einer Upstream-PROJECT-CONTEXT.md (alter Weg). Diese Datei kommt wie bei einem echten Release (factory-release-manifest.sh baut aus
# `ownership-check.sh --list factory`) nicht ins Manifest.
# Setzt: out_44, rc_44 (Ausgabe und Exit des Syncs), SHA_CLAUDE_44, SHA_PC_44 (Fingerprints der Konsumenten-Anpassungsstellen).
world_44() {
  world_23 "$1"
  printf '# Projekt-Regeln\n@docs/factory/FACTORY.md\n' > "$C1_23/CLAUDE.md"
  mkdir -p "$C1_23/docs/factory"; printf '# Projekt-Kontext\n' > "$C1_23/docs/factory/PROJECT-CONTEXT.md"
  git -C "$C1_23" add -A && git_23 -C "$C1_23" commit -q -m kontext
  SHA_CLAUDE_44="$(shasum -a 256 < "$C1_23/CLAUDE.md")"; SHA_PC_44="$(shasum -a 256 < "$C1_23/docs/factory/PROJECT-CONTEXT.md")"
  mkdir -p "$U23/docs/factory/lessons" "$U23/scripts/checks"
  sed '1s/.*/# Development Factory · v4.0.0/' "$FACTORY_ROOT/docs/factory/FACTORY.md" > "$U23/docs/factory/FACTORY.md"
  cp "$FACTORY_ROOT"/docs/factory/lessons/*.md "$U23/docs/factory/lessons/"
  cp "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$U23/scripts/checks/customization-points.txt"
  printf '### Neue Lesson 44\n\ntext\n' > "$U23/docs/factory/lessons/neu-44.md"
  if [ "$2" = 1 ]; then
    awk '{ print } /\]\(lessons\/factory-workflow\.md\)/ { print "> - [`lessons/neu-44.md`](lessons/neu-44.md) – Testthema 44 · **Laden bei:** `/implement` bei Fall 44" }' \
      "$U23/docs/factory/FACTORY.md" > "$U23/x" && mv "$U23/x" "$U23/docs/factory/FACTORY.md"
    printf '\n**[`lessons/neu-44.md`](neu-44.md)** – Testthema 44 · **Laden bei:** `/implement` bei Fall 44\n\n- Neue Lesson 44 (aus Fixture)\n' >> "$U23/docs/factory/lessons/INDEX.md"
  else
    printf '**[`lessons/neu-44.md`](lessons/neu-44.md)** – Testthema 44 · **Laden bei:** `/implement` bei Fall 44\n' > "$U23/docs/factory/PROJECT-CONTEXT.md"
  fi
  git -C "$U23" add -A && git_23 -C "$U23" commit -q -m v4 && git -C "$U23" tag v4.0.0
  mk_manifest_23 "$U23" v4.0.0 "$R23/v4.0.0/factory-release.json"
  if [ "$2" = 0 ]; then
    jq '.files |= map(select(.path != "docs/factory/PROJECT-CONTEXT.md"))' "$R23/v4.0.0/factory-release.json" > "$R23/x" \
      && mv "$R23/x" "$R23/v4.0.0/factory-release.json"
  fi
  out_44="$(sync_23 "$C1_23" v4.0.0)"; rc_44=$?
}
guard_c1_44() { lessons_index_guard_44 "$C1_23/docs/factory/FACTORY.md" "$C1_23/docs/factory/lessons/INDEX.md" "$C1_23/docs/factory/lessons" "$C1_23/scripts/checks/customization-points.txt"; }

# ── AK7: neuer Weg ───────────────────────────────────────────────────────────────────────────────────────────────────
world_44 l44 1
assert_exit 0 "$rc_44" "#44 AK7: Abholung von v4.0.0 mit neuer Lesson → grün"
assert_true "$(cmp -s "$U23/docs/factory/lessons/neu-44.md" "$C1_23/docs/factory/lessons/neu-44.md"; echo $?)" "#44 AK7: die neue Lesson liegt beim Konsumenten (byte-gleich)"
assert_true "$(cmp -s "$U23/docs/factory/lessons/INDEX.md" "$C1_23/docs/factory/lessons/INDEX.md"; echo $?)" "#44 AK7: lessons/INDEX.md liegt beim Konsumenten (byte-gleich)"
assert_true "$(grep -F -- '](lessons/neu-44.md)' "$C1_23/docs/factory/FACTORY.md" | grep -qF -- '**Laden bei:**'; echo $?)" \
  "#44 AK7: FACTORY.md beim Konsumenten trägt die Übersichtszeile mit „Laden bei“ zur neuen Lesson"
guard_out_44="$(guard_c1_44)"; guard_rc_44=$?
assert_exit 0 "$guard_rc_44" "#44 AK7: der Guard ist gegen den Konsumenten grün (Ausgabe: ${guard_out_44:-leer})"
assert_true "$([ "$(shasum -a 256 < "$C1_23/CLAUDE.md")" = "$SHA_CLAUDE_44" ]; echo $?)" "#44 AK7: CLAUDE.md des Konsumenten byte-gleich"
assert_true "$([ "$(shasum -a 256 < "$C1_23/docs/factory/PROJECT-CONTEXT.md")" = "$SHA_PC_44" ]; echo $?)" "#44 AK7: PROJECT-CONTEXT.md des Konsumenten byte-gleich"

# ── AK7 Negativkontrolle: alter Weg (Trigger in der Anpassungsstelle) kommt nicht an ────────────────────────────────
world_44 l44n 0
# Realer Ablauf: das Manifest kennt die Anpassungsstelle nicht, der Sync ist grün – und die Lesson kommt OHNE Trigger an.
assert_exit 0 "$rc_44" "#44 AK7 (Negativkontrolle): Abholung mit Trigger nur in der Upstream-PROJECT-CONTEXT.md → Sync grün (Ausgabe: ${out_44:-leer})"
assert_true "$([ -f "$C1_23/docs/factory/lessons/neu-44.md" ]; echo $?)" "#44 AK7 (Negativkontrolle): die neue Lesson liegt beim Konsumenten"
assert_true "$(! grep -qF -- '](lessons/neu-44.md)' "$C1_23/docs/factory/FACTORY.md"; echo $?)" \
  "#44 AK7 (Negativkontrolle): FACTORY.md beim Konsumenten hat keine Übersichtszeile zur neuen Lesson"
guard_out_44="$(guard_c1_44)"; guard_rc_44=$?
assert_exit 1 "$guard_rc_44" "#44 AK7 (Negativkontrolle): „Trigger im Konsumenten vorhanden“ ist rot – Guard gegen den Konsumenten"
assert_contains_286 "$guard_out_44" "fehlt-uebersicht:neu-44.md" "#44 AK7 (Negativkontrolle): Signal fehlt-uebersicht:neu-44.md"
assert_true "$([ "$(shasum -a 256 < "$C1_23/docs/factory/PROJECT-CONTEXT.md")" = "$SHA_PC_44" ]; echo $?)" \
  "#44 AK7 (Negativkontrolle): die Anpassungsstelle des Konsumenten bleibt unverändert – der Trigger im alten Ort erreicht ihn nicht"
assert_absent "$(cat "$C1_23/docs/factory/PROJECT-CONTEXT.md")" "neu-44" "#44 AK7 (Negativkontrolle): PROJECT-CONTEXT.md des Konsumenten kennt die neue Lesson nicht"

factory_lock_template_unchanged
test_group_finish; exit $?
