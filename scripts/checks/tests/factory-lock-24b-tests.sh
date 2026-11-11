#!/usr/bin/env bash
# factory-lock-24b-tests.sh – Testgruppe Factory-Issue #24, Teil b: Token fehlt/abgelehnt, tokenfreie Abholung, Hooks,
# Fail-closed-Zweige, Rückkehr, Selbst-Ersatz, Credential-Helper, Verdrahtung von Skript und Workflow
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-24b-tests.sh
# Fixtures und Helfer: lib/factory-lock-fixtures.sh; Teil a: factory-lock-24a-tests.sh. Gibt keinen eigenen Abschnittskopf
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

# ── FS-T2.3: Token fehlt / abgelehnt → rot vor jedem weiteren Schritt, auch ohne neue Version ────────────────────────
world_24 t1
out_24="$(TOKEN_24='' upd_24)"; rc_24=$?
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 0 "$?" "#24 FS-T2.3: Token leer (GITHUB_TOKEN gesetzt) → rot mit Verweis auf OPERATING.md, nichts weiter"
world_24 t2
out_24="$(TOKEN_24=abgelaufen upd_24)"; rc_24=$?
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 0 "$?" "#24 FS-T2.3: Token abgelehnt (401) → rot, Release-Liste nie gelesen"
world_24 t3; printf 'false\n' > "$GS_24/push"
out_24="$(upd_24)"; rc_24=$?
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 0 "$?" "#24 FS-T2.3: Token ohne Schreibrecht → rot"
world_24 t4; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
out_24="$(TOKEN_24=abgelaufen upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && [ -z "$(sha_24 "$BR_24")" ]; echo $?)" "#24 FS-T2.3: abgelehntes Token bei neuer Version → rot, kein Push"
# Mutationsbeleg: ohne den Aufruf der Token-Prüfung verletzt derselbe Fall den Guard
MUT_24="$T23/mut24"
grep -vxF '  require_token' "$UPD_24" > "$T23/mut24-update.sh"
factory_scripts_24 "$MUT_24" "$T23/mut24-update.sh"
assert_true "$([ "$(grep -cxF '  require_token' "$UPD_24")" = 1 ] && ! grep -qxF '  require_token' "$MUT_24/scripts/factory-update.sh"; echo $?)" \
  "#24 FS-T2.3 (Mutation): genau der Aufruf der Token-Prüfung ist im Mutanten entfernt"
world_24 t5
out_24="$(TOKEN_24=abgelaufen upd_24 "$MUT_24/scripts/factory-update.sh")"; rc_24=$?
token_refused_24 "$rc_24" "$out_24" "$GS_24/calls.log"; assert_exit 1 "$?" "#24 FS-T2.3 (Mutation): ohne Token-Prüfung ist derselbe Guard rot – die Prüfung ist wirksam"

# ── Security: die Abholung läuft ohne Token (factory-sync.sh startet sich in der Fassung des Release neu) ────────────
# Wrapper-Stub statt factory-sync.sh: protokolliert, welche Token-Variablen er sieht, und reicht an das echte Skript weiter.
tokenless_sync_24() { # $1 = update-skript; setzt SEEN_24 (Protokoll) und MUT_24
  MUT_24="$W24/tokenless"; factory_scripts_24 "$MUT_24" "$1"
  mv "$MUT_24/scripts/factory-sync.sh" "$MUT_24/scripts/factory-sync.real.sh"
  SEEN_24="$W24/sync-env.log"
  printf '#!/usr/bin/env bash\nprintf "FST=%%s GH=%%s GT=%%s\\n" "${FACTORY_SYNC_TOKEN:-}" "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}" >> "%s"\nexec bash "%s" "$@"\n' \
    "$SEEN_24" "$MUT_24/scripts/factory-sync.real.sh" > "$MUT_24/scripts/factory-sync.sh"
  chmod +x "$MUT_24/scripts/factory-sync.sh"
}
next_world_24 tokenless; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
tokenless_sync_24 "$UPD_24"
out_24="$(upd_24 "$MUT_24/scripts/factory-update.sh")"; rc_24=$?
assert_exit 0 "$rc_24" "#24 Security: Lauf mit Wrapper-Stub für factory-sync.sh grün (Stub reicht an das echte Skript weiter)"
assert_true "$([ -s "$SEEN_24" ]; echo $?)" "#24 Security: factory-sync.sh wurde aufgerufen (Protokoll nicht leer)"
# Zeilenweise: factory-sync.sh startet sich nach dem Abholen neu (--compose --check) – auch dieser Aufruf muss tokenfrei sein
sync_saw_no_token_24() { [ "$(wc -l < "$SEEN_24")" -ge 2 ] && ! grep -qvxF 'FST= GH= GT=' "$SEEN_24"; }
assert_true "$(sync_saw_no_token_24; echo $?)" "#24 Security: jeder Aufruf von factory-sync.sh (auch der Neustart) sieht weder FACTORY_SYNC_TOKEN noch GH_TOKEN noch GITHUB_TOKEN"
assert_true "$([ "$(lock_on_branch_24)" = v1.1.0 ]; echo $?)" "#24 Security: der Update-PR entsteht trotzdem (Push und PR laufen danach mit Token)"
# Mutation: ohne das `env -u` desselben Aufrufs sieht der Stub das Token – derselbe Guard muss rot werden
next_world_24 tokenless; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
sed 's/env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN //' "$UPD_24" > "$T23/mut24-tokenless.sh"
assert_true "$([ "$(grep -c 'env -u FACTORY_SYNC_TOKEN' "$UPD_24")" = 1 ] && ! grep -q 'env -u FACTORY_SYNC_TOKEN' "$T23/mut24-tokenless.sh"; echo $?)" \
  "#24 Security (Mutation): genau das env -u der Abholung ist im Mutanten entfernt"
