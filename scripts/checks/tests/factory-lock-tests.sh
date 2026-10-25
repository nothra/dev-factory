#!/usr/bin/env bash
# factory-lock-tests.sh – Tests zu Abholen, factory.lock und Integritäts-Gate (Factory-Issue #23)
#
# Wird von scripts/checks/tests/run-tests.sh gesourct (gemeinsame Zähler und Helfer). Alles läuft offline gegen
# ein Fixture-Factory-Repo (lokales Git-Repo mit zwei Tags) und handgebaute Release-Manifeste; Netzzugriffe sind über
# FACTORY_UPSTREAM_GIT_URL/FACTORY_RELEASE_BASE_URL (`file://`) umgelenkt. Die Suite ist konsumenten-neutral: sie
# liest nur Dateien der Seite `factory` und baut alles Übrige selbst.
# Erwartet: FACTORY_ROOT, HAS_YQ, die Helfer aus lib/assert-helpers.sh.

echo ""
echo "Factory-Issue #23: Abholen, factory.lock, Integritäts-Gate:"

if [ "$HAS_YQ" -ne 1 ]; then
  skip_yq "#23 Abholen/Integritäts-Gate (braucht yq für upstream.repo)"
else

SYNC_23="$FACTORY_ROOT/scripts/factory-sync.sh"
GATE_23="$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh"
OWN_23="$FACTORY_ROOT/scripts/checks/ownership-check.sh"
T23="$(mktemp -d)"

git_23() { git -c user.email=t@example.invalid -c user.name=t "$@"; }

# mk_manifest_23 <upstream> <tag> <ziel> – Release-Manifest eines Tags (Pfade und Hashes aus dem Tag, nicht aus dem Arbeitsbaum)
mk_manifest_23() {
  local up="$1" tag="$2" dest="$3" p tsv
  tsv="$(mktemp)"
  git -C "$up" ls-tree -r --name-only "$tag" | while IFS= read -r p; do
    printf '%s\t%s\n' "$p" "$(git -C "$up" show "$tag:$p" | shasum -a 256 | cut -d' ' -f1)"
  done > "$tsv"
  mkdir -p "$(dirname "$dest")"
  jq -n --arg tag "$tag" --arg commit "$(git -C "$up" rev-parse "$tag^{commit}")" --rawfile tsv "$tsv" \
    '{schema: 1, repo: "nothra/dev-factory", version: $tag, commit: $commit,
      files: ($tsv | split("\n") | map(select(length > 0) | split("\t") | {path: .[0], sha256: .[1]}))}' > "$dest"
  rm -f "$tsv"
}

# Vorlage: Upstream mit v1.0.0/v2.0.0, Manifeste, Konsument ohne Lock (C0) und Konsument nach Abholung von v1.0.0 (C1)
build_template_23() {
  local t="$1" u="$1/U" r="$1/R" c
  mkdir -p "$u/docs/factory" "$u/scripts" "$u/.claude"
  git -C "$u" init -q -b main
  printf '# Development Factory · v1.0.0\n' > "$u/docs/factory/FACTORY.md"
  printf '#!/usr/bin/env bash\necho tool v1\n' > "$u/scripts/tool.sh"; chmod +x "$u/scripts/tool.sh"
  printf 'echo old\n' > "$u/scripts/old.sh"
  printf '{"permissions":{"allow":["Bash(a)"]}}\n' > "$u/.claude/settings.factory.json"
  printf 'factory-ignore/\n' > "$u/docs/factory/gitignore.factory"
  git -C "$u" add -A && git_23 -C "$u" commit -q -m v1 && git -C "$u" tag v1.0.0
  mk_manifest_23 "$u" v1.0.0 "$r/v1.0.0/factory-release.json"
  printf '# Development Factory · v2.0.0\n' > "$u/docs/factory/FACTORY.md"
  printf '#!/usr/bin/env bash\necho tool v2\n' > "$u/scripts/tool.sh"
  git -C "$u" rm -q scripts/old.sh
  printf 'echo new\n' > "$u/scripts/new.sh"
  printf '{"permissions":{"allow":["Bash(a)","Bash(b)"]}}\n' > "$u/.claude/settings.factory.json"
  git -C "$u" add -A && git_23 -C "$u" commit -q -m v2 && git -C "$u" tag v2.0.0
  mk_manifest_23 "$u" v2.0.0 "$r/v2.0.0/factory-release.json"

  c="$t/C0"; mkdir -p "$c/.claude" "$c/tasks"
  git -C "$c" init -q -b main
  printf 'upstream:\n  repo: nothra/dev-factory\n' > "$c/factory.defaults.yml"
  printf '{"permissions":{"allow":["Edit(x)"]}}\n' > "$c/.claude/settings.project.json"
  printf 'proj-ignore/\n' > "$c/.gitignore.project"
  printf '# Projekt\n' > "$c/README.md"; printf 'task\n' > "$c/tasks/t.md"
  git -C "$c" add -A && git_23 -C "$c" commit -q -m init
  cp -R "$c" "$t/C1"
  FACTORY_DIR="$t/C1" FACTORY_UPSTREAM_GIT_URL="file://$u" FACTORY_RELEASE_BASE_URL="file://$r" bash "$SYNC_23" v1.0.0 >/dev/null 2>&1
  git -C "$t/C1" add -A && git_23 -C "$t/C1" commit -q -m "adopt v1"
}
build_template_23 "$T23/tmpl"

