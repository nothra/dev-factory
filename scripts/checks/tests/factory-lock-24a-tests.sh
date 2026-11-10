#!/usr/bin/env bash
# factory-lock-24a-tests.sh – Testgruppe Factory-Issue #24, Teil a: Update-Workflow und Update-PR (factory-update.sh) –
# neue Version, keine neuere Version, mehrere Versionen, Fremd-Commits, Lease, geschlossene PRs, ohne/mit unlesbarem Lock
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-24a-tests.sh
# Fixtures und Helfer: lib/factory-lock-fixtures.sh; Teil b (Token, Security, Fail-closed, Selbst-Ersatz, Verdrahtung): factory-lock-24b-tests.sh.

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
echo ""
echo "Factory-Issue #24: Update-Workflow und Update-PR:"


# ── AK2.2d / AK2.4 / F1: neue Version → Update-PR ────────────────────────────────────────────────────────────────────
world_24 u1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
main_before_24="$(sha_24 main)"
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 AK2.2d: neue Version v1.1.0 → Lauf grün"
assert_true "$([ "$(lock_on_branch_24)" = v1.1.0 ]; echo $?)" "#24 AK2.2d: factory.lock auf $BR_24 zeigt auf v1.1.0"
# Vergleich: Diff des Branches == Diff einer direkten Abholung auf main
git clone -q "file://$ORIGIN_24" "$W24/direct"
env_23 "$W24/direct" bash "$SYNC_23" v1.1.0 >/dev/null
git -C "$W24/direct" add -A
direct_tree_24="$(git -C "$W24/direct" write-tree)"
branch_tree_24="$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^{tree}")"
assert_true "$([ "$direct_tree_24" = "$branch_tree_24" ]; echo $?)" "#24 AK2.2d: Stand des Branches == Ergebnis von factory-sync.sh v1.1.0 auf main (sonst keine Änderung)"
assert_true "$([ "$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^")" = "$main_before_24" ]; echo $?)" "#24 AK2.2d: genau ein Commit auf main"
assert_true "$([ "$(git -C "$ORIGIN_24" log -1 --format=%an "refs/heads/$BR_24")" = factory-update ]; echo $?)" "#24 E11: Commit mit expliziter Identität factory-update"
assert_true "$([ "$(open_prs_24)" = 1 ]; echo $?)" "#24 AK2.2d: genau ein offener PR"
assert_contains_286 "$(pr_body_24)" 'Notes v1.1.0' "#24 AK2.2d: der PR-Body zeigt die Release Notes von v1.1.0"
assert_contains_286 "$(pr_body_24)" '<!-- factory-update-version: v1.1.0 -->' "#24 E13: der PR-Body trägt die Versionsmarke"
assert_contains_286 "$(pr_body_24)" 'von v1.0.0 auf v1.1.0' "#24 E13: der PR-Body nennt „von N auf V“"
assert_true "$([ "$(jq -r '.[0].title' "$GS_24/prs.json")" = 'chore: factory auf v1.1.0 heben' ]; echo $?)" "#24 E13: Titel nennt die Version"
assert_true "$([ "$(jq -r '.[0].labels[0]' "$GS_24/prs.json")" = enhancement ]; echo $?)" "#24 E11: PR trägt das Art-Label enhancement"
assert_true "$(grep -qE '^pr create .*--base main .*--head chore/factory-update' "$GS_24/calls.log"; echo $?)" "#24 AK2.2d: PR von $BR_24 nach main"
assert_absent "$(grep -E '^pr create' "$GS_24/calls.log")" '--draft' "#24 E11: der PR ist kein Draft"
assert_absent "$(cat "$GS_24/calls.log")" 'pr merge' "#24 AK2.4: kein Merge-Aufruf im Protokoll"
assert_absent "$(cat "$GS_24/calls.log")" '--auto' "#24 AK2.4: kein Auto-Merge im Protokoll"
assert_absent "$(cat "$GS_24/calls.log")" 'GITHUB_TOKEN=gesetzt' "#24 AK2.4: GITHUB_TOKEN erreicht gh nie (kein Rückfall)"
assert_true "$([ "$(grep -c '' "$GS_24/calls.log")" = "$(grep -c "GH_TOKEN=$GOOD_TOKEN_24 " "$GS_24/calls.log")" ]; echo $?)" "#24 AK2.4: jeder gh-Aufruf läuft mit FACTORY_SYNC_TOKEN"
assert_true "$([ "$(sha_24 main)" = "$main_before_24" ]; echo $?)" "#24 F1: main im Origin unverändert"
assert_true "$([ "$(git -C "$ORIGIN_24" for-each-ref --format='%(refname)' refs/heads | LC_ALL=C sort | tr '\n' ' ')" = "refs/heads/$BR_24 refs/heads/main " ]; echo $?)" \
  "#24 F1: einziges neues Schreibziel im Origin ist $BR_24"