tokenless_sync_24 "$T23/mut24-tokenless.sh"
upd_24 "$MUT_24/scripts/factory-update.sh" >/dev/null
assert_exit 1 "$(sync_saw_no_token_24; echo $?)" "#24 Security (Mutation): ohne env -u ist derselbe Guard rot – die tokenfreie Abholung ist wirksam"
assert_true "$(grep -qF "FST=$GOOD_TOKEN_24" "$SEEN_24"; echo $?)" "#24 Security (Mutation): der Stub sah im Mutanten tatsächlich das Token"

# Security: Git-Hooks laufen nie – nach der Abholung stammen sie aus dem ungeprüften Release und erbten beim Push das Token
# spy_hooks_24 – core.hooksPath von C1 auf protokollierende Hooks (Hook-Name + sichtbare Token-Variablen); setzt HOOKS_24
spy_hooks_24() {
  local dir="$W24/hooks" h
  HOOKS_24="$W24/hooks.log"; mkdir -p "$dir"; : > "$HOOKS_24"
  for h in pre-commit commit-msg pre-push post-checkout reference-transaction; do
    printf '#!/usr/bin/env bash\nprintf "%s FST=%%s GH=%%s\\n" "${FACTORY_SYNC_TOKEN:-}" "${GH_TOKEN:-}" >> "%s"\nexit 0\n' "$h" "$HOOKS_24" > "$dir/$h"
    chmod +x "$dir/$h"
  done
  git -C "$C1_23" config core.hooksPath "$dir"
}
hooks_saw_no_token_24() { ! grep -qE '=[^ ]' "$HOOKS_24"; }
next_world_24 hooks; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; spy_hooks_24
out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 0 ] && [ "$(lock_on_branch_24)" = v1.1.0 ]; echo $?)" "#24 Security: mit installierten Hooks entsteht der Update-PR (kein Gate-Hook bricht den Push ab, F1)"
assert_true "$(hooks_saw_no_token_24; echo $?)" "#24 Security: kein Git-Hook sieht FACTORY_SYNC_TOKEN oder GH_TOKEN"
assert_true "$([ ! -s "$HOOKS_24" ]; echo $?)" "#24 Security: kein Git-Hook läuft (Commit, Push, Checkout, Fetch)"
# Mutation: ohne die Hook-Abschaltung laufen die Hooks mit Token – derselbe Guard muss rot werden
next_world_24 hooks; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; spy_hooks_24
sed 's|-c core.hooksPath=/dev/null ||' "$UPD_24" > "$T23/mut24-hooks.sh"
assert_true "$([ "$(grep -c 'core.hooksPath=/dev/null' "$UPD_24")" = 1 ] && ! grep -q 'core.hooksPath' "$T23/mut24-hooks.sh"; echo $?)" \
  "#24 Security (Mutation): genau die Hook-Abschaltung ist im Mutanten entfernt"
