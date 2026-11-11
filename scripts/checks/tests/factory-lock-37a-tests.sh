#!/usr/bin/env bash
# factory-lock-37a-tests.sh – Testgruppe Factory-Issue #37, Teil a: Token und Release-Code trennen (Factory-ADR-063,
# Nachtrag 2026-10-31 E17–E22) – Verdrahtung, Doku-Guards, AK-37b, AK-37c
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-37a-tests.sh
# Fixtures und Helfer: lib/factory-lock-fixtures.sh; Teil b (Fail-closed-Zweige, F-37.1, guard/preflight): factory-lock-37b-tests.sh.

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
echo "Factory-Issue #37: Token und Release-Code trennen:"

# ── Verdrahtung: je Job, wo das Token verfügbar ist (AK-37a/e, F-37.3, F-37.4) ──────────────────────────────────────────
wf_job_37() { yq -o=json ".jobs.$2" "$1"; }
# Ausgabe erst fangen, dann prüfen: `yq … | grep -q` ist unter pipefail ein SIGPIPE-Race (lokal grün, sonst gelegentlich rot)
wf_has_line_37() { local out; out="$(yq "$2" "$1")"; grep -qxF -- "$3" <<< "$out"; }
wf_idx_37() { yq ".jobs.$2.steps | to_entries | .[] | select((.value.uses // .value.run // \"\") | test(\"$3\")) | .key" "$1" | head -1; }
wf_ok_37() { # $1 = Workflow-Datei; 0 = alle Anker stimmen
  local f="$1" j
  [ "$(yq -o=json -I=0 '.jobs | keys' "$f")" = '["guard","preflight","fetch","publish"]' ] || return 1
  for j in guard fetch; do [ -z "$(yq ".jobs.$j.environment // \"\"" "$f")" ] || return 1; done
  for j in preflight publish; do [ "$(yq ".jobs.$j.environment" "$f")" = factory-update ] || return 1; done
  [ "$(grep -c 'secrets\.FACTORY_SYNC_TOKEN' "$f")" = 3 ] || return 1
  [ "$(wf_job_37 "$f" guard | grep -c 'FACTORY_SYNC_TOKEN_REPO_SECRET": ".*secrets\.FACTORY_SYNC_TOKEN')" = 1 ] || return 1
  local fetch_job; fetch_job="$(wf_job_37 "$f" fetch)"; ! grep -q 'secrets\.' <<< "$fetch_job" || return 1
  [ "$(wf_job_37 "$f" preflight | grep -c 'secrets\.FACTORY_SYNC_TOKEN')" = 1 ] || return 1
  [ "$(wf_job_37 "$f" publish | grep -c 'secrets\.FACTORY_SYNC_TOKEN')" = 1 ] || return 1
  [ "$(yq -o=json -I=0 '.jobs.preflight.needs' "$f")" = '"guard"' ] || return 1
  [ "$(yq -o=json -I=0 '.jobs.fetch.needs' "$f")" = '"preflight"' ] || return 1
  [ "$(yq -o=json -I=0 '.jobs.publish.needs' "$f")" = '["preflight","fetch"]' ] || return 1
  [ "$(yq '.jobs.preflight.if' "$f")" = "needs.guard.outputs.lock == 'true'" ] || return 1
  [ "$(yq '.jobs.fetch.if' "$f")" = "needs.preflight.outputs.version != ''" ] || return 1
  for j in guard preflight fetch publish; do
    [ "$(yq ".jobs.$j.permissions.contents" "$f")" = read ] || return 1
    [ "$(yq ".jobs.$j.steps[0].with.ref" "$f")" = '${{ github.event.repository.default_branch }}' ] || return 1
    [ "$(yq ".jobs.$j.steps[0].with.persist-credentials" "$f")" = false ] || return 1
  done
  wf_has_line_37 "$f" '.jobs.guard.steps[].run' 'bash scripts/factory-update.sh guard' || return 1
  wf_has_line_37 "$f" '.jobs.preflight.steps[].run' 'bash scripts/factory-update.sh preflight' || return 1
  wf_has_line_37 "$f" '.jobs.fetch.steps[].run' 'bash scripts/factory-update.sh fetch "$VERSION" "$BASE_SHA" "$RUNNER_TEMP/update.bundle"' || return 1
  wf_has_line_37 "$f" '.jobs.publish.steps[].run' 'bash scripts/factory-update.sh publish "$VERSION" "$BASE_SHA" "$RUNNER_TEMP/bundle/update.bundle"' || return 1
  for j in preflight fetch publish; do
    [ "$(wf_idx_37 "$f" "$j" 'install-yq')" -lt "$(wf_idx_37 "$f" "$j" 'factory-update.sh')" ] || return 1
  done
  [ "$(wf_idx_37 "$f" publish 'download-artifact')" -lt "$(wf_idx_37 "$f" publish 'factory-update.sh')" ] || return 1
  # Re-run all jobs behält run_id: ohne overwrite scheitert der zweite Versuch von fetch am vorhandenen Artefakt
  [ "$(yq '.jobs.fetch.steps[] | select((.uses // "") | test("upload-artifact")) | .with.overwrite' "$f")" = true ] || return 1
}
wf_ok_37 "$WF_24"; assert_exit 0 "$?" "#37 AK-37a/e, F-37.3/4: Workflow je Job verdrahtet (Environment nur preflight/publish, Secret nie in fetch, main-Checkout)"
# Mutationsbeleg je tragender Zeile: derselbe Prüfer wird rot
mut_wf_37() { # $1 = Name, $2 = yq-Ausdruck
  cp "$WF_24" "$T23/mut37-$1.yml"; yq -i "$2" "$T23/mut37-$1.yml"
  assert_true "$(cmp -s "$WF_24" "$T23/mut37-$1.yml"; [ $? -ne 0 ]; echo $?)" "#37 Mutation $1: der Mutant unterscheidet sich vom Workflow (Voraussetzung)"
  wf_ok_37 "$T23/mut37-$1.yml"; assert_exit 1 "$?" "#37 AK-37 (Mutation): $1 → derselbe Prüfer ist rot"
}
mut_wf_37 secret-im-fetch '.jobs.fetch.env.FACTORY_SYNC_TOKEN = "${{ secrets.FACTORY_SYNC_TOKEN }}"'
mut_wf_37 secret-im-fetch-schritt '.jobs.fetch.steps[1].env.X = "${{ secrets.FACTORY_SYNC_TOKEN }}"'
mut_wf_37 environment-im-fetch '.jobs.fetch.environment = "factory-update"'
mut_wf_37 environment-im-guard '.jobs.guard.environment = "factory-update"'
mut_wf_37 environment-fehlt-im-publish 'del(.jobs.publish.environment)'
mut_wf_37 fetch-ohne-lesende-rechte 'del(.jobs.fetch.permissions)'
mut_wf_37 checkout-nicht-main '.jobs.publish.steps[0].with.ref = "${{ github.head_ref }}"'
mut_wf_37 publish-ohne-fetch '.jobs.publish.needs = "preflight"'
mut_wf_37 artefakt-ohne-overwrite 'del(.jobs.fetch.steps[] | select((.uses // "") | test("upload-artifact")) | .with.overwrite)'
mut_wf_37 noop-pfad-im-environment-job '.jobs.preflight.if = "true"'

# ── Doku-Guards: OPERATING.md §0.6 (AK-37e/g), ADR-063 (AK-37h) ───────────────────────────────────────────────────────
# Fließtext auf eine Zeile (Zeilenumbrüche der Prosa dürfen die Anker nicht lautlos brechen)
flat_37() { tr '\n' ' ' < "$1" | tr -s ' '; }
ops_ok_37() { # $1 = geglätteter Text von OPERATING.md
  local p
  for p in 'Environment `factory-update`' 'Deployment branches and tags' 'Regel **`main`**' '**Kein** gleichnamiges Repository-Secret' \
           'Bestand umziehen' 'das Repository-Secret gleichen Namens **löschen**' '**Test-Lauf:**' '`workflow_dispatch` **auf `main`**' 'keine geschützten Stellen im Manifest'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
  ! grep -qF -- 'als Repository-Secret **`FACTORY_SYNC_TOKEN`** hinterlegen' <<< "$1"
}
adr_ok_37() { # $1 = geglätteter Text von ADR-063
  local p
  for p in '**Restrisiko (ehrlich):**' 'Status: Accepted (2026-11-01' 'Ersetzt durch #37' 'Nachtrag 2026-10-31, E17/E20' \
           'Release selbst ist bösartig' 'Environment-Konfiguration' 'keine geschützten Stellen im Manifest'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
  ! grep -qF -- 'Status: Proposed, wird mit der Umsetzung' <<< "$1"
}
ops_37="$(flat_37 "$FACTORY_ROOT/docs/factory/OPERATING.md")"; adr_37="$(flat_37 "$FACTORY_ROOT/docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md")"
ops_ok_37 "$ops_37"; assert_exit 0 "$?" "#37 AK-37e/g: OPERATING.md §0.6 beschreibt Environment, Branch-Regel main, Umzug des Bestands, Test-Lauf – und nicht mehr „als Repository-Secret“"
# Mutanten per strip_literal_37 statt ${v//x/}: gleiches Ergebnis, aber linear (Factory-ADR-066 D7)
ops_ok_37 "$(strip_literal_37 "$ops_37" 'keine geschützten Stellen im Manifest')"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne „keine geschützten Stellen im Manifest“ in OPERATING.md ist derselbe Guard rot"
ops_ok_37 "$(strip_literal_37 "$ops_37" 'Bestand umziehen')"; assert_exit 1 "$?" "#37 AK-37g (Mutation): ohne den Abschnitt „Bestand umziehen“ ist derselbe Guard rot"
ops_ok_37 "$ops_37 Im Konsumenten-Repo als Repository-Secret **\`FACTORY_SYNC_TOKEN\`** hinterlegen"; assert_exit 1 "$?" "#37 AK-37e (Mutation): die alte Anweisung „als Repository-Secret hinterlegen“ macht den Guard rot"
adr_ok_37 "$adr_37"; assert_exit 0 "$?" "#37 AK-37h: ADR-063 nennt Restrisiko, Status Accepted und verweist in E4/E12 auf die neue Aufteilung"
adr_ok_37 "$(strip_literal_37 "$adr_37" 'keine geschützten Stellen im Manifest')"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne „keine geschützten Stellen im Manifest“ in ADR-063 E18 ist derselbe Guard rot"
adr_ok_37 "$(strip_literal_37 "$adr_37" 'Restrisiko (ehrlich)')"; assert_exit 1 "$?" "#37 AK-37h (Mutation): ohne den Abschnitt „Restrisiko (ehrlich)“ ist derselbe Guard rot"

# hostile_37 <welt> <payload-funktion> [token] – wie der CI-Job fetch: frischer Klon eines main, das die Skripte schon trägt (v1.1.0),
# Modus fetch im Klon (dort ersetzt factory-sync.sh sich selbst), ohne Token – mit dem dritten Argument „token“ als Gegenprobe mit Token.
# Das Release v1.2.0 hat in factory-sync.sh nach dem Neustart (--compose --check) die Nutzlast; Prüfung und Push dann per publish in C1.
# MARKER_37 protokolliert in MARKLOG_37 jeden Aufruf samt Token. Setzt out_24/rc_24 (von publish), FETCH_RC_37, BASE_37, BUNDLE_37, VER_37.
hostile_37() {
  world_24 "$1"
  MARKLOG_37="$W24/marker.log"; MARKER_37="$W24/marker.sh"; : > "$MARKLOG_37"
  printf '#!/bin/sh\necho "RAN FST=${FACTORY_SYNC_TOKEN:-} GH=${GH_TOKEN:-} $*" >> "%s"\nexit 0\n' "$MARKLOG_37" > "$MARKER_37"; chmod +x "$MARKER_37"
  factory_scripts_24 "$U23" "$UPD_24"
  add_release_24 v1.1.0
  sync_23 "$C1_23" v1.1.0 >/dev/null
  git -C "$C1_23" add -A && git_23 -C "$C1_23" commit -q -m "adopt v1.1.0" && git -C "$C1_23" push -q origin main
  { echo; "$2"; } >> "$U23/scripts/factory-sync.sh"
  add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
  VER_37=v1.2.0; BASE_37="$(git -C "$ORIGIN_24" rev-parse main)"; CL_37="$W24/clone37"; BUNDLE_37="$W24/u.bundle"
  git clone -q "$C1_23" "$CL_37"
  if [ "${3:-}" = token ]; then
    env_23 "$CL_37" env FACTORY_SYNC_TOKEN="$GOOD_TOKEN_24" bash "$CL_37/scripts/factory-update.sh" fetch "$VER_37" "$BASE_37" "$BUNDLE_37" >/dev/null
  else
    env_23 "$CL_37" env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN bash "$CL_37/scripts/factory-update.sh" fetch "$VER_37" "$BASE_37" "$BUNDLE_37" >/dev/null
  fi
  FETCH_RC_37=$?
  pub_37 "${4:-}"
}
payload_config_37() { cat <<EOF
git -C "\$FACTORY_DIR" config core.fsmonitor "$MARKER_37"
git -C "\$FACTORY_DIR" config filter.evil.clean "$MARKER_37 filter; cat"
printf '* filter=evil\n' >> "\$FACTORY_DIR/.git/info/attributes"
mkdir -p "\$FACTORY_DIR/.git/hooks"
for h in pre-commit commit-msg pre-push post-commit reference-transaction; do printf '#!/bin/sh\n"$MARKER_37" hook-%s\nexit 0\n' "\$h" > "\$FACTORY_DIR/.git/hooks/\$h"; chmod +x "\$FACTORY_DIR/.git/hooks/\$h"; done
git -C "\$FACTORY_DIR" config core.hooksPath "\$FACTORY_DIR/.git/hooks"
true
EOF
}
payload_foreign_37() { printf '%s\n' 'printf evil > "$FACTORY_DIR/EVIL.txt"'; }
payload_symlink_37() { printf '%s\n' 'rm -f "$FACTORY_DIR/scripts/tool.sh"; ln -s /etc/hosts "$FACTORY_DIR/scripts/tool.sh"'; }
payload_tamper_37() { printf '%s\n' 'printf "echo boese\n" >> "$FACTORY_DIR/scripts/tool.sh"'; }
no_token_marker_37() { ! grep -qE 'FST=[^ ]|GH=[^ ]' "$MARKLOG_37"; }

# ── AK-37b: Git-Konfiguration, Hooks und .git/info des Release erreichen das Token nie ────────────────────────────────
hostile_37 hc1 payload_config_37
assert_true "$([ "$FETCH_RC_37" -eq 0 ] && [ "$rc_24" -eq 0 ] && [ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" "#37 AK-37b/d: Release mit böser Git-Konfiguration/Hooks/Filter → der Update-PR entsteht trotzdem"
assert_true "$([ -s "$MARKLOG_37" ]; echo $?)" "#37 AK-37b (Voraussetzung): der Marker-Befehl des Release lief in der Abholung (Nutzlast wurde ausgeführt)"
assert_true "$(no_token_marker_37; echo $?)" "#37 AK-37b: kein Marker-Befehl (fsmonitor, Filter, Hooks) sah je ein Token – weder in der Abholung noch in publish"
assert_true "$([ "$(git -C "$ORIGIN_24" log -1 --format='%an|%ae|%s' "refs/heads/$BR_24")" = 'factory-update|factory-update@localhost|chore: factory auf v1.2.0 heben' ]; echo $?)" "#37 AK-37b: der Commit auf dem Branch trägt feste Identität und Nachricht"
tree_37="$(git -C "$ORIGIN_24" ls-tree -r --name-only "refs/heads/$BR_24")"
assert_true "$(grep -qE 'EVIL|\.git/' <<< "$tree_37"; [ $? -ne 0 ]; echo $?)" "#37 AK-37b: nichts aus .git/ des Klons gelangt in den Branch"
# Gegenprobe: lief die Abholung mit Token (ein Job für beides), sähe derselbe Marker-Befehl es – die Trennung ist es, die schützt
hostile_37 hc2 payload_config_37 token
assert_exit 1 "$(no_token_marker_37; echo $?)" "#37 AK-37b (Gegenprobe): mit Token in der Abholung sieht der Marker-Befehl des Release das Token – die Trennung ist wirksam"
assert_true "$(grep -qF "FST=$GOOD_TOKEN_24" "$MARKLOG_37"; echo $?)" "#37 AK-37b (Gegenprobe): der Marker lief tatsächlich mit dem Token"

# ── AK-37c: Übergabe als Daten, Prüfung vor dem Push ─────────────────────────────────────────────────────────────────
hostile_refused_37() { hostile_37 "$1" "$2" "" "${4:-}"; refused_ok_37 "$3"; }
hostile_refused_37 hf1 payload_foreign_37 'unerwarteter Pfad'; assert_exit 0 "$?" "#37 AK-37c: Datei außerhalb der Übernahme-Liste → rot, kein Push, kein PR"
assert_contains_286 "$out_24" 'EVIL.txt' "#37 AK-37c: die Meldung nennt den unerwarteten Pfad"
mutant_37 pfad 's#comm -23 - "\$WORK/allowed.txt"#cat >/dev/null#'
hostile_refused_37 hf2 payload_foreign_37 'unerwarteter Pfad' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Pfadprüfung ist derselbe Guard rot"
hostile_refused_37 hs1 payload_symlink_37 'Symlink oder Submodul'; assert_exit 0 "$?" "#37 AK-37c: Symlink an erlaubtem Pfad → rot, kein Push"
mutant_37 symlink 's#\[\[ ! "\$mode" =~ \$BUNDLE_MODE_FORBIDDEN_RE \]\]#true#'
hostile_refused_37 hs2 payload_symlink_37 'Symlink oder Submodul' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Modusprüfung ist derselbe Guard rot"
hostile_refused_37 ht1 payload_tamper_37 'stimmen nicht mit dem Manifest'; assert_exit 0 "$?" "#37 AK-37c: veränderte Manifest-Datei → rot, kein Push"
mutant_37 hash 's#\[ -z "\$\(fl_diff_hashes "\$WORK/want.tsv" "\$WORK/quarantine.tsv"\)" \]#true#'
hostile_refused_37 ht2 payload_tamper_37 'stimmen nicht mit dem Manifest' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Hash-Prüfung ist derselbe Guard rot"

# Von Hand gebaute Bundles gegen den Modus publish (Token-Seite): Übergabe-Commit verfälscht (bundle_37: lib/factory-lock-fixtures.sh)
bundle_refused_37() { bundle_37 "$1" "$2"; pub_37 "${4:-}"; refused_ok_37 "$3"; } # <welt> <snippet> <meldung> [<skript>]
bundle_37 pb0; pub_37
assert_true "$([ "$rc_24" -eq 0 ] && [ "$(lock_on_branch_24)" = v1.1.0 ] && [ "$(open_prs_24)" = 1 ]; echo $?)" "#37 AK-37d (Voraussetzung): legitimes Bundle → publish pusht und legt den PR an"
LOCKBAD_37='jq ".version=\"v9.9.9\"" factory.lock > x && mv x factory.lock && git add -A && git -c user.email=t@x -c user.name=t commit -q --amend --no-edit'
bundle_refused_37 pb1 "$LOCKBAD_37" 'nicht das Manifest'; assert_exit 0 "$?" "#37 AK-37c: factory.lock der Übergabe ≠ frisch geholtes Manifest → rot, kein Push"
mutant_37 lock 's#cmp -s - "\$WORK/manifest.json"#cat >/dev/null#'
bundle_refused_37 pb2 "$LOCKBAD_37" 'nicht das Manifest' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Lock-Vergleich ist derselbe Guard rot"
TWO_37='git -c user.email=t@x -c user.name=t commit -q --allow-empty -m zweiter'
bundle_refused_37 pb3 "$TWO_37" 'nicht genau ein Commit'; assert_exit 0 "$?" "#37 AK-37c: zwei Commits in der Übergabe → rot, kein Push"
mutant_37 anzahl 's#\[ "\$\(git rev-list --count "\$base..\$QUARANTINE_SHA"\)" = 1 \]#true#; s#\[ "\$\(git rev-parse "\$QUARANTINE_SHA\^"\)" = "\$base" \]#true#'
bundle_refused_37 pb4 "$TWO_37" 'nicht genau ein Commit' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Commit-/Elternteil-Prüfung ist derselbe Guard rot"
moved_37() { bundle_37 "$1"; git_23 -C "$C1_23" commit -q --allow-empty -m weiter && git -C "$C1_23" push -q origin main; pub_37 "${2:-}"; refused_ok_37 'bewegt'; }
moved_37 pm1; assert_exit 0 "$?" "#37 AK-37c: main bewegt sich zwischen Abholung und Prüfung → rot, kein Push (der nächste Lauf baut neu auf)"
mutant_37 bewegt 's#\[ "\$\(git rev-parse -q --verify "refs/remotes/origin/\$BASE_BRANCH"\)" = "\$base" \]#true#'
moved_37 pm2 "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Prüfung der Basis ist derselbe Guard rot"
# Autor, Nachricht und Header des Release-Codes gelangen nicht in den Branch (commit-tree mit fester Identität)
META_37='git -c user.email=evil@x -c user.name=Boese commit -q --amend --no-edit --author="Boese <evil@x>" -m "boese Nachricht"'
meta_ok_37() { [ "$rc_24" -eq 0 ] && [ "$(git -C "$ORIGIN_24" log -1 --format='%an|%s' "refs/heads/$BR_24")" = 'factory-update|chore: factory auf v1.1.0 heben' ]; }
bundle_37 pc1 "$META_37"; pub_37; meta_ok_37; assert_exit 0 "$?" "#37 AK-37c: Autor und Nachricht der Übergabe werden verworfen (neuer Commit mit fester Identität)"
mutant_37 commit 's#"\$sha:refs/heads/\$UPDATE_BRANCH"#"$QUARANTINE_SHA:refs/heads/$UPDATE_BRANCH"#'
bundle_37 pc2 "$META_37"; pub_37 "$MUT37"; meta_ok_37; assert_exit 1 "$?" "#37 AK-37c (Mutation): wird der Commit aus dem Bundle gepusht, ist derselbe Guard rot"

# craft_protected_manifest_37 – im Klon: Datei unter tasks/ (Projektbereich) hinzufügen, ins Release-Manifest und in factory.lock
# aufnehmen (gültiger Hash), Commit ersetzen – ein Release, das die Sperre des Projektbesitzes umgehen will
craft_protected_manifest_37() {
  local hash
  printf x > tasks/x.md
  hash="$(shasum -a 256 tasks/x.md | cut -c1-64)"
  jq --arg h "$hash" '.files += [{path: "tasks/x.md", sha256: $h}]' "$R23/v1.1.0/factory-release.json" > "$R23/m.json" \
    && mv "$R23/m.json" "$R23/v1.1.0/factory-release.json" && cp "$R23/v1.1.0/factory-release.json" factory.lock \
    && git add -A && git -c user.email=t@x -c user.name=t commit -q --amend --no-edit
}
# Manifest des Release liefert eine geschützte Stelle (Projektbereich tasks/): factory-sync.sh lehnt das ab, publish muss es ebenso tun
PROT_37=craft_protected_manifest_37
bundle_refused_37 pr1 "$PROT_37" 'geschützte'; assert_exit 0 "$?" "#37 AK-37c: Manifest mit geschützter Stelle (tasks/) → rot, kein Push (wie factory-sync.sh)"
mutant_37 geschuetzt 's#fl_protected_findings "\$WORK/manifest.json"#printf ""#'
bundle_refused_37 pr2 "$PROT_37" 'geschützte' "$MUT37"; assert_exit 1 "$?" "#37 AK-37c (Mutation): ohne Prüfung geschützter Stellen ist derselbe Guard rot"

# Drift-Guard: die zusammengesetzten Ziele, die publish zulässt, sind genau die von factory-sync.sh geschriebenen
targets_ok_37() { # $1 = factory-update.sh, $2 = factory-sync.sh
  local a b
  a="$(sed -n 's/^COMPOSED_TARGETS=(\(.*\))$/\1/p' "$1" | tr ' ' '\n' | LC_ALL=C sort)"
  b="$(sed -n 's/^SETTINGS_TARGET="\(.*\)"$/\1/p; s/^GITIGNORE_TARGET="\(.*\)"$/\1/p' "$2" | LC_ALL=C sort)"
  [ -n "$a" ] && [ "$a" = "$b" ]
}
targets_ok_37 "$UPD_24" "$FACTORY_ROOT/scripts/factory-sync.sh"; assert_exit 0 "$?" "#37 E18: COMPOSED_TARGETS in factory-update.sh == SETTINGS_TARGET/GITIGNORE_TARGET in factory-sync.sh"
sed 's#^COMPOSED_TARGETS=.*#COMPOSED_TARGETS=(.claude/settings.json)#' "$UPD_24" > "$T23/m37-targets-a.sh"
targets_ok_37 "$T23/m37-targets-a.sh" "$FACTORY_ROOT/scripts/factory-sync.sh"; assert_exit 1 "$?" "#37 E18 (Mutation): fehlt ein Ziel in factory-update.sh, ist der Drift-Guard rot"
sed 's#^GITIGNORE_TARGET=.*#GITIGNORE_TARGET=".gitignore.neu"#' "$FACTORY_ROOT/scripts/factory-sync.sh" > "$T23/m37-targets-b.sh"
targets_ok_37 "$UPD_24" "$T23/m37-targets-b.sh"; assert_exit 1 "$?" "#37 E18 (Mutation): ändert factory-sync.sh ein Ziel, ist der Drift-Guard rot"

factory_lock_template_unchanged
test_group_finish; exit $?