assert_absent "$(cat "$C1_23/.git/config")" "$GOOD_TOKEN_24" "#24 E12: das Token steht nicht in .git/config"

# ── AK2.4b: keine neuere Version / kein Release → nichts geändert ────────────────────────────────────────────────────
nochange_24() { # $1 = Beschreibung; erwartet: grün, Hinweis, kein schreibender Aufruf, Origin unverändert
  local refs_before; refs_before="$(git -C "$ORIGIN_24" for-each-ref)"
  out_24="$(upd_24)"; rc_24=$?
  assert_exit 0 "$rc_24" "#24 $1 → Lauf grün"
  assert_contains_286 "$out_24" 'ℹ' "#24 $1 → Hinweis in der Ausgabe"
  assert_true "$([ -z "$(writes_24)" ]; echo $?)" "#24 $1 → kein schreibender gh-Aufruf"
  assert_true "$([ "$refs_before" = "$(git -C "$ORIGIN_24" for-each-ref)" ]; echo $?)" "#24 $1 → kein Push"
}
world_24 n1; nochange_24 "AK2.4b: neueste Version = N"
assert_contains_286 "$out_24" 'keine neuere Version' "#24 AK2.4b: der Hinweis nennt den Grund"
world_24 n2; printf '[]\n' > "$GS_24/releases.json"; nochange_24 "AK2.4b: kein veröffentlichtes Release"
world_24 n3; releases_24 v0.9.0; nochange_24 "AK2.4b: neueste Version < N (kein Downgrade)"
world_24 n4; add_release_24 v1.1.0; add_release_24 v2.5.0
jq '[{tag_name: "v2.5.0", draft: true, prerelease: false, body: "", assets: [{name: "factory-release.json"}]},
     {tag_name: "v1.1.0", draft: false, prerelease: true, body: "", assets: [{name: "factory-release.json"}]},
     {tag_name: "v9.0.0", draft: false, prerelease: false, body: "", assets: [{name: "notes.txt"}]},
     {tag_name: "v9.1.0-rc1", draft: false, prerelease: false, body: "", assets: [{name: "factory-release.json"}]},
     {tag_name: "v1.0.0", draft: false, prerelease: false, body: "", assets: [{name: "factory-release.json"}]}]' -n > "$GS_24/releases.json"
nochange_24 "AK2.4b: Draft, Pre-Release, Release ohne Manifest-Asset und Nicht-SemVer-Tag zählen nicht"

# Numerischer Vergleich: v1.10.0 > v1.9.0 (kein lexikalischer Vergleich)
world_24 s1; add_release_24 v1.9.0; add_release_24 v1.10.0; releases_24 v1.10.0 v1.9.0 v1.0.0
upd_24 >/dev/null; assert_true "$([ "$(lock_on_branch_24)" = v1.10.0 ]; echo $?)" "#24 E11: höchste Version numerisch verglichen (v1.10.0 > v1.9.0)"