factory_scripts_24 "$W24/nohooks-mut" "$T23/mut24-hooks.sh"
upd_24 "$W24/nohooks-mut/scripts/factory-update.sh" >/dev/null
assert_exit 1 "$(hooks_saw_no_token_24; echo $?)" "#24 Security (Mutation): ohne core.hooksPath=/dev/null ist derselbe Guard rot – die Abschaltung ist wirksam"
assert_true "$(grep -qE "^pre-push FST=$GOOD_TOKEN_24 " "$HOOKS_24"; echo $?)" "#24 Security (Mutation): im Mutanten sah der pre-push-Hook tatsächlich das Token"

# ── F-24.2: Release-Liste nicht lesbar → rot ─────────────────────────────────────────────────────────────────────────
world_24 r1; : > "$GS_24/releases-fail"
out_24="$(upd_24)"; rc_24=$?
assert_exit 1 "$rc_24" "#24 F-24.2: Abruf der Release-Liste scheitert → rot (nicht „keine neue Version“)"
assert_contains_286 "$out_24" 'Release-Liste' "#24 F-24.2: die Meldung nennt die Release-Liste"
for resp_24 in 'kein json' '{"message":"Not Found"}' ''; do
  next_world_24 relbad;printf '%s' "$resp_24" > "$GS_24/releases.json"
  upd_24 >/dev/null; rc_24=$?
  assert_true "$([ "$rc_24" -eq 1 ] && [ -z "$(writes_24)" ]; echo $?)" "#24 F-24.2: Antwort „${resp_24}“ ist kein JSON-Array → rot, nichts geändert"
done

# ── F-24.1: Abholung scheitert → rot, kein Push, bestehender PR unverändert ──────────────────────────────────────────
world_24 a1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 >/dev/null
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0; rm -rf "$R23/v1.2.0"
branch_before_24="$(sha_24 "$BR_24")"; prs_before_24="$(cat "$GS_24/prs.json")"; main_before_24="$(sha_24 main)"; : > "$GS_24/calls.log"
out_24="$(upd_24)"; rc_24=$?
assert_exit 1 "$rc_24" "#24 F-24.1: Manifest fehlt → Abholung scheitert → rot"
assert_contains_286 "$out_24" 'nicht eingebunden' "#24 F-24.1: die Meldung von factory-sync.sh wird ausgegeben"
assert_true "$([ "$branch_before_24" = "$(sha_24 "$BR_24")" ] && [ "$main_before_24" = "$(sha_24 main)" ]; echo $?)" "#24 F-24.1: kein Push (Branch und main unverändert)"
assert_true "$([ "$prs_before_24" = "$(cat "$GS_24/prs.json")" ] && [ -z "$(writes_24)" ]; echo $?)" "#24 F-24.1: bestehender PR unverändert"
world_24 a2; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
printf 'echo lokal\n' >> "$C1_23/scripts/tool.sh"; git_23 -C "$C1_23" commit -qam lokal
git -C "$C1_23" push -q origin main
out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && [ -z "$(sha_24 "$BR_24")" ] && [ -z "$(writes_24)" ]; echo $?)" "#24 F-24.1/F2: lokale Änderung auf main → rot, kein Push, kein PR"
assert_contains_286 "$out_24" 'scripts/tool.sh' "#24 F-24.1/F2: die Meldung nennt die geänderte Datei"

# ── /test: weitere Fail-closed-Zweige (je Zweig: rot, zweigspezifische Meldung, nichts gepusht, kein schreibender gh-Aufruf) ──
# fail_closed_24 <beschreibung> <meldung> – setzt rc_24/out_24 des vorigen Laufs voraus; Branch nie gepusht, kein PR geschrieben
fail_closed_24() {
  assert_true "$([ "$rc_24" -eq 1 ] && [ -z "$(sha_24 "$BR_24")" ] && [ -z "$(writes_24)" ]; echo $?)" "#24 $1 → rot, kein Push, kein schreibender gh-Aufruf"
  assert_contains_286 "$out_24" "$2" "#24 $1 → Meldung nennt „$2“"
}
# gh nicht installiert: PATH nur mit den übrigen Werkzeugen (Symlinks), ohne gh
NOGH_24="$T23/nogh24"; mkdir -p "$NOGH_24"
for tool_24 in bash git jq yq awk sed grep cat tr cut sort head tail dirname basename mktemp rm cp mv mkdir shasum curl find ls wc uniq date cmp chmod readlink tee xargs env; do
  [ -x "$(command -v "$tool_24" 2>/dev/null)" ] && ln -sf "$(command -v "$tool_24")" "$NOGH_24/$tool_24"