# world_23 <name> – frische Kopie der Vorlage; setzt U23/R23/C0_23/C1_23
world_23() {
  cp -R "$T23/tmpl" "$T23/$1"
  U23="$T23/$1/U"; R23="$T23/$1/R"; C0_23="$T23/$1/C0"; C1_23="$T23/$1/C1"
}
# env_23 <wurzel> <befehl…> – Befehl mit umgelenktem Factory-Repo und Release-Base ausführen (Ausgabe stdout+stderr)
env_23() {
  local root="$1"; shift
  FACTORY_DIR="$root" FACTORY_UPSTREAM_GIT_URL="file://$U23" FACTORY_RELEASE_BASE_URL="file://$R23" "$@" 2>&1
}
sync_23() { local root="$1"; shift; env_23 "$root" bash "$SYNC_23" "$@"; }
gate_23() { local root="$1"; shift; env_23 "$root" bash "$GATE_23" "$@"; }
# snap_23 <wurzel> – Prüfsumme über alle Dateien außer .git (Inhalt + Pfad)
snap_23() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(shasum -a 256 < "$f" | cut -c1-64)" "$f"; done | shasum -a 256 | cut -c1-64); }
# stubs_23 <name…> – Verzeichnis mit Stubs, die sofort scheitern (Messung brechen, Lesson nothra/tch-gastro-services#319)
stubs_23() { local d; d="$(mktemp -d "$T23/stub.XXXXXX")"; local n; for n in "$@"; do printf '#!/bin/sh\nexit 1\n' > "$d/$n"; chmod +x "$d/$n"; done; printf '%s' "$d"; }
# mut_manifest_23 <tag> <jq-filter> – Manifest des Tags in der aktuellen Welt verändern
mut_manifest_23() { jq "$2" "$R23/$1/factory-release.json" > "$R23/$1/x" && mv "$R23/$1/x" "$R23/$1/factory-release.json"; }

# ── AK2.2a/AK2.1a: Erstabholung ohne abweichende Dateien braucht keinen Schalter ───────────────────────────────────────
world_23 w1
out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.2a: Abholung von v1.0.0 ohne Lock und ohne Abweichung → Exit 0 (kein Schalter nötig)"
cmp -s "$C0_23/factory.lock" "$R23/v1.0.0/factory-release.json"
assert_exit 0 "$?" "#23 AK2.1a: factory.lock ist eine Byte-Kopie des Release-Manifests"
assert_true "$([ "$(jq -r '[.repo, .version, .commit] | join(" ")' "$C0_23/factory.lock")" = "nothra/dev-factory v1.0.0 $(git -C "$U23" rev-parse v1.0.0^{commit})" ]; echo $?)" \
  "#23 AK2.1a: Lock nennt Quell-Repo, Tag und Commit-SHA des Tags"
assert_true "$([ "$(head -1 "$C0_23/docs/factory/FACTORY.md")" = "# Development Factory · v1.0.0" ]; echo $?)" "#23 AK2.1a: die Versionszeile in FACTORY.md nennt denselben Tag"
assert_true "$([ -x "$C0_23/scripts/tool.sh" ]; echo $?)" "#23 AK2.2a: das Ausführbar-Bit übernommener Skripte bleibt erhalten"
jq -e '.permissions.allow | (index("Bash(a)") != null and index("Edit(x)") != null)' "$C0_23/.claude/settings.json" >/dev/null 2>&1
assert_exit 0 "$?" "#23 AK2.3b: settings.json nach der Abholung aus Factory- und Projekt-Fragment zusammengesetzt"
assert_true "$([ "$(cat "$C0_23/.gitignore")" = "$(printf 'factory-ignore/\nproj-ignore/')" ]; echo $?)" "#23 AK2.3b: .gitignore nach der Abholung zusammengesetzt"
git -C "$C0_23" add -A
out_23="$(FACTORY_DIR="$C0_23" bash "$OWN_23" 2>&1)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.1c: ownership-check.sh ist nach der Abholung im Lock-Modus grün"
assert_contains_286 "$out_23" 'Modus: Lock' "#23 AK2.1c: der Ownership-Check läuft tatsächlich im Lock-Modus"
gate_23 "$C0_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.1b: lokale Stufe grün nach der Abholung"
gate_23 "$C0_23" --ci >/dev/null; assert_exit 0 "$?" "#23 AK2.1b: CI-Stufe grün nach der Abholung (Lock == Manifest)"
for f_23 in README.md tasks/t.md .claude/settings.project.json .gitignore.project factory.defaults.yml; do
  cmp -s "$C0_23/$f_23" "$T23/tmpl/C0/$f_23"
  assert_exit 0 "$?" "#23 AK2.3: $f_23 (Projektbesitz) nach der Abholung unverändert"
done