# Pagination: `gh api --paginate` liefert je Seite ein eigenes JSON-Array hintereinander – die neueste Version kann auf Seite 2 liegen
paged_ok_24() { [ "$(lock_on_branch_24 2>/dev/null)" = v1.1.0 ]; }
world_24 pg1; add_release_24 v1.1.0
{ releases_24 v1.0.0; cat "$GS_24/releases.json"; releases_24 v1.1.0; cat "$GS_24/releases.json"; } > "$GS_24/pages.json"
mv "$GS_24/pages.json" "$GS_24/releases.json"
assert_true "$([ "$(jq -s 'length' "$GS_24/releases.json")" = 2 ]; echo $?)" "#24 Pagination (Voraussetzung): die Stub-Antwort besteht aus zwei getrennten Arrays"
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 Pagination: neueste Version nur auf Seite 2 → Lauf grün"
assert_true "$(paged_ok_24; echo $?)" "#24 Pagination: Version von Seite 2 (v1.1.0) wird angeboten"
# Mutation: ohne `add` (nur die erste Seite) bliebe v1.1.0 unsichtbar – derselbe Guard muss rot werden
world_24 pg2; add_release_24 v1.1.0
{ releases_24 v1.0.0; cat "$GS_24/releases.json"; releases_24 v1.1.0; cat "$GS_24/releases.json"; } > "$GS_24/pages.json"
mv "$GS_24/pages.json" "$GS_24/releases.json"
sed 's/^  add$/  .[0]/' "$UPD_24" > "$T23/mut24-pages.sh"
assert_true "$([ "$(grep -c '^  add$' "$UPD_24")" = 1 ] && ! grep -q '^  add$' "$T23/mut24-pages.sh"; echo $?)" \
  "#24 Pagination (Mutation): genau das Zusammenführen der Seiten ist im Mutanten entfernt"
factory_scripts_24 "$W24/pages-mut" "$T23/mut24-pages.sh"
upd_24 "$W24/pages-mut/scripts/factory-update.sh" >/dev/null
assert_exit 1 "$(paged_ok_24; echo $?)" "#24 Pagination (Mutation): ohne das Zusammenführen ist derselbe Guard rot – es ist wirksam"

# ── F3 / AK-24a: mehrere Versionen → ein PR, neu aufgebaut auf die neueste ───────────────────────────────────────────
world_24 f3; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 >/dev/null
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 F3: zweiter Lauf nach v1.2.0 → grün"
assert_true "$([ "$(open_prs_24)" = 1 ]; echo $?)" "#24 F3: höchstens ein offener Update-PR"
assert_true "$([ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" "#24 F3: Lock im Branch = v1.2.0"
assert_true "$([ "$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^")" = "$(sha_24 main)" ]; echo $?)" "#24 F3: Branch von main aus neu aufgebaut (v1.1.0 nicht als Zwischenstand)"
assert_true "$([ "$(jq -r '.[0].title' "$GS_24/prs.json")" = 'chore: factory auf v1.2.0 heben' ]; echo $?)" "#24 F3: Titel nennt v1.2.0"
assert_true "$(grep -qE '^pr edit 1 ' "$GS_24/calls.log"; echo $?)" "#24 F3: der bestehende PR wird bearbeitet, nicht neu angelegt"
body_24="$(pr_body_24)"
assert_contains_286 "$body_24" '<!-- factory-update-version: v1.2.0 -->' "#24 F3: Body nennt v1.2.0 (Marke)"
assert_contains_286 "$body_24" 'Notes v1.1.0' "#24 AK-24a: Notes der übersprungenen Version v1.1.0 im Body"
assert_contains_286 "$body_24" 'Notes v1.2.0' "#24 AK-24a: Notes der neuesten Version v1.2.0 im Body"
assert_absent "$body_24" 'Notes v1.0.0' "#24 AK-24a: Notes von N selbst nicht im Body (Intervall (N, V])"
pos_24() { printf '%s\n' "$body_24" | grep -nxF "## $1" | head -1 | cut -d: -f1; }
assert_true "$([ -n "$(pos_24 v1.2.0)" ] && [ -n "$(pos_24 v1.1.0)" ] && [ "$(pos_24 v1.2.0)" -lt "$(pos_24 v1.1.0)" ]; echo $?)" \
  "#24 AK-24a: je Version eine Überschrift, neueste zuerst"

# ── AK-24b: offener PR schon auf der neuesten Version → Branch unberührt (auch mit Fremd-Commit) ─────────────────────
world_24 b1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 >/dev/null
git -C "$C1_23" fetch -q origin && git -C "$C1_23" checkout -q -B fremd "origin/$BR_24"
printf 'mensch\n' > "$C1_23/mensch.txt"; git -C "$C1_23" add mensch.txt; git_23 -C "$C1_23" commit -q -m mensch
git -C "$C1_23" push -q origin "HEAD:refs/heads/$BR_24"
git -C "$C1_23" checkout -q main
printf 'weiter\n' > "$C1_23/main-weiter.txt"; git -C "$C1_23" add main-weiter.txt; git_23 -C "$C1_23" commit -q -m weiter
git -C "$C1_23" push -q origin main
branch_before_24="$(sha_24 "$BR_24")"; prs_before_24="$(cat "$GS_24/prs.json")"; : > "$GS_24/calls.log"
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 AK-24b: PR steht schon auf v1.1.0 → grün"
assert_true "$([ "$branch_before_24" = "$(sha_24 "$BR_24")" ]; echo $?)" "#24 AK-24b: Branch-SHA vor/nach gleich (Fremd-Commit bleibt, main weitergelaufen)"
assert_true "$([ "$prs_before_24" = "$(cat "$GS_24/prs.json")" ] && [ -z "$(writes_24)" ]; echo $?)" "#24 AK-24b: PR unverändert, kein schreibender Aufruf"
assert_contains_286 "$out_24" 'steht schon auf v1.1.0' "#24 AK-24b: Hinweis nennt den Grund"