done
world_24 g1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
out_24="$(env_23 "$C1_23" env PATH="$NOGH_24" GITHUB_REPOSITORY=acme/consumer FACTORY_SYNC_TOKEN="$GOOD_TOKEN_24" bash "$UPD_24")"; rc_24=$?
fail_closed_24 "gh nicht installiert" 'gh nicht gefunden'
assert_true "$([ ! -s "$GS_24/calls.log" ]; echo $?)" "#24 gh nicht installiert → der Stub wurde nie gerufen (Voraussetzung: kein gh im PATH)"
# GITHUB_REPOSITORY kein Slug → rot vor jedem gh-Aufruf
for repo_24 in 'kein-slug' '' 'a/b/c' 'a b/c'; do
  next_world_24 slug; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
  out_24="$(REPO_24="$repo_24" upd_24)"; rc_24=$?
  fail_closed_24 "GITHUB_REPOSITORY „${repo_24}“ ist kein Slug" 'kein <owner>/<repo>-Slug'
  assert_true "$([ ! -s "$GS_24/calls.log" ]; echo $?)" "#24 GITHUB_REPOSITORY „${repo_24}“ → kein gh-Aufruf"
done
# Fetch von origin scheitert → rot vor jedem Schreiben
world_24 f1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
git -C "$C1_23" remote set-url origin "file://$W24/gibt-es-nicht.git"
out_24="$(upd_24)"; rc_24=$?
fail_closed_24 "Fetch von origin scheitert" 'Fetch von origin'
# PR-Listen nicht lesbar (offen / geschlossen) → rot, nichts geschrieben (kein Rückfall auf „kein PR“ → kein Duplikat-PR)
for st_24 in open closed; do
  next_world_24 prl; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; : > "$GS_24/pr-list-fail-$st_24"
  out_24="$(upd_24)"; rc_24=$?
  fail_closed_24 "PR-Liste ($st_24) nicht lesbar" "PRs nicht lesbar"
done
# Arbeitsbaum des Konsumenten nicht sauber → kein Neuaufbau (ein Checkout -B würde die Änderung mitnehmen oder verlieren)
world_24 dirty1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
printf 'unfertig\n' > "$C1_23/unfertig.txt"
out_24="$(upd_24)"; rc_24=$?
fail_closed_24 "unsauberer Arbeitsbaum" 'Arbeitsbaum nicht sauber'
assert_true "$([ "$(cat "$C1_23/unfertig.txt")" = unfertig ]; echo $?)" "#24 unsauberer Arbeitsbaum → die Änderung des Konsumenten bleibt unberührt"

# PR anlegen scheitert, nachdem gepusht wurde → rot mit eigener Meldung; Branch steht (nächster Lauf repariert per Neuaufbau)
world_24 c1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; : > "$GS_24/pr-create-fail"
out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && [ "$(lock_on_branch_24)" = v1.1.0 ] && [ "$(open_prs_24)" = 0 ]; echo $?)" "#24 pr create scheitert → rot, Branch gepusht, kein PR"
assert_contains_286 "$out_24" 'nicht anlegbar' "#24 pr create scheitert → Meldung nennt das Anlegen"
rm -f "$GS_24/pr-create-fail"; : > "$GS_24/calls.log"; out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 0 ] && [ "$(open_prs_24)" = 1 ]; echo $?)" "#24 pr create scheitert → der Folgelauf legt den PR an (selbstheilend)"
# PR bearbeiten scheitert → rot, Body des bestehenden PR unverändert
world_24 pred1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; upd_24 >/dev/null
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0; : > "$GS_24/pr-edit-fail"; body_before_24="$(pr_body_24)"
out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 1 ] && [ "$body_before_24" = "$(pr_body_24)" ]; echo $?)" "#24 pr edit scheitert → rot, PR-Body unverändert"
assert_contains_286 "$out_24" 'nicht aktualisierbar' "#24 pr edit scheitert → Meldung nennt das Aktualisieren"