# ── AK2.5a: lokale Stufe lehnt Änderung und Löschung ab ──────────────────────────────────────────────────────────────
world_23 w2
printf 'echo manipuliert\n' >> "$C1_23/scripts/tool.sh"
out_23="$(gate_23 "$C1_23")"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5a: geänderte übernommene Datei → lokale Stufe rot"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 AK2.5a: die Meldung nennt die geänderte Datei"
assert_contains_286 "$out_23" 'Änderung gehört nach' "#23 AK2.5a: die Meldung nennt den Hinweis auf das Factory-Repo"
assert_contains_286 "$out_23" 'nothra/dev-factory' "#23 AK2.5a: der Hinweis nennt das Factory-Repo"
git -C "$C1_23" checkout -q -- scripts/tool.sh
rm "$C1_23/docs/factory/gitignore.factory"
out_23="$(gate_23 "$C1_23")"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5a: gelöschte übernommene Datei → lokale Stufe rot"
assert_contains_286 "$out_23" 'docs/factory/gitignore.factory' "#23 AK2.5a: die Meldung nennt die gelöschte Datei"
git -C "$C1_23" checkout -q -- docs/factory/gitignore.factory
rm "$C1_23/scripts/tool.sh"; ln -s ../README.md "$C1_23/scripts/tool.sh"
out_23="$(gate_23 "$C1_23")"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5a: übernommene Datei durch Symlink ersetzt → rot (nur reguläre Dateien zählen)"
assert_contains_286 "$out_23" 'keine reguläre Datei' "#23 AK2.5a: die Meldung nennt den Symlink-Grund"
rm "$C1_23/scripts/tool.sh"; git -C "$C1_23" checkout -q -- scripts/tool.sh
gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.5a: nach der Wiederherstellung wieder grün"

# ── AK-28b: zusammengesetzte Dateien müssen den Fragmenten entsprechen ────────────────────────────────────────────────
printf '\n# drift\n' >> "$C1_23/.gitignore"
out_23="$(gate_23 "$C1_23")"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK-28b: abweichende .gitignore → lokale Stufe rot"
assert_contains_286 "$out_23" '.gitignore' "#23 AK-28b: die Meldung nennt .gitignore"
git -C "$C1_23" checkout -q -- .gitignore
jq '.permissions.allow += ["Bash(drift)"]' "$C1_23/.claude/settings.json" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/.claude/settings.json"
out_23="$(gate_23 "$C1_23")"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK-28b: abweichende settings.json → lokale Stufe rot"
assert_contains_286 "$out_23" 'settings.json' "#23 AK-28b: die Meldung nennt settings.json"
git -C "$C1_23" checkout -q -- .claude/settings.json
printf '{"permissions":{"allow":["Edit(neu)"]}}\n' > "$C1_23/.claude/settings.project.json"
gate_23 "$C1_23" >/dev/null; assert_exit 1 "$?" "#23 AK-28b: geändertes Projekt-Fragment ohne neues Zusammensetzen → rot"
git -C "$C1_23" checkout -q -- .claude/settings.project.json

# ── AK2.5b: CI-Stufe fängt Datei + Hash gemeinsam geändert ────────────────────────────────────────────────────────────
printf 'echo manipuliert\n' >> "$C1_23/scripts/tool.sh"
new_hash_23="$(shasum -a 256 < "$C1_23/scripts/tool.sh" | cut -c1-64)"
jq --arg h "$new_hash_23" '(.files[] | select(.path == "scripts/tool.sh") | .sha256) = $h' "$C1_23/factory.lock" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.5b (Voraussetzung): Datei + Hash gemeinsam geändert passiert die lokale Stufe"
out_23="$(gate_23 "$C1_23" --ci)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5b: CI-Stufe lehnt Datei + Hash gemeinsam geändert ab"
assert_contains_286 "$out_23" 'weicht vom Release-Manifest' "#23 AK2.5b: die Meldung nennt den Manifest-Abgleich"
# Mutationsbeleg: ohne den Manifest-Vergleich bleibt derselbe Fall grün – der Test misst also den Vergleich
MUT_23="$T23/mut"; mkdir -p "$MUT_23/scripts/checks" "$MUT_23/scripts/lib"
cp "$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh" "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$MUT_23/scripts/checks/"
cp "$FACTORY_ROOT/scripts/factory-sync.sh" "$MUT_23/scripts/"
cp "$FACTORY_ROOT/scripts/lib/factory-lock.sh" "$FACTORY_ROOT/scripts/lib/gate-config.sh" "$MUT_23/scripts/lib/"
sed 's|if \[ "\$(jq -S . "\$LOCK_FILE")" != "\$(jq -S . "\$WORK_DIR/manifest.json")" \]; then|if false; then|' "$MUT_23/scripts/checks/factory-integrity-check.sh" > "$MUT_23/x" && mv "$MUT_23/x" "$MUT_23/scripts/checks/factory-integrity-check.sh"
assert_true "$(grep -qF 'if false; then' "$MUT_23/scripts/checks/factory-integrity-check.sh"; echo $?)" "#23 AK2.5b (Mutation): der Manifest-Vergleich ist im Mutanten ersetzt"
env_23 "$C1_23" bash "$MUT_23/scripts/checks/factory-integrity-check.sh" --ci >/dev/null
assert_exit 0 "$?" "#23 AK2.5b (Mutation): ohne Manifest-Vergleich besteht die CI-Stufe die Manipulation – der Vergleich ist wirksam"
git -C "$C1_23" checkout -q -- scripts/tool.sh factory.lock
# Pfadmenge: Datei im Lock ergänzt bzw. entfernt (je Stufe eine Gegenprobe)
jq '.files |= map(select(.path != "scripts/tool.sh"))' "$C1_23/factory.lock" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.1b: Datei aus dem Lock entfernt → lokale Stufe sieht es nicht (Voraussetzung)"
gate_23 "$C1_23" --ci >/dev/null; assert_exit 1 "$?" "#23 AK2.1b: Datei aus dem Lock entfernt → CI-Stufe rot (Pfadmenge ≠ Manifest)"
git -C "$C1_23" checkout -q -- factory.lock
jq '.files += [{"path":"scripts/extra.sh","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]' "$C1_23/factory.lock" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 1 "$?" "#23 AK2.1b: Datei im Lock ergänzt, im Repo nicht vorhanden → lokale Stufe rot"
git -C "$C1_23" checkout -q -- factory.lock
jq '.repo = "evil/fork"' "$C1_23/factory.lock" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/factory.lock"
out_23="$(gate_23 "$C1_23" --ci)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 F-23.1: lock.repo ≠ upstream.repo → CI-Stufe rot (der Lock ist nie die Quelle)"
assert_contains_286 "$out_23" 'upstream.repo' "#23 F-23.1: die Meldung nennt upstream.repo"
git -C "$C1_23" checkout -q -- factory.lock