# ── AK-24c: neuere Version ersetzt Fremd-Commits sichtbar ────────────────────────────────────────────────────────────
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 AK-24c: neuere Version v1.2.0 bei Fremd-Commit → grün (Lease auf den gelesenen SHA)"
assert_true "$(git -C "$ORIGIN_24" cat-file -e "refs/heads/$BR_24:mensch.txt" 2>/dev/null; [ $? -ne 0 ]; echo $?)" "#24 AK-24c: der Fremd-Commit ist nicht mehr auf dem Branch"
assert_true "$([ "$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^")" = "$(sha_24 main)" ]; echo $?)" "#24 AK-24c: neu aufgebaut auf dem aktuellen main"
assert_contains_286 "$(pr_body_24)" 'gehört dem Workflow' "#24 AK-24c: der Body nennt den Branch-Besitz"
assert_contains_286 "$(pr_body_24)" 'eigene Commits' "#24 AK-24c: der Body sagt, dass eigene Commits entfallen"

# Lease: hat sich der Branch zwischen Lesen und Push geändert, wird nicht überschrieben (git-Wrapper schiebt einen Fremd-Push dazwischen)
world_24 l1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
git -C "$C1_23" push -q origin "main:refs/heads/$BR_24"
LEASE_24="$W24/gitwrap"; mkdir -p "$LEASE_24"; REAL_GIT_24="$(command -v git)"
cat > "$LEASE_24/git" <<WRAP
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = push ] && [ ! -e "$LEASE_24/done" ]; then
    : > "$LEASE_24/done"
    "$REAL_GIT_24" -C "$ORIGIN_24" -c user.email=t@example.invalid -c user.name=t commit-tree -p refs/heads/$BR_24 -m dazwischen "refs/heads/$BR_24^{tree}" \
      | xargs -I{} "$REAL_GIT_24" -C "$ORIGIN_24" update-ref refs/heads/$BR_24 {}
  fi
done
exec "$REAL_GIT_24" "\$@"
WRAP
chmod +x "$LEASE_24/git"
racing_24="$(PATH="$LEASE_24:$PATH" upd_24 >/dev/null; echo $?)"; between_24="$(sha_24 "$BR_24")"
assert_true "$([ "$racing_24" -ne 0 ] && [ "$(git -C "$ORIGIN_24" log -1 --format=%s "$between_24")" = dazwischen ]; echo $?)" \
  "#24 E11: --force-with-lease – ein Push, der zwischen Lesen und Schreiben kam, wird nicht überschrieben"