# Der Checkout des Konsumenten steht nach dem Lauf wieder auf dem Ausgangs-Branch (Folgelauf liest den Lock von dort)
# back_on_main_24 – C1 steht auf main
back_on_main_24() { [ "$(git -C "$C1_23" symbolic-ref -q --short HEAD)" = main ]; }
world_24 o1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 >/dev/null; back_on_main_24; assert_exit 0 "$?" "#24 Rückkehr: nach erfolgreichem Lauf steht der Checkout wieder auf main"
world_24 o2; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; : > "$GS_24/pr-create-fail"
upd_24 >/dev/null; back_on_main_24; assert_exit 0 "$?" "#24 Rückkehr: auch nach einem Abbruch im PR-Schritt steht der Checkout wieder auf main"
# Seit #37 (Factory-ADR-063 E18) schaltet der Lauf den Arbeitsbaum des Konsumenten gar nicht mehr um: ORIG_REF und die Rückkehr
# entfallen, der Neuaufbau läuft in einem frischen Klon. Statt der Rückkehr-Mutation gilt: HEAD und Branches von C1 bleiben unberührt.
untouched_24() { [ "$(git -C "$C1_23" rev-parse HEAD)" = "$1" ] && ! git -C "$C1_23" show-ref -q --verify "refs/heads/$BR_24"; }
world_24 o3; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; head_24="$(git -C "$C1_23" rev-parse HEAD)"
upd_24 >/dev/null; untouched_24 "$head_24"; assert_exit 0 "$?" "#24 E18: nach erfolgreichem Lauf sind HEAD und lokale Branches des Konsumenten unverändert (kein lokaler $BR_24)"
world_24 o4; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; head_24="$(git -C "$C1_23" rev-parse HEAD)"; : > "$GS_24/pr-create-fail"
upd_24 >/dev/null; untouched_24 "$head_24"; assert_exit 0 "$?" "#24 E18: auch nach einem Abbruch im PR-Schritt sind HEAD und lokale Branches unverändert"

# ── Selbst-Ersatz: factory-update.sh läuft aus dem Konsumenten-Checkout, factory-sync.sh überschreibt es im Lauf ─────
# Bash liest ein Skript stückweise und setzt nach `main` am alten Byte-Offset fort – dann in der neuen Fassung.
# self_replace_24 <welt> <update-skript> – C1 hat <update-skript> mit v1.1.0 übernommen; v1.2.0 liefert dieselbe Datei,
# verlängert um eine erkennbare Zeile genau am alten Dateiende. Das Skript läuft aus C1; setzt out_24/rc_24.
self_replace_24() {
  world_24 "$1"
  factory_scripts_24 "$U23" "$2"
  add_release_24 v1.1.0
  sync_23 "$C1_23" v1.1.0 >/dev/null
  git -C "$C1_23" add -A && git_23 -C "$C1_23" commit -q -m "adopt v1.1.0" && git -C "$C1_23" push -q origin main
  printf 'echo AUS-NEUER-VERSION-24; exit 7\n' >> "$U23/scripts/factory-update.sh"
  add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
  # Seit #37 läuft die Abholung im Modus fetch im Checkout des Konsumenten (CI: Job fetch) – dort ersetzt factory-sync.sh die Datei
  SR_PRE_24="$(cmp -s "$C1_23/scripts/factory-update.sh" "$UPD_24"; echo $?)"
  BUNDLE_24="$W24/sr.bundle"
  out_24="$(env_23 "$C1_23" env PATH="$GH_STUB_24:$PATH" bash "$C1_23/scripts/factory-update.sh" fetch v1.2.0 "$(git -C "$ORIGIN_24" rev-parse main)" "$BUNDLE_24")"; rc_24=$?
}
# Guard: Lauf grün, und keine Zeile der neuen Fassung wurde ausgeführt
self_replace_safe_24() { [ "$1" -eq 0 ] && ! grep -qF 'AUS-NEUER-VERSION-24' <<< "$2"; }
self_replace_24 sr1 "$UPD_24"
assert_true "$SR_PRE_24" "#24 Selbst-Ersatz (Voraussetzung): C1 führt die übernommene factory-update.sh aus"
self_replace_safe_24 "$rc_24" "$out_24"; assert_exit 0 "$?" "#24 Selbst-Ersatz: nach main liest bash nichts mehr aus der ersetzten Datei (grün, nichts aus v1.2.0 ausgeführt)"
assert_true "$([ "$(git bundle list-heads "$BUNDLE_24" | wc -l | tr -d ' ')" -ge 1 ]; echo $?)" "#24 Selbst-Ersatz: die Abholung liefert das Bundle (inkl. neuer factory-update.sh)"
# Mutationsbeleg: steht nach `main "$@"` kein exit auf derselben Zeile, verletzt derselbe Fall den Guard
END_LINE_24='main "$@"; exit $?'
sed "s/^main \"\\\$@\"; exit \\\$?\$/main \"\$@\"/" "$UPD_24" > "$T23/mut24-selfreplace.sh"
assert_true "$([ "$(grep -cxF "$END_LINE_24" "$UPD_24")" = 1 ] && ! grep -qxF "$END_LINE_24" "$T23/mut24-selfreplace.sh" \
  && [ "$(grep -cxF 'main "$@"' "$T23/mut24-selfreplace.sh")" = 1 ]; echo $?)" \
  "#24 Selbst-Ersatz (Mutation): genau die Aufrufzeile ist im Mutanten auf 'main \"\$@\"' ohne exit reduziert"