# ── AK2.5c / F-23.2: Moduswahl ───────────────────────────────────────────────────────────────────────────────────────
world_23 w3
mkdir -p "$T23/w3/bare"
out_23="$(FACTORY_DIR="$T23/w3/bare" bash "$GATE_23" 2>&1)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.5c: ohne factory.lock (Factory-Repo) → No-op, Exit 0"
assert_contains_286 "$out_23" 'kein factory.lock' "#23 AK2.5c: der No-op nennt den Grund"
out_23="$(FACTORY_DIR="$T23/w3/bare" bash "$GATE_23" --ci 2>&1)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.5c: auch die CI-Stufe ist im Factory-Repo ein No-op, Exit 0"
printf '{' > "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 2 "$?" "#23 F-23.2: ungültiges JSON im Lock → Exit 2 (kein Rückfall auf No-op)"
printf '' > "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 2 "$?" "#23 F-23.2: leerer Lock → Exit 2"
printf '{"schema":2,"files":[]}' > "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 2 "$?" "#23 F-23.2: Lock mit unbekanntem schema → Exit 2"
rm -f "$C1_23/factory.lock"; ln -s /nicht/vorhanden/lock "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 2 "$?" "#23 F-23.2/E8: hängender Symlink als Lock gilt als Lock und ist unlesbar → Exit 2 (nicht No-op)"
out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 F-23.2: Abholung mit unlesbarem Lock bricht ab"
rm -f "$C1_23/factory.lock"
jq '.files[0].path = "../escape"' "$T23/tmpl/C1/factory.lock" > "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 2 "$?" "#23 F-23.3: Lock mit Pfad „..“ → Exit 2"

# ── AK2.8/AK2.5d: offline und fail-closed ────────────────────────────────────────────────────────────────────────────
world_23 w4
STUB_NET_23="$(stubs_23 curl git)"
PATH="$STUB_NET_23:$PATH" gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.8: lokale Stufe ist mit scheiternden curl/git-Stubs grün (offline)"
PATH="$STUB_NET_23:$PATH" FACTORY_DIR="$C1_23" bash "$FACTORY_ROOT/scripts/factory-sync.sh" --compose --check >/dev/null 2>&1
assert_exit 0 "$?" "#23 AK2.8: --compose --check läuft offline"
PATH="$(stubs_23 curl):$PATH" FACTORY_DIR="$C1_23" bash "$OWN_23" >/dev/null 2>&1; assert_exit 0 "$?" "#23 AK2.8: ownership-check.sh läuft offline"
out_23="$(PATH="$STUB_NET_23:$PATH" gate_23 "$C1_23" --ci)"; rc_23=$?
assert_exit 2 "$rc_23" "#23 AK2.5d: CI-Stufe mit scheiterndem Download → Exit 2 (fail-closed)"
assert_contains_286 "$out_23" 'nicht abrufbar' "#23 AK2.5d: klare Meldung, dass das Manifest nicht abrufbar ist"
rm -rf "$R23/v1.0.0"
gate_23 "$C1_23" --ci >/dev/null; assert_exit 2 "$?" "#23 AK2.5d: Tag ohne Manifest-Asset → CI-Stufe Exit 2"
FACTORY_RELEASE_BASE_URL="file:///nicht/vorhanden" FACTORY_DIR="$C1_23" bash "$GATE_23" --ci >/dev/null 2>&1
assert_exit 2 "$?" "#23 AK2.5d: Factory-Repo nicht erreichbar → CI-Stufe Exit 2"
mut_json_23() { printf '%s' "$1" > "$R23/v1.0.0/factory-release.json"; }
mkdir -p "$R23/v1.0.0"; mut_json_23 'kein json'
gate_23 "$C1_23" --ci >/dev/null; rc_23=$?
assert_exit 2 "$rc_23" "#23 FS-T2.1: Manifest kein gültiges JSON → CI-Stufe Exit 2"

