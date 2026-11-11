#!/usr/bin/env bash
# factory-lock-37b-tests.sh – Testgruppe Factory-Issue #37, Teil b: Fail-closed-Zweige von fetch/publish, F-37.1,
# Modus guard und preflight
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-37b-tests.sh
# Fixtures und Helfer: lib/factory-lock-fixtures.sh; Teil a: factory-lock-37a-tests.sh. Gibt keinen eigenen Abschnittskopf
# aus: seine Ausgabe folgt beim Sammeln direkt auf Teil a, wie zuvor im selben Abschnitt.

set -uo pipefail

TESTS_DIR_52="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib_52 in assert-helpers test-groups factory-lock-fixtures; do
  # shellcheck source=/dev/null
  source "$TESTS_DIR_52/lib/$lib_52.sh" || { echo "$(basename "$0"): Helfer-Lib nicht ladbar: lib/$lib_52.sh (fail-closed)" >&2; exit 2; }
done

# Ohne yq entfällt die Gruppe still: die Skip-Zeile für #23/#24/#37 schreibt factory-lock-23-tests.sh
[ "$HAS_YQ" -eq 1 ] || { test_group_finish; exit $?; }
factory_lock_setup
factory_lock_setup_24

# ── /test: Fail-closed-Zweige von fetch/publish, die Mutationsläufe als ungetestet gezeigt haben ─────────────────────────
# mutdie_37 <name> <anfang-der-meldung> – Mutante: das `|| die "<anfang>…` wird zu `|| true "<anfang>…` (der Zweig läuft weiter statt zu enden)
mutdie_37() { mutant_37 "$1" "s#\|\| die \"$2#|| true \"$2#"; }
# Jeder Fall: rot mit zweigspezifischer Meldung, kein Push, kein schreibender gh-Aufruf (bzw. kein Bundle bei fetch)
sc_handover_37() { bundle_37 "$1"; BUNDLE_37=''; pub_37 "${2:-}" ''; refused_ok_37 'Pfad des Übergabe-Bundles fehlt'; }
sc_manifest_gone_37() { bundle_37 "$1"; rm -f "$R23/v1.1.0/factory-release.json"; pub_37 "${2:-}"; refused_ok_37 'nicht abrufbar'; }
sc_manifest_bad_37() { bundle_37 "$1"; printf '{' > "$R23/v1.1.0/factory-release.json"; pub_37 "${2:-}"; refused_ok_37 'ungültig'; }
sc_nocp_37() { # Liste der Anpassungsstellen fehlt → Schutzprüfung nicht möglich → fail-closed (nicht „keine Funde“)
  local s="${2:-}"
  bundle_37 "$1"
  if [ -z "$s" ]; then factory_scripts_24 "$W24/nocp" "$UPD_24"; s="$W24/nocp/scripts/factory-update.sh"; fi
  rm -f "$(dirname "$s")/checks/customization-points.txt"; pub_37 "$s"; refused_ok_37 'nicht prüfbar'
}
sc_missing_file_37() { bundle_37 "$1" 'git rm -q scripts/tool.sh && git -c user.email=t@x -c user.name=t commit -q --amend --no-edit'; pub_37 "${2:-}"; refused_ok_37 'fehlt in der Übergabe'; }
sc_newline_37() {
  bundle_37 "$1" "$(printf '%s' "touch \"\$(printf 'zeile\\numbruch')\" && git add -A && git -c user.email=t@x -c user.name=t commit -q --amend --no-edit")"
  pub_37 "${2:-}"; refused_ok_37 'Zeilenumbruch'
}
sc_push_rejected_37() { # Origin lehnt den Push ab (z. B. Branch-Schutz) → rot, PR nie angelegt
  bundle_37 "$1"; mkdir -p "$ORIGIN_24/hooks"; printf '#!/bin/sh\nexit 1\n' > "$ORIGIN_24/hooks/pre-receive"; chmod +x "$ORIGIN_24/hooks/pre-receive"
  pub_37 "${2:-}"; refused_ok_37 'abgelehnt'
}
sc_dirty_fetch_37() { # Modus fetch in einem Checkout mit unversionierter Datei → rot, kein Bundle
  world_24 "$1"; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; CL_37="$W24/clone37"; BUNDLE_37="$W24/u.bundle"
  git clone -q "$C1_23" "$CL_37"; : > "$CL_37/unfertig.txt"
  out_24="$(env_23 "$CL_37" env -u FACTORY_SYNC_TOKEN bash "${2:-$UPD_24}" fetch v1.1.0 "$(git -C "$ORIGIN_24" rev-parse main)" "$BUNDLE_37")"; rc_24=$?
  [ "$rc_24" -eq 1 ] && grep -qF 'Arbeitsbaum nicht sauber' <<< "$out_24" && [ ! -e "$BUNDLE_37" ]
}
sc_base_missing_37() { # Basis-Commit existiert im Checkout nicht → rot, kein Bundle
  world_24 "$1"; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; CL_37="$W24/clone37"; BUNDLE_37="$W24/u.bundle"
  git clone -q "$C1_23" "$CL_37"
  out_24="$(env_23 "$CL_37" env -u FACTORY_SYNC_TOKEN bash "${2:-$UPD_24}" fetch v1.1.0 "$(printf '0%.0s' $(seq 40))" "$BUNDLE_37")"; rc_24=$?
  [ "$rc_24" -eq 1 ] && grep -qF 'nicht auscheckbar' <<< "$out_24" && [ ! -e "$BUNDLE_37" ]
}
cov_37() { # <fall> <meldungsanfang> <beschreibung> – Fall grün, Mutante (die → weiter) rot
  local fn="sc_$1_37"
  "$fn" "cv-$1-a"; assert_exit 0 "$?" "#37 /test: $3 → rot, zweigspezifische Meldung, nichts gepusht"
  mutdie_37 "cv-$1" "$2"
  "$fn" "cv-$1-b" "$MUT37"; assert_exit 1 "$?" "#37 /test (Mutation): ohne dieses die ist derselbe Fall nicht mehr rot – der Zweig ist wirksam"
}
cov_37 handover 'Pfad des Übergabe-Bundles' 'leerer Bundle-Pfad (Modus publish)'
cov_37 manifest_gone 'Release-Manifest zu \$version nicht abrufbar' 'Release-Manifest nicht abrufbar'
cov_37 manifest_bad 'Release-Manifest zu \$version ungültig' 'Release-Manifest ungültig'
cov_37 nocp 'Anpassungsstellen nicht prüfbar' 'Liste der Anpassungsstellen fehlt (kein „keine Funde“)'
cov_37 missing_file 'Manifest-Datei fehlt in der Übergabe' 'Manifest-Datei fehlt im Bundle'
cov_37 push_rejected 'Push auf \$UPDATE_BRANCH abgelehnt' 'Origin lehnt den Push ab'
cov_37 dirty_fetch 'Arbeitsbaum nicht sauber' 'Modus fetch mit unsauberem Arbeitsbaum'
cov_37 base_missing 'Basis \$base nicht auscheckbar' 'Modus fetch mit unbekannter Basis'
# Zeilenumbruch im Pfad: das case-Muster endet nicht auf `|| die`, eigene Mutante
sc_newline_37 nl-a; assert_exit 0 "$?" "#37 /test: Pfad mit Zeilenumbruch in der Übergabe → rot, zweigspezifische Meldung, nichts gepusht"
mutant_37 nl 's#\) die "Übergabe enthält einen Pfad#) true "Übergabe enthält einen Pfad#'
sc_newline_37 nl-b "$MUT37"; assert_exit 1 "$?" "#37 /test (Mutation): ohne dieses die ist derselbe Fall nicht mehr rot"
# Unbekannter Modus
out_24="$(env_23 "$C1_23" env PATH="$GH_STUB_24:$PATH" bash "$UPD_24" frobnicate)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && grep -qF 'unbekannter Modus' <<< "$out_24"; echo $?)" "#37 /test: unbekannter Modus → rot mit Meldung"