self_replace_24 sr2 "$T23/mut24-selfreplace.sh"
self_replace_safe_24 "$rc_24" "$out_24"; assert_exit 1 "$?" "#24 Selbst-Ersatz (Mutation): ohne exit auf der Aufrufzeile ist derselbe Guard rot"

# ── E12: Credential-Helper gibt das Token zur Laufzeit aus der Umgebung aus ──────────────────────────────────────────
helper_line_24="$(grep -E '^CREDENTIAL_HELPER=' "$UPD_24")"
assert_absent "$helper_line_24" "$GOOD_TOKEN_24" "#24 E12: die Helper-Definition enthält keinen Token-Wert"
cred_24="$(eval "$helper_line_24"; printf 'protocol=https\nhost=github.com\n\n' \
  | FACTORY_SYNC_TOKEN=geheim-24 git -c credential.helper= -c "credential.helper=$CREDENTIAL_HELPER" credential fill 2>/dev/null)"
assert_contains_286 "$cred_24" 'password=geheim-24' "#24 E12: der Helper liefert das Token aus FACTORY_SYNC_TOKEN"
assert_contains_286 "$cred_24" 'username=x-access-token' "#24 E12: der Helper liefert username=x-access-token"

# ── Verdrahtung: Skript und Workflow ─────────────────────────────────────────────────────────────────────────────────
upd_src_24="$(cat "$UPD_24")"
assert_true "$([ "$(grep -cE '(git|git_with_token) .*push ' <<< "$upd_src_24")" = 1 ]; echo $?)" "#24 F1: das Skript hat genau eine Push-Zeile"
assert_true "$(grep -E '(git|git_with_token) .*push ' <<< "$upd_src_24" | grep -qF '"$sha:refs/heads/$UPDATE_BRANCH"'; echo $?)" "#24 F1: einziges Push-Ziel ist refs/heads/\$UPDATE_BRANCH"
assert_true "$(grep -qxF 'UPDATE_BRANCH="chore/factory-update"' <<< "$upd_src_24"; echo $?)" "#24 F1: UPDATE_BRANCH ist fest chore/factory-update"
assert_absent "$upd_src_24" 'pr merge' "#24 AK2.4: das Skript ruft nie gh pr merge"
assert_absent "$upd_src_24" '--auto' "#24 AK2.4: das Skript aktiviert kein Auto-Merge"
assert_absent "$upd_src_24" '$GITHUB_TOKEN' "#24 AK2.4: das Skript liest GITHUB_TOKEN nie"
assert_absent "$upd_src_24" '${GITHUB_TOKEN' "#24 AK2.4: das Skript liest GITHUB_TOKEN nie (Klammerform)"

wf_24="$(cat "$WF_24" 2>/dev/null)"
assert_true "$(grep -qE '^  schedule:' <<< "$wf_24" && grep -qE "^    - cron: '[^']+'" <<< "$wf_24"; echo $?)" "#24 AK2.2d: factory-update.yml läuft per schedule"
assert_true "$(grep -qE '^  workflow_dispatch:' <<< "$wf_24"; echo $?)" "#24 AK2.2d: factory-update.yml läuft per workflow_dispatch"
assert_true "$(grep -qxF '  group: factory-update' <<< "$wf_24" && grep -qxF '  cancel-in-progress: false' <<< "$wf_24"; echo $?)" "#24 E10: concurrency factory-update, ohne Cancel"
assert_true "$(grep -qxF 'permissions:' <<< "$wf_24" && grep -qxF '  contents: read' <<< "$wf_24"; echo $?)" "#24 E10: GITHUB_TOKEN nur contents: read"
assert_true "$(grep -qxF '          fetch-depth: 0' <<< "$wf_24" && grep -qxF '          persist-credentials: false' <<< "$wf_24"; echo $?)" "#24 E10: Checkout mit fetch-depth 0 und ohne gespeicherte Anmeldung"
assert_absent "$wf_24" 'GITHUB_TOKEN' "#24 AK2.4: factory-update.yml reicht GITHUB_TOKEN nicht weiter"
assert_absent "$wf_24" 'pr merge' "#24 AK2.4: factory-update.yml merged nie"


factory_lock_template_unchanged
test_group_finish; exit $?