# ── AK2.6 / AK2.2c / F2: Hebung N → N+1 ──────────────────────────────────────────────────────────────────────────────
world_23 w5
printf 'meins\n' > "$C1_23/docs-fremd.txt"; mkdir -p "$C1_23/docs/factory"; printf 'tabelle\n' > "$C1_23/docs/factory/OWNERSHIP.md"
git -C "$C1_23" add -A; git_23 -C "$C1_23" commit -q -m fremd
out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.6: Hebung von v1.0.0 auf v2.0.0 → Exit 0"
cmp -s "$C1_23/factory.lock" "$R23/v2.0.0/factory-release.json"; assert_exit 0 "$?" "#23 AK2.2a: factory.lock zeigt auf v2.0.0 (Byte-Kopie des Manifests)"
assert_true "$([ ! -e "$C1_23/scripts/old.sh" ]; echo $?)" "#23 AK2.2c: entfallene Datei (im alten Lock, nicht im neuen Manifest) gelöscht"
assert_true "$([ -f "$C1_23/scripts/new.sh" ]; echo $?)" "#23 AK2.2c: neue Datei des Manifests angelegt"
assert_contains_286 "$(cat "$C1_23/scripts/tool.sh")" 'tool v2' "#23 AK2.2a: geänderte Datei auf den Stand von v2.0.0 gebracht"
assert_true "$([ "$(cat "$C1_23/docs-fremd.txt")" = meins ] && [ "$(cat "$C1_23/docs/factory/OWNERSHIP.md")" = tabelle ]; echo $?)" \
  "#23 AK2.2c: Dateien, die weder im alten Lock noch im Manifest stehen, bleiben unberührt (z. B. OWNERSHIP.md)"
jq -e '.permissions.allow | index("Bash(b)") != null' "$C1_23/.claude/settings.json" >/dev/null 2>&1
assert_exit 0 "$?" "#23 AK2.3b: geändertes Factory-Fragment steckt nach der Abholung in settings.json"
gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 AK2.6: lokale Stufe nach der Hebung grün (keine „lokale Änderung“)"
gate_23 "$C1_23" --ci >/dev/null; assert_exit 0 "$?" "#23 AK2.6: CI-Stufe nach der Hebung grün"
git -C "$C1_23" add -A
FACTORY_DIR="$C1_23" bash "$OWN_23" >/dev/null 2>&1; assert_exit 0 "$?" "#23 AK2.6: ownership-check.sh nach der Hebung grün"

# F2: lokal geänderte Datei → Abbruch vor dem Schreiben
world_23 w6
printf 'echo lokal\n' >> "$C1_23/scripts/tool.sh"
before_23="$(snap_23 "$C1_23")"
out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 F2: lokal geänderte übernommene Datei → Abholung bricht ab"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 F2: die Meldung nennt die geänderte Datei"
assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 F2: nichts geschrieben (kein stilles Überschreiben, kein stilles Behalten)"
out_23="$(sync_23 "$C1_23" v2.0.0 --adopt)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.2e: --adopt mit factory.lock wird abgelehnt (F2 bleibt unumgehbar)"
assert_contains_286 "$out_23" 'Erstabholung' "#23 AK2.2e: die Ablehnung nennt die Erstabholung"
assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 AK2.2e: nach der Ablehnung von --adopt nichts geschrieben"

# ── AK2.2e: Erstabholung mit abweichenden Dateien ────────────────────────────────────────────────────────────────────
world_23 w7
mkdir -p "$C0_23/scripts"; printf 'echo fremd\n' > "$C0_23/scripts/tool.sh"
before_23="$(snap_23 "$C0_23")"
out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.2e: ohne Schalter bricht die Erstabholung bei abweichender Datei ab"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 AK2.2e: die Meldung nennt jede abweichende Datei"
assert_true "$([ "$before_23" = "$(snap_23 "$C0_23")" ]; echo $?)" "#23 AK2.2e: ohne Schalter nichts geändert"
out_23="$(sync_23 "$C0_23" v1.0.0 --adopt)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.2e: mit --adopt wird übernommen"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 AK2.2e: die Liste der überschriebenen Dateien nennt die Datei"
assert_contains_286 "$(cat "$C0_23/scripts/tool.sh")" 'tool v1' "#23 AK2.2e: die abweichende Datei steht auf dem Stand der Version"
assert_true "$([ -f "$C0_23/factory.lock" ]; echo $?)" "#23 AK2.2e: der Lock ist geschrieben"
world_23 w7b
mkdir -p "$C0_23/scripts"; printf '#!/usr/bin/env bash\necho tool v1\n' > "$C0_23/scripts/tool.sh"
sync_23 "$C0_23" v1.0.0 >/dev/null; assert_exit 0 "$?" "#23 AK2.2e: gleichlautende vorhandene Datei braucht keinen Schalter"