# ── F-37.1: Übergabe scheitert → rot, kein Push, bestehender PR unverändert ──────────────────────────────────────────
bundle_37 pu1; pub_37 "" "$W24/gibt-es-nicht.bundle"
refused_ok_37 'Bundle fehlt'; assert_exit 0 "$?" "#37 F-37.1: kein Bundle (Abholung abgebrochen) → rot, kein Push, kein PR"
mutant_37 vorhanden 's#\[ -f "\$bundle" \]#true#'
pub_37 "$MUT37" "$W24/gibt-es-nicht.bundle"; refused_ok_37 'Bundle fehlt'; assert_exit 1 "$?" "#37 F-37.1 (Mutation): ohne Existenzprüfung ist derselbe Guard rot"
printf 'kein bundle\n' > "$W24/kaputt.bundle"; pub_37 "" "$W24/kaputt.bundle"
refused_ok_37 'unlesbar'; assert_exit 0 "$?" "#37 F-37.1: unlesbares Bundle → rot, kein Push, kein PR"
world_24 pu2; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; upd_24 >/dev/null
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0; BASE_37="$(git -C "$ORIGIN_24" rev-parse main)"
branch_before_24="$(sha_24 "$BR_24")"; prs_before_24="$(cat "$GS_24/prs.json")"; : > "$GS_24/calls.log"
VER_37=v1.2.0 pub_37 "" "$W24/gibt-es-nicht.bundle"
assert_true "$([ "$rc_24" -eq 1 ] && [ "$branch_before_24" = "$(sha_24 "$BR_24")" ] && [ "$prs_before_24" = "$(cat "$GS_24/prs.json")" ] && [ -z "$(writes_24)" ]; echo $?)" "#37 F-37.1: bestehender Update-PR und Branch bleiben bei fehlender Übergabe unverändert"
# neuere Version seit dem Preflight → publish wirft die Übergabe weg
bundle_37 ps1; releases_24 v1.0.0 v1.1.0 v1.2.0; pub_37
refused_ok_37 'inzwischen'; assert_exit 0 "$?" "#37 AK-37c: neuere Version seit dem Preflight → rot, kein Push (der nächste Lauf baut neu auf)"
mutant_37 aktuell 's#\[ "\$TARGET_VERSION" = "\$1" \]#true#'
bundle_37 ps2; releases_24 v1.0.0 v1.1.0 v1.2.0; pub_37 "$MUT37"; refused_ok_37 'inzwischen'; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Versionsvergleich ist derselbe Guard rot"
# Übergabeargumente stammen aus Job-Ausgaben: Form wird geprüft, bevor sie an git/curl gehen
bundle_37 pa1
for bad_37 in 'v1.1' '--upload-pack=x' ''; do
  VER_37="$bad_37" pub_37
  assert_true "$([ "$rc_24" -eq 1 ] && [ -z "$(sha_24 "$BR_24")" ] && [ -z "$(writes_24)" ]; echo $?)" "#37 Übergabe: Version „${bad_37}“ → rot, nichts geschrieben"