# ── AK-24d: ohne Merge geschlossene Version wird nicht erneut angeboten ─────────────────────────────────────────────
world_24 d1; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 >/dev/null
jq 'map(.state = "CLOSED")' "$GS_24/prs.json" > "$GS_24/x" && mv "$GS_24/x" "$GS_24/prs.json"
git -C "$ORIGIN_24" update-ref -d "refs/heads/$BR_24"; : > "$GS_24/calls.log"
nochange_24 "AK-24d: v1.1.0 ohne Merge geschlossen, weiterhin neueste"
assert_contains_286 "$out_24" 'https://example.invalid/pull/1' "#24 AK-24d: der Hinweis verlinkt den geschlossenen PR"
add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
out_24="$(upd_24)"; rc_24=$?
assert_exit 0 "$rc_24" "#24 AK-24d: danach v1.2.0 → grün"
assert_true "$([ "$(open_prs_24)" = 1 ] && [ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" "#24 AK-24d: für v1.2.0 entsteht wieder ein PR"
# Eine Marke in den eingebetteten Release Notes sperrt nicht – nur die Marke im Kopf des Bodys zählt
world_24 d3; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
jq '(.[] | select(.tag_name == "v1.1.0") | .body) = "Beispiel:\n<!-- factory-update-version: v1.2.0 -->"' "$GS_24/releases.json" > "$GS_24/x" && mv "$GS_24/x" "$GS_24/releases.json"
upd_24 >/dev/null
assert_contains_286 "$(pr_body_24)" '<!-- factory-update-version: v1.2.0 -->' "#24 AK-24d (Voraussetzung): die Notes im PR für v1.1.0 zitieren die Marke von v1.2.0"
jq 'map(.state = "CLOSED")' "$GS_24/prs.json" > "$GS_24/x" && mv "$GS_24/x" "$GS_24/prs.json"
git -C "$ORIGIN_24" update-ref -d "refs/heads/$BR_24"
add_release_24 v1.2.0; jq '. + [{tag_name: "v1.2.0", draft: false, prerelease: false, body: "Notes v1.2.0", assets: [{name: "factory-release.json"}]}]' \
  "$GS_24/releases.json" > "$GS_24/x" && mv "$GS_24/x" "$GS_24/releases.json"
out_24="$(upd_24)"; rc_24=$?
assert_true "$([ "$rc_24" -eq 0 ] && [ "$(open_prs_24)" = 1 ] && [ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" \
  "#24 AK-24d: eine Marke in den Release Notes eines abgelehnten PRs sperrt die zitierte Version nicht"
# Ein Fork-PR mit gleichem Branch-Namen und der Marke im Body sperrt keine Version
world_24 d2; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
jq -n '[{number: 7, url: "https://example.invalid/pull/7", state: "CLOSED", title: "x", headRefName: "chore/factory-update",
         isCrossRepository: true, mergedAt: null, body: "<!-- factory-update-version: v1.1.0 -->"}]' > "$GS_24/prs.json"
upd_24 >/dev/null; assert_true "$([ "$(open_prs_24)" = 1 ]; echo $?)" "#24 AK-24d: geschlossener Fork-PR sperrt die Version nicht"
assert_true "$(grep -qE '^pr edit 7' "$GS_24/calls.log"; [ $? -ne 0 ]; echo $?)" "#24 E11: ein Fork-PR mit gleichem Branch-Namen wird nie bearbeitet"

# ── AK-24e: ohne factory.lock → No-op, ohne Token, ohne Netz ─────────────────────────────────────────────────────────
world_24 e1
out_24="$(env_23 "$C0_23" env PATH="$GH_STUB_24:$(stubs_23 curl):$PATH" GH_STUB_STATE="$GS_24" GH_STUB_TOKEN=x FACTORY_SYNC_TOKEN= bash "$UPD_24")"; rc_24=$?
assert_exit 0 "$rc_24" "#24 AK-24e: ohne factory.lock und ohne Token → No-op, grün"
assert_contains_286 "$out_24" 'kein factory.lock' "#24 AK-24e: der Hinweis nennt den Grund"
assert_true "$([ ! -s "$GS_24/calls.log" ]; echo $?)" "#24 AK-24e: kein gh-Aufruf (kein Netzzugriff)"

# ── F-24.3: Lock unlesbar → rot, kein Rückfall auf No-op ─────────────────────────────────────────────────────────────
for bad_24 in '{' '' '{"schema":1,"version":"kaputt"}'; do
  next_world_24 lockbad;printf '%s' "$bad_24" > "$C1_23/factory.lock"
  out_24="$(upd_24)"; rc_24=$?
  assert_exit 1 "$rc_24" "#24 F-24.3: Lock „${bad_24}“ → rot"
  assert_contains_286 "$out_24" 'factory.lock' "#24 F-24.3: die Meldung nennt factory.lock (Lock „${bad_24}“)"
  assert_true "$([ ! -s "$GS_24/calls.log" ]; echo $?)" "#24 F-24.3: vor jedem gh-Aufruf abgebrochen (Lock „${bad_24}“)"
done
world_24 g9; rm "$C1_23/factory.lock"; ln -s /nicht/vorhanden/lock "$C1_23/factory.lock"
upd_24 >/dev/null; assert_exit 1 "$?" "#24 F-24.3: hängender Symlink als Lock → rot (kein No-op)"


factory_lock_template_unchanged
test_group_finish; exit $?