# ── AK2.2b/F4: Abbruch an jeder Stelle → nichts verändert ────────────────────────────────────────────────────────────
world_23 w8
before_23="$(snap_23 "$C1_23")"
PATH="$(stubs_23 curl):$PATH" sync_23 "$C1_23" v2.0.0 >/dev/null; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.2b: Download (curl) scheitert → Abbruch"
assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 AK2.2b: curl scheitert → nichts verändert"
PATH="$(stubs_23 git):$PATH" sync_23 "$C1_23" v2.0.0 >/dev/null; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.2b: Klon (git) scheitert → Abbruch"
assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 AK2.2b: git scheitert → nichts verändert"
before0_23="$(snap_23 "$C0_23")"
PATH="$(stubs_23 shasum sha256sum):$PATH" sync_23 "$C0_23" v1.0.0 >/dev/null; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.2b: Hash-Werkzeug scheitert (Messung gebrochen) → Abbruch, nicht still grün"
assert_true "$([ "$before0_23" = "$(snap_23 "$C0_23")" ]; echo $?)" "#23 AK2.2b: Hash-Werkzeug scheitert → nichts verändert"
# Schreibfehler mitten in Phase 2: scripts/ nicht beschreibbar, davor wurden schon andere Dateien geschrieben
chmod 555 "$C1_23/scripts"
if [ -w "$C1_23/scripts/new.sh" ] || [ -w "$C1_23/scripts" ]; then
  echo "  • #23 AK2.2b: Schreibfehler-Test übersprungen (Verzeichnis trotz chmod beschreibbar, z. B. root)"
else
  out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
  assert_exit 1 "$rc_23" "#23 AK2.2b: Schreibfehler in Phase 2 → Abbruch"
  assert_contains_286 "$out_23" 'stelle den vorherigen Stand wieder her' "#23 AK2.2b: der Rückbau läuft (Meldung)"
  assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 AK2.2b: Schreibfehler in Phase 2 → alles zurückgebaut, nichts verändert (inkl. Lock, zusammengesetzte Dateien)"
fi
chmod 755 "$C1_23/scripts"

# Ziele außerhalb der Manifest-Pfade (zusammengesetzte Dateien, Lock) dürfen kein Symlink sein: sonst schriebe die Abholung aus dem Repo hinaus
for tgt_23 in .gitignore .claude/settings.json; do
  world_23 "s_${tgt_23//[^a-z]/_}"
  cp "$C1_23/$tgt_23" "$T23/outside.txt"   # gleicher Inhalt: die lokale Stufe des Gates lässt den Symlink passieren
  orig_outside_23="$(cat "$T23/outside.txt")"
  rm "$C1_23/$tgt_23"; ln -s "$T23/outside.txt" "$C1_23/$tgt_23"
  before_23="$(snap_23 "$C1_23")"
  out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
  assert_true "$([ "$rc_23" -ne 0 ]; echo $?)" "#23 E4: $tgt_23 ist ein Symlink → Abholung bricht ab"
  assert_true "$([ "$(cat "$T23/outside.txt")" = "$orig_outside_23" ]; echo $?)" "#23 E4: $tgt_23 als Symlink → die Datei außerhalb des Repos bleibt unberührt"
  assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 E4: $tgt_23 als Symlink → nichts verändert"
done

# Entfallene Pfade des alten Locks laufen durch dieselbe Schutzprüfung wie das neue Manifest (Projektbesitz wird nie gelöscht)
world_23 r1
jq --arg h "$(shasum -a 256 < "$C1_23/README.md" | cut -c1-64)" '.files += [{"path":"README.md","sha256":$h}]' "$C1_23/factory.lock" > "$C1_23/x" && mv "$C1_23/x" "$C1_23/factory.lock"
gate_23 "$C1_23" >/dev/null; assert_exit 0 "$?" "#23 E6 (Voraussetzung): Lock mit Anpassungsstelle und passendem Hash passiert die lokale Stufe"
before_23="$(snap_23 "$C1_23")"
out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 E6: Anpassungsstelle im alten Lock → Abholung bricht ab (würde sie als entfallen löschen)"
assert_contains_286 "$out_23" 'README.md' "#23 E6: die Meldung nennt die geschützte Datei"
assert_true "$([ "$before_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "#23 E6: README.md und alles Übrige unverändert"