done
VER_37=v1.1.0; BASE_37=kein-sha pub_37
assert_true "$([ "$rc_24" -eq 1 ] && grep -qF 'keine Commit-SHA' <<< "$out_24" && [ -z "$(writes_24)" ]; echo $?)" "#37 Übergabe: Basis ohne SHA-Form → rot, nichts geschrieben"

# ── Modus guard (AK-37f, F-37.3) und preflight (F-37.2) ──────────────────────────────────────────────────────────────
guard_37() { # <wurzel> [<skript>] – Modus guard ohne FACTORY_SYNC_TOKEN, Repository-Secret aus REPOSEC_37; setzt out_24/rc_24
  out_24="$(env_23 "$1" env -u FACTORY_SYNC_TOKEN PATH="$GH_STUB_24:$PATH" GH_STUB_STATE="$GS_24" GH_STUB_TOKEN=x "FACTORY_SYNC_TOKEN_REPO_SECRET=${REPOSEC_37-}" \
    GITHUB_OUTPUT="$W24/gh-output" bash "${2:-$UPD_24}" guard)"; rc_24=$?
}
world_24 gd1; : > "$W24/gh-output"; REPOSEC_37=''; guard_37 "$C1_23"
assert_true "$([ "$rc_24" -eq 0 ] && grep -qxF 'lock=true' "$W24/gh-output"; echo $?)" "#37 guard: Lock vorhanden, kein Repository-Secret → grün, Ausgabe lock=true"
assert_true "$([ ! -s "$GS_24/calls.log" ]; echo $?)" "#37 guard: braucht weder Token noch gh (kein Aufruf)"
REPOSEC_37='altes-secret'; guard_37 "$C1_23"
assert_true "$([ "$rc_24" -eq 1 ] && grep -qF 'Repository-Secret' <<< "$out_24" && grep -qF 'OPERATING.md §0.6' <<< "$out_24"; echo $?)" "#37 AK-37f: Repository-Secret FACTORY_SYNC_TOKEN vorhanden → rot mit Verweis auf OPERATING.md §0.6"
mutant_37 wachter 's#\[ -z "\$\{FACTORY_SYNC_TOKEN_REPO_SECRET:-\}" \]#true#'
guard_37 "$C1_23" "$MUT37"
assert_exit 0 "$rc_24" "#37 AK-37f (Mutation): ohne Wächter bleibt der Lauf mit Repository-Secret grün – der Wächter ist wirksam"
world_24 gd2; : > "$W24/gh-output"; REPOSEC_37='altes-secret'; guard_37 "$C0_23"
assert_true "$([ "$rc_24" -eq 0 ] && grep -qF 'kein factory.lock' <<< "$out_24" && grep -qxF 'lock=false' "$W24/gh-output" && [ ! -s "$GS_24/calls.log" ]; echo $?)" "#37 F-37.3: ohne Lock grüner No-op (lock=false), auch mit Repository-Secret, ohne gh-Aufruf"
# Kurzform in CI verweigert (Token neben Release-Code)
world_24 ci1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
out_24="$(GITHUB_ACTIONS=true upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && grep -qF 'nicht in CI' <<< "$out_24" && [ ! -s "$GS_24/calls.log" ]; echo $?)" "#37 E20: die Kurzform verweigert den Lauf in CI, vor jedem gh-Aufruf"
mutant_37 ci 's#\[ "\$\{GITHUB_ACTIONS:-\}" != true \]#true#'
world_24 ci2; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
out_24="$(GITHUB_ACTIONS=true upd_24 "$MUT37")"; rc_24=$?
assert_exit 0 "$rc_24" "#37 E20 (Mutation): ohne die Prüfung läuft die Kurzform in CI – die Verweigerung ist wirksam"
# preflight: Token fehlt im Kontext → FS-T2.3 unverändert, Meldung nennt den Kontext (F-37.2)
pre_37() { # [<token>] – Modus preflight; setzt out_24/rc_24
  out_24="$(env_23 "$C1_23" env PATH="$GH_STUB_24:$PATH" GH_STUB_STATE="$GS_24" GH_STUB_TOKEN="$GOOD_TOKEN_24" GITHUB_REPOSITORY=acme/consumer GITHUB_OUTPUT="$W24/gh-output" \
    FACTORY_SYNC_TOKEN="${1-$GOOD_TOKEN_24}" bash "$UPD_24" preflight)"; rc_24=$?
}
world_24 pf1; : > "$W24/gh-output"; pre_37 ''
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 0 "$?" "#37 F-37.2: Token im Kontext leer → rot vor jedem weiteren Schritt (FS-T2.3)"
assert_contains_286 "$out_24" 'Environment factory-update' "#37 F-37.2: die Meldung nennt den Kontext (Environment factory-update) als mögliche Ursache"
world_24 pf2; : > "$W24/gh-output"; pre_37 abgelaufen
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 0 "$?" "#37 F-37.2: Token abgelehnt → rot, Release-Liste nie gelesen"
assert_contains_286 "$out_24" 'Environment factory-update' "#37 F-37.2: auch bei abgelehntem Token nennt die Meldung den Kontext"
world_24 pf3; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; : > "$W24/gh-output"; pre_37
assert_true "$([ "$rc_24" -eq 0 ] && grep -qxF 'version=v1.1.0' "$W24/gh-output" && grep -qxF "base_sha=$(sha_24 main)" "$W24/gh-output" && [ -z "$(writes_24)" ] && [ -z "$(sha_24 "$BR_24")" ]; echo $?)" "#37 preflight: neue Version → Ausgabe version/base_sha, kein Push, kein schreibender Aufruf"
world_24 pf4; : > "$W24/gh-output"; pre_37
assert_true "$([ "$rc_24" -eq 0 ] && ! grep -q '^version=' "$W24/gh-output"; echo $?)" "#37 preflight: keine neuere Version → grün ohne Ausgabe version (Folge-Jobs entfallen)"
world_24 pf5; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; upd_24 >/dev/null; : > "$W24/gh-output"; pre_37
assert_true "$([ "$rc_24" -eq 0 ] && ! grep -q '^version=' "$W24/gh-output"; echo $?)" "#37 preflight: Update-PR steht schon auf der Version → grün ohne Ausgabe version"

factory_lock_template_unchanged
test_group_finish; exit $?