# ── AK2.3 / FS-T2.x / F-23.x: ungültige Manifeste → Abbruch, nichts verändert ─────────────────────────────────────────
reject_23() { # $1 = Beschreibung, $2 = erwartete Meldung, Manifest ist bereits verändert; Wurzel C0_23
  local desc="$1" needle="$2" b
  b="$(snap_23 "$C0_23")"
  out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
  assert_exit 1 "$rc_23" "#23 $desc → Abbruch"
  assert_contains_286 "$out_23" "$needle" "#23 $desc → Meldung nennt „${needle}“"
  assert_true "$([ "$b" = "$(snap_23 "$C0_23")" ]; echo $?)" "#23 $desc → nichts verändert"
}
world_23 m1; rm -rf "$R23/v1.0.0"
reject_23 "FS-T2.4: Tag ohne Release/Manifest" 'nicht eingebunden'
world_23 m2; printf 'kein json' > "$R23/v1.0.0/factory-release.json"
reject_23 "FS-T2.1: Manifest kein JSON" 'kein gültiges JSON'
world_23 m3; mut_manifest_23 v1.0.0 '.schema = 2'
reject_23 "FS-T2.1: unbekanntes schema" 'schema'
world_23 m4; mut_manifest_23 v1.0.0 'del(.schema)'
reject_23 "FS-T2.1: schema fehlt" 'schema'
world_23 m5; mut_manifest_23 v1.0.0 '(.files[] | select(.path == "scripts/tool.sh") | .sha256) = "1111111111111111111111111111111111111111111111111111111111111111"'
reject_23 "FS-T2.2: Hash weicht ab" 'scripts/tool.sh'
world_23 m6; mut_manifest_23 v1.0.0 '.version = "v9.9.9"'
reject_23 "F-23.1: Manifest-version ≠ Tag" 'version im Manifest'
world_23 m7; mut_manifest_23 v1.0.0 '.commit = "0000000000000000000000000000000000000000"'
reject_23 "F-23.1: Manifest-commit ≠ Commit des Tags" 'Commit des Manifests'
world_23 m8; mut_manifest_23 v1.0.0 '.repo = "evil/fork"'
reject_23 "F-23.1: Manifest-repo ≠ Quell-Repo" 'Quell-Repo'
world_23 m9; mut_manifest_23 v1.0.0 '.files += [{"path":"/etc/passwd","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "F-23.3: absoluter Pfad" '/etc/passwd'
world_23 m10; mut_manifest_23 v1.0.0 '.files += [{"path":"docs/../../escape","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "F-23.3: Pfad mit .." 'escape'
world_23 m11; mut_manifest_23 v1.0.0 '.files += [{"path":"README.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "AK2.3: Manifest liefert eine Anpassungsstelle (README.md)" 'README.md'
world_23 m12; mut_manifest_23 v1.0.0 '.files += [{"path":"tasks/t.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "AK2.3: Manifest liefert einen Pfad im Projektbereich (tasks/)" 'tasks/t.md'
world_23 m13; mut_manifest_23 v1.0.0 '.files += [.files[0]]'
reject_23 "F-23.3: doppelter Pfad" 'doppelt'
world_23 m14; mut_manifest_23 v1.0.0 '.files = []'
reject_23 "FS-T2.1: Manifest ohne Dateien" 'Pflichtfelder'

# Versionsangabe wird vor jedem Netzzugriff geprüft (kein Wert, der git als Option erreicht)
world_23 v1
for bad_23 in "1.0.0" "v1" "v1.0.0;x" "--upload-pack=touch /tmp/pwn" "v1.0.0 "; do
  out_23="$(FACTORY_RELEASE_BASE_URL=file:///nicht/da FACTORY_UPSTREAM_GIT_URL=file:///nicht/da FACTORY_DIR="$C0_23" bash "$SYNC_23" "$bad_23" 2>&1)"; rc_23=$?
  assert_exit 1 "$rc_23" "#23 E3: ungültige Version „${bad_23}“ → Exit 1"
  assert_absent "$out_23" 'nicht abrufbar' "#23 E3: ungültige Version „${bad_23}“ erreicht keinen Netzzugriff"
done
out_23="$(sync_23 "$C0_23" --adopt)"; assert_exit 1 "$?" "#23 E3: --adopt ohne Version → Exit 1"
out_23="$(sync_23 "$C0_23" v1.0.0 --compose)"; assert_exit 1 "$?" "#23 E3: Version zusammen mit --compose → Exit 1"

# ── fl_hash_paths: Sonderfälle der Pfade ─────────────────────────────────────────────────────────────────────────────
H23="$(mktemp -d)"; printf 'a\n' > "$H23/-dash"; printf 'b\n' > "$H23/mit leer.txt"
hash_out_23="$(printf -- '-dash\nmit leer.txt\n' | (source "$FACTORY_ROOT/scripts/lib/factory-lock.sh"; fl_hash_paths "$H23"))"; rc_23=$?
assert_exit 0 "$rc_23" "#23 E5: fl_hash_paths verarbeitet Pfade mit führendem „-“ und Leerzeichen"
assert_contains_286 "$hash_out_23" "$(printf '%s\t%s' "$(printf 'a\n' | shasum -a 256 | cut -c1-64)" '-dash')" "#23 E5: fl_hash_paths liefert Hash und Pfad getrennt durch Tab"
rm -rf "$H23"

# ── Verdrahtung: pre-commit, pre-push, CI-Job ────────────────────────────────────────────────────────────────────────
# wired_23 <datei-inhalt> – beide Anker (Zielpfad + echte Aufrufzeile) stehen im Inhalt; derselbe Ausdruck prüft Original und Mutante
wired_23() {
  printf '%s\n' "$1" | grep -qF 'INTEGRITY_CHECK="$FACTORY_DIR/scripts/checks/factory-integrity-check.sh"' \
    && printf '%s\n' "$1" | grep -qF 'bash "$INTEGRITY_CHECK"'
}
for hook_23 in pre-commit pre-push; do
  hook_src_23="$(cat "$FACTORY_ROOT/scripts/checks/$hook_23.sh")"
  wired_23 "$hook_src_23"; assert_exit 0 "$?" "#23 AK2.5a: $hook_23.sh zeigt auf das Integritäts-Gate und ruft es auf (echte Aufrufzeile)"
  wired_23 "$(printf '%s\n' "$hook_src_23" | grep -vF 'bash "$INTEGRITY_CHECK"')"
  assert_exit 1 "$?" "#23 AK2.5a (Mutation): ohne die Aufrufzeile in $hook_23.sh wird derselbe Guard rot"
done
world_23 h1
mkdir -p "$C1_23/scripts/checks" "$C1_23/scripts/lib"
cp "$FACTORY_ROOT/scripts/checks/pre-commit.sh" "$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh" "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$C1_23/scripts/checks/"
cp "$FACTORY_ROOT/scripts/lib/gate-config.sh" "$FACTORY_ROOT/scripts/lib/factory-lock.sh" "$C1_23/scripts/lib/"
cp "$FACTORY_ROOT/scripts/factory-sync.sh" "$C1_23/scripts/"
out_23="$(cd "$C1_23" && FACTORY_LINT_COMMAND=true bash scripts/checks/pre-commit.sh 2>&1)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.5a: pre-commit.sh ist mit unverändertem Lock grün"
printf 'echo x\n' >> "$C1_23/scripts/tool.sh"
out_23="$(cd "$C1_23" && FACTORY_LINT_COMMAND=true bash scripts/checks/pre-commit.sh 2>&1)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5a: pre-commit.sh blockiert bei geänderter übernommener Datei"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 AK2.5a: pre-commit.sh nennt die Datei"
assert_contains_286 "$out_23" 'Änderung gehört nach' "#23 AK2.5a: pre-commit.sh nennt den Hinweis"

# pre-push.sh: eigener Verhaltenstest (je Konsument des Gates ein Test, Lesson nothra/tch-gastro-services#431)
world_23 h2
mkdir -p "$C1_23/scripts/checks" "$C1_23/scripts/lib"
cp "$FACTORY_ROOT/scripts/checks/pre-push.sh" "$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh" "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$C1_23/scripts/checks/"
cp "$FACTORY_ROOT/scripts/lib/gate-config.sh" "$FACTORY_ROOT/scripts/lib/factory-lock.sh" "$C1_23/scripts/lib/"
cp "$FACTORY_ROOT/scripts/factory-sync.sh" "$C1_23/scripts/"
git -C "$C1_23" checkout -q -b feature/23-gate-test
push_23() { (cd "$C1_23" && env FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_TYPECHECK_COMMAND=true FACTORY_FORMAT_COMMAND=true bash scripts/checks/pre-push.sh 2>&1); }
out_23="$(push_23)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 AK2.5a: pre-push.sh ist mit unverändertem Lock grün"
printf 'echo x\n' >> "$C1_23/scripts/tool.sh"
out_23="$(push_23)"; rc_23=$?
assert_exit 1 "$rc_23" "#23 AK2.5a: pre-push.sh blockiert bei geänderter übernommener Datei"
assert_contains_286 "$out_23" 'scripts/tool.sh' "#23 AK2.5a: pre-push.sh nennt die Datei"
assert_contains_286 "$out_23" 'Änderung gehört nach' "#23 AK2.5a: pre-push.sh nennt den Hinweis"

JOB_23="$(ci_job_block factory-integrity "$FACTORY_ROOT/.github/workflows/factory-ci.yml")"
ci_wired_23() { # $1 = Job-Block: yq bereitstellen steht vor der echten run:-Zeile des Checks mit --ci
  local y r
  y="$(printf '%s\n' "$1" | grep -nF 'run: sudo bash scripts/install-yq.sh' | head -1 | cut -d: -f1)"
  r="$(printf '%s\n' "$1" | grep -nxF '        run: bash scripts/checks/factory-integrity-check.sh --ci' | head -1 | cut -d: -f1)"
  [ -n "$y" ] && [ -n "$r" ] && [ "$y" -lt "$r" ]
}
ci_wired_23 "$JOB_23"; assert_exit 0 "$?" "#23 AK2.5b: factory-ci.yml Job factory-integrity: yq bereitstellen, dann der Check mit --ci (echte run:-Zeilen)"
ci_wired_23 "$(printf '%s\n' "$JOB_23" | grep -vxF '        run: bash scripts/checks/factory-integrity-check.sh --ci')"
assert_exit 1 "$?" "#23 AK2.5b (Mutation): ohne die run:-Zeile wird derselbe Guard rot"

rm -rf "$T23"
fi
