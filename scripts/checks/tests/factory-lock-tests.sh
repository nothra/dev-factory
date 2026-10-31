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
  # v3.0.0: Versionszeile in FACTORY.md nennt weiter v2.0.0 (Tag und Datei widersprechen sich)
  printf 'echo tool v3\n' >> "$u/scripts/tool.sh"
  git -C "$u" add -A && git_23 -C "$u" commit -q -m v3 && git -C "$u" tag v3.0.0
  mk_manifest_23 "$u" v3.0.0 "$r/v3.0.0/factory-release.json"

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
  # Eine schon vorhandene Welt würde cp -R in sich hinein kopieren (alter, veränderter Stand bliebe) – fail-closed
  [ ! -e "$T23/$1" ] || { echo "world_23: Welt '$1' existiert schon – Namen eindeutig wählen (fail-closed)" >&2; exit 2; }
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
  assert_contains_286 "$out_23" 'Schreiben von' "#23 AK2.2b: die Meldung nennt den gescheiterten Schreibvorgang"
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
world_23 m11; rm "$C0_23/README.md"   # Datei fehlt im Repo: ohne Schutzprüfung käme erst der Klon-Schritt ("fehlt im Tag")
mut_manifest_23 v1.0.0 '.files += [{"path":"README.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "AK2.3: Manifest liefert eine Anpassungsstelle (README.md)" 'geschützte Stelle (Anpassungsstelle)'
assert_absent "$out_23" 'fehlt im Tag' "#23 AK2.3: der Abbruch kommt an der Schutzprüfung, nicht erst in einer späteren Stufe (Klon/Hash)"
world_23 m12; rm "$C0_23/tasks/t.md"
mut_manifest_23 v1.0.0 '.files += [{"path":"tasks/t.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "AK2.3: Manifest liefert einen Pfad im Projektbereich (tasks/)" 'geschützte Stelle (Projektbereich)'
assert_absent "$out_23" 'fehlt im Tag' "#23 AK2.3: der Abbruch kommt an der Schutzprüfung, nicht erst in einer späteren Stufe (Klon/Hash)"
world_23 m13; mut_manifest_23 v1.0.0 '.files += [.files[0]]'
reject_23 "F-23.3: doppelter Pfad" 'doppelt'
world_23 m14; mut_manifest_23 v1.0.0 '.files = []'
reject_23 "FS-T2.1: Manifest ohne Dateien" 'Pflichtfelder'

# ── /test-Ergänzungen: Fail-closed-Zweige, die Mutationsläufe als ungetestet gezeigt haben ───────────────────────────────
# Datei im Manifest, aber nicht im Tag
world_23 x1; mut_manifest_23 v1.0.0 '.files += [{"path":"scripts/ghost.sh","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]'
reject_23 "/test: Manifest nennt eine Datei, die im Tag fehlt" 'fehlt im Tag'
# Tag und Versionszeile in FACTORY.md widersprechen sich
world_23 x2; b_23="$(snap_23 "$C1_23")"
out_23="$(sync_23 "$C1_23" v3.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "/test AK2.1a: Versionszeile in FACTORY.md ≠ Tag → Abholung bricht ab"
assert_contains_286 "$out_23" 'Versionszeile' "/test AK2.1a: die Meldung nennt die Versionszeile"
assert_true "$([ "$b_23" = "$(snap_23 "$C1_23")" ]; echo $?)" "/test AK2.1a: Versionszeile ≠ Tag → nichts verändert"
# Zielverzeichnis als Symlink (nicht nur die Zieldatei)
world_23 x3; mkdir -p "$T23/outdir"; cp "$C1_23/.claude/"* "$T23/outdir/"
rm -rf "$C1_23/.claude"; ln -s "$T23/outdir" "$C1_23/.claude"
b_23="$(snap_23 "$C1_23")"; o_23="$(snap_23 "$T23/outdir")"
out_23="$(sync_23 "$C1_23" v2.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "/test E4: .claude ist ein Symlink auf ein Verzeichnis außerhalb → Abholung bricht ab"
assert_contains_286 "$out_23" 'Zielverzeichnis ist ein Symlink' "/test E4: die Meldung nennt das Symlink-Verzeichnis"
assert_true "$([ "$o_23" = "$(snap_23 "$T23/outdir")" ]; echo $?)" "/test E4: das Verzeichnis außerhalb des Repos bleibt unberührt"
# Zusammensetzen im Temp-Baum scheitert (Projekt-Fragment kein JSON), Erstabholung
world_23 x4; printf 'kein json' > "$C0_23/.claude/settings.project.json"; git -C "$C0_23" add -A
b_23="$(snap_23 "$C0_23")"
out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "/test AK2.3b: Projekt-Fragment ungültig → Abholung bricht ab"
assert_contains_286 "$out_23" 'Zusammensetzen im Temp-Baum fehlgeschlagen' "/test AK2.3b: die Meldung nennt das gescheiterte Zusammensetzen"
assert_true "$([ "$b_23" = "$(snap_23 "$C0_23")" ]; echo $?)" "/test AK2.3b: ungültiges Projekt-Fragment → nichts verändert"
rm "$C0_23/.gitignore.project"
out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "/test AK2.3b: Projekt-Fragment fehlt → Abholung bricht ab"
assert_contains_286 "$out_23" 'Projekt-Fragment fehlt' "/test AK2.3b: die Meldung nennt das fehlende Projekt-Fragment"
# upstream.repo fehlt in der Config
world_23 x5; printf 'upstream:\n  repo: ""\n' > "$C0_23/factory.defaults.yml"; printf 'upstream:\n  repo: ""\n' > "$C1_23/factory.defaults.yml"
out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
assert_exit 1 "$rc_23" "/test E2: upstream.repo leer → Abholung bricht ab"
assert_contains_286 "$out_23" 'Quell-Repo nicht ermittelbar' "/test E2: die Meldung nennt das fehlende Quell-Repo"
out_23="$(gate_23 "$C1_23" --ci)"; rc_23=$?
assert_exit 2 "$rc_23" "/test E2: CI-Stufe ohne upstream.repo → Exit 2 (fail-closed)"
assert_contains_286 "$out_23" 'upstream.repo nicht ermittelbar' "/test E2: die Meldung der CI-Stufe nennt upstream.repo"
# Hash-Werkzeug scheitert bei vorhandener abweichender Datei (Erstabholung) und im Gate
world_23 x6; mkdir -p "$C0_23/scripts"; printf 'echo fremd\n' > "$C0_23/scripts/tool.sh"
out_23="$(PATH="$(stubs_23 shasum sha256sum):$PATH" sync_23 "$C0_23" v1.0.0 --adopt)"; rc_23=$?
assert_exit 1 "$rc_23" "/test AK2.2b: Hash-Werkzeug scheitert beim Vergleich vorhandener Dateien → Abbruch"
assert_contains_286 "$out_23" 'Hashen der vorhandenen Dateien' "/test AK2.2b: die Meldung nennt das Hashen der vorhandenen Dateien"
out_23="$(PATH="$(stubs_23 shasum sha256sum):$PATH" gate_23 "$C1_23")"; rc_23=$?
assert_exit 2 "$rc_23" "/test AK2.5a: Hash-Werkzeug scheitert im Gate → Exit 2, nicht still grün"
assert_contains_286 "$out_23" 'Hashen der Dateien fehlgeschlagen' "/test AK2.5a: die Meldung nennt das gescheiterte Hashen"
# Gate ohne factory-sync.sh daneben
world_23 x7; NOSYNC_23="$T23/nosync"; mkdir -p "$NOSYNC_23/scripts/checks" "$NOSYNC_23/scripts/lib"
cp "$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh" "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$NOSYNC_23/scripts/checks/"
cp "$FACTORY_ROOT/scripts/lib/factory-lock.sh" "$FACTORY_ROOT/scripts/lib/gate-config.sh" "$NOSYNC_23/scripts/lib/"
out_23="$(env_23 "$C1_23" bash "$NOSYNC_23/scripts/checks/factory-integrity-check.sh")"; rc_23=$?
assert_exit 2 "$rc_23" "/test E8: Gate ohne scripts/factory-sync.sh → Exit 2 (fail-closed)"
assert_contains_286 "$out_23" 'factory-sync.sh fehlt' "/test E8: die Meldung nennt die fehlende factory-sync.sh"
# Meldungen der bestehenden Abbruch-Tests schärfen (Mutationslauf: ohne die Meldung blieb der Abbruch trotzdem grün)
world_23 x8
out_23="$(PATH="$(stubs_23 git):$PATH" sync_23 "$C1_23" v2.0.0)"
assert_contains_286 "$out_23" 'nicht klonbar' "/test AK2.2b: git-Stub → die Meldung nennt den gescheiterten Klon"

# Security-Review: Pfade mit führendem „-“ erreichen dirname nie als Option (Symlink-Prüfung darf nicht ins Leere laufen)
world_23 d1; mkdir -p "$U23/-d" "$T23/d1/out"
printf 'echo ok\n' > "$U23/-d/x.sh"; printf '# Development Factory · v4.0.0\n' > "$U23/docs/factory/FACTORY.md"
git -C "$U23" add -A && git_23 -C "$U23" commit -q -m dash && git -C "$U23" tag v4.0.0
mk_manifest_23 "$U23" v4.0.0 "$R23/v4.0.0/factory-release.json"
ln -s "$T23/d1/out" "$C1_23/-d"
b_23="$(snap_23 "$C1_23")"
out_23="$(sync_23 "$C1_23" v4.0.0)"; rc_23=$?
assert_true "$([ "$rc_23" -ne 0 ]; echo $?)" "#23 Security: Manifest-Pfad -d/x.sh mit Symlink -d nach außerhalb → Abholung bricht ab"
assert_true "$([ -z "$(ls -A "$T23/d1/out")" ]; echo $?)" "#23 Security: nichts außerhalb des Repos geschrieben"
assert_contains_286 "$out_23" 'Zielverzeichnis ist ein Symlink' "#23 Security: die Meldung nennt das Symlink-Verzeichnis (Prüfung greift, läuft nicht ins Leere)"
assert_absent "$out_23" 'illegal option' "#23 Security: dirname bekommt den Pfad nie als Option"
world_23 d2; mkdir -p "$U23/-d"; printf 'echo ok\n' > "$U23/-d/x.sh"; printf '# Development Factory · v4.0.0\n' > "$U23/docs/factory/FACTORY.md"
git -C "$U23" add -A && git_23 -C "$U23" commit -q -m dash && git -C "$U23" tag v4.0.0
mk_manifest_23 "$U23" v4.0.0 "$R23/v4.0.0/factory-release.json"
out_23="$(sync_23 "$C1_23" v4.0.0)"; rc_23=$?
assert_exit 0 "$rc_23" "#23 Security: ein legitimer Pfad -d/x.sh ohne Symlink wird übernommen"
assert_true "$([ -f "$C1_23/-d/x.sh" ]; echo $?)" "#23 Security: -d/x.sh liegt im Repo"
# upstream.repo: Segmente „.“ und „..“ sind kein Repo-Slug
world_23 d3
for slug_23 in '../evil' 'owner/..' './x'; do
  printf 'upstream:\n  repo: "%s"\n' "$slug_23" > "$C0_23/factory.defaults.yml"
  out_23="$(sync_23 "$C0_23" v1.0.0)"; rc_23=$?
  assert_exit 1 "$rc_23" "#23 Security: upstream.repo „${slug_23}“ → Abholung bricht ab"
  assert_contains_286 "$out_23" 'Quell-Repo nicht ermittelbar' "#23 Security: upstream.repo „${slug_23}“ → Meldung nennt das Quell-Repo"
done

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

# ═══ Factory-Issue #24: Update-Workflow und Update-PR (factory-update.sh) ════════════════════════════════════════════
# Gleiche Welt wie #23 (world_23), dazu ein Bare-Repo als `origin` des Konsumenten und ein gh-Stub im PATH, der
# Repo-Rechte, Release-Liste und PR-Zustand aus Dateien liefert und jeden Aufruf protokolliert (Factory-ADR-063 E16).
echo ""
echo "Factory-Issue #24: Update-Workflow und Update-PR:"

UPD_24="$FACTORY_ROOT/scripts/factory-update.sh"
BR_24="chore/factory-update"
GOOD_TOKEN_24="pat-gueltig-24"

# gh-Stub: Zustand unter $GH_STUB_STATE (push, releases.json, prs.json, calls.log); jeder Aufruf mit falschem GH_TOKEN → 401
GH_STUB_24="$T23/ghstub"; mkdir -p "$GH_STUB_24"
cat > "$GH_STUB_24/gh" <<'STUB'
#!/usr/bin/env bash
s="$GH_STUB_STATE"
printf '%s | GH_TOKEN=%s | GITHUB_TOKEN=%s\n' "$*" "${GH_TOKEN:-}" "${GITHUB_TOKEN:+gesetzt}" >> "$s/calls.log"
[ "${GH_TOKEN:-}" = "$GH_STUB_TOKEN" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }
arg() { local k="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$k" ] && { printf '%s' "$2"; return; }; shift; done; }
case "$1 $2" in
  "api repos/"*)       cat "$s/push" ;;
  "api --paginate")    [ ! -e "$s/releases-fail" ] || exit 1; cat "$s/releases.json" ;;
  "pr list")
    st="$(arg --state "$@")"
    [ ! -e "$s/pr-list-fail-$st" ] || exit 1
    jq --arg st "$st" --arg h "$(arg --head "$@")" \
      '[.[] | select(.headRefName == $h) | select(if $st == "open" then .state == "OPEN" else .state != "OPEN" end)]' "$s/prs.json" ;;
  "pr create")
    [ ! -e "$s/pr-create-fail" ] || exit 1
    n=$(( $(jq length "$s/prs.json") + 1 ))
    jq --argjson n "$n" --arg t "$(arg --title "$@")" --rawfile b "$(arg --body-file "$@")" --arg h "$(arg --head "$@")" --arg l "$(arg --label "$@")" \
      '. + [{number: $n, url: "https://example.invalid/pull/\($n)", state: "OPEN", title: $t, body: $b, headRefName: $h,
             isCrossRepository: false, mergedAt: null, labels: [$l]}]' "$s/prs.json" > "$s/x" && mv "$s/x" "$s/prs.json"
    echo "https://example.invalid/pull/$n" ;;
  "pr edit")
    [ ! -e "$s/pr-edit-fail" ] || exit 1
    jq --argjson n "$3" --arg t "$(arg --title "$@")" --rawfile b "$(arg --body-file "$@")" \
      'map(if .number == $n then .title = $t | .body = $b else . end)' "$s/prs.json" > "$s/x" && mv "$s/x" "$s/prs.json" ;;
  *) exit 0 ;;   # z. B. „pr merge“: tut nichts, steht aber im Protokoll
esac
STUB
chmod +x "$GH_STUB_24/gh"

# add_release_24 <tag> – neuer Tag im Upstream der aktuellen Welt (gültige Versionszeile) samt Manifest
add_release_24() {
  printf '# Development Factory · %s\n' "$1" > "$U23/docs/factory/FACTORY.md"
  printf 'echo %s\n' "$1" >> "$U23/scripts/tool.sh"
  git -C "$U23" add -A && git_23 -C "$U23" commit -q -m "$1" && git -C "$U23" tag "$1"
  mk_manifest_23 "$U23" "$1" "$R23/$1/factory-release.json"
}
# releases_24 <tag…> – Release-Liste des Stubs: je Tag ein veröffentlichtes Release mit Manifest-Asset und Notes „Notes <tag>“
releases_24() {
  printf '%s\n' "$@" | jq -R . | jq -s 'map({tag_name: ., draft: false, prerelease: false, body: "Notes \(.)",
                                            assets: [{name: "factory-release.json"}]})' > "$GS_24/releases.json"
}
# world_24 <name> – world_23 + Bare-Origin für C1 + frischer Stub-Zustand (Push-Recht, keine PRs, nur v1.0.0 veröffentlicht)
# Eigener Namensraum w24-<name>: die Welten aus #23 tragen dieselben Kurznamen (d1, x3 …)
world_24() {
  W24="$T23/w24-$1"
  world_23 "w24-$1"
  ORIGIN_24="$W24/origin.git"; GS_24="$W24/gh"; mkdir -p "$GS_24"
  git clone -q --bare "$C1_23" "$ORIGIN_24"
  git -C "$C1_23" remote add origin "file://$ORIGIN_24" && git -C "$C1_23" fetch -q origin
  printf 'true\n' > "$GS_24/push"; printf '[]\n' > "$GS_24/prs.json"; : > "$GS_24/calls.log"
  releases_24 v1.0.0
}
# upd_24 [<skript>] – factory-update.sh gegen C1 der aktuellen Welt; Token gültig, GITHUB_TOKEN gesetzt (darf nie ankommen)
upd_24() {
  env_23 "$C1_23" env PATH="$GH_STUB_24:$PATH" GH_STUB_STATE="$GS_24" GH_STUB_TOKEN="$GOOD_TOKEN_24" \
    GITHUB_REPOSITORY="${REPO_24-acme/consumer}" GITHUB_TOKEN=actions-token-24 FACTORY_SYNC_TOKEN="${TOKEN_24-$GOOD_TOKEN_24}" \
    bash "${1:-$UPD_24}"
}
sha_24() { git -C "$ORIGIN_24" rev-parse -q --verify "refs/heads/$1"; }
open_prs_24() { jq '[.[] | select(.state == "OPEN")] | length' "$GS_24/prs.json"; }
pr_body_24() { jq -r '.[0].body' "$GS_24/prs.json"; }
# writes_24 – schreibende Aufrufe im Stub-Protokoll (leer = keine)
writes_24() { grep -E '^pr (create|edit|merge|comment|close)|^api .*(-X|--method)' "$GS_24/calls.log"; }
lock_on_branch_24() { git -C "$ORIGIN_24" show "refs/heads/$BR_24:factory.lock" | jq -r .version; }
# factory_scripts_24 <wurzel> <update-skript> – factory-update.sh (die übergebene Fassung) samt allem, was es zur Laufzeit lädt
factory_scripts_24() {
  mkdir -p "$1/scripts/checks" "$1/scripts/lib"
  cp "$FACTORY_ROOT/scripts/factory-sync.sh" "$1/scripts/"
  cp "$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh" "$FACTORY_ROOT/scripts/checks/customization-points.txt" "$1/scripts/checks/"
  cp "$FACTORY_ROOT/scripts/lib/factory-lock.sh" "$FACTORY_ROOT/scripts/lib/gate-config.sh" "$1/scripts/lib/"
  cp "$2" "$1/scripts/factory-update.sh"
}
# Welt-Namen aus einem Zähler (für Schleifen: eindeutig unabhängig vom Testwert)
N_24=0
next_world_24() { N_24=$((N_24 + 1)); world_24 "$1$N_24"; }

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

# ── FS-T2.3: Token fehlt / abgelehnt → rot vor jedem weiteren Schritt, auch ohne neue Version ────────────────────────
# token_refused_24 <exit> <ausgabe> <protokoll-datei> – rot, Meldung nennt Token + OPERATING.md, Release-Liste nie gelesen
token_refused_24() {
  [ "$1" -eq 1 ] && grep -qF 'FACTORY_SYNC_TOKEN' <<< "$2" && grep -qF 'OPERATING.md' <<< "$2" && ! grep -qF 'releases' "$3"
}
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
# Mutationsbeleg: ohne den Checkout auf ORIG_REF verletzt derselbe Fall den Guard
RESTORE_LINE_24='git checkout --quiet "$ORIG_REF"'
grep -vF "$RESTORE_LINE_24" "$UPD_24" > "$T23/mut24-restore.sh"
assert_true "$([ "$(grep -cF "$RESTORE_LINE_24" "$UPD_24")" = 1 ] && ! grep -qF "$RESTORE_LINE_24" "$T23/mut24-restore.sh"; echo $?)" \
  "#24 Rückkehr (Mutation): genau die Checkout-Zeile auf ORIG_REF ist im Mutanten entfernt"
factory_scripts_24 "$T23/mut24r" "$T23/mut24-restore.sh"
world_24 o3; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0
upd_24 "$T23/mut24r/scripts/factory-update.sh" >/dev/null; back_on_main_24; assert_exit 1 "$?" "#24 Rückkehr (Mutation): ohne die Zeile ist derselbe Guard rot – die Rückkehr ist wirksam"

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
  out_24="$(upd_24 "$C1_23/scripts/factory-update.sh")"; rc_24=$?
}
# Guard: Lauf grün, und keine Zeile der neuen Fassung wurde ausgeführt
self_replace_safe_24() { [ "$1" -eq 0 ] && ! grep -qF 'AUS-NEUER-VERSION-24' <<< "$2"; }
self_replace_24 sr1 "$UPD_24"
assert_true "$(cmp -s "$C1_23/scripts/factory-update.sh" "$UPD_24"; echo $?)" "#24 Selbst-Ersatz (Voraussetzung): C1 führt die übernommene factory-update.sh aus"
self_replace_safe_24 "$rc_24" "$out_24"; assert_exit 0 "$?" "#24 Selbst-Ersatz: nach main liest bash nichts mehr aus der ersetzten Datei (grün, nichts aus v1.2.0 ausgeführt)"
assert_true "$([ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" "#24 Selbst-Ersatz: der Update-PR steht auf v1.2.0 (inkl. neuer factory-update.sh)"
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
assert_true "$(grep -E '(git|git_with_token) .*push ' <<< "$upd_src_24" | grep -qF '"HEAD:refs/heads/$UPDATE_BRANCH"'; echo $?)" "#24 F1: einziges Push-Ziel ist refs/heads/\$UPDATE_BRANCH"
assert_true "$(grep -qxF 'UPDATE_BRANCH="chore/factory-update"' <<< "$upd_src_24"; echo $?)" "#24 F1: UPDATE_BRANCH ist fest chore/factory-update"
assert_absent "$upd_src_24" 'pr merge' "#24 AK2.4: das Skript ruft nie gh pr merge"
assert_absent "$upd_src_24" '--auto' "#24 AK2.4: das Skript aktiviert kein Auto-Merge"
assert_absent "$upd_src_24" '$GITHUB_TOKEN' "#24 AK2.4: das Skript liest GITHUB_TOKEN nie"
assert_absent "$upd_src_24" '${GITHUB_TOKEN' "#24 AK2.4: das Skript liest GITHUB_TOKEN nie (Klammerform)"

WF_24="$FACTORY_ROOT/.github/workflows/factory-update.yml"
wf_24="$(cat "$WF_24" 2>/dev/null)"
assert_true "$(grep -qE '^  schedule:' <<< "$wf_24" && grep -qE "^    - cron: '[^']+'" <<< "$wf_24"; echo $?)" "#24 AK2.2d: factory-update.yml läuft per schedule"
assert_true "$(grep -qE '^  workflow_dispatch:' <<< "$wf_24"; echo $?)" "#24 AK2.2d: factory-update.yml läuft per workflow_dispatch"
assert_true "$(grep -qxF '  group: factory-update' <<< "$wf_24" && grep -qxF '  cancel-in-progress: false' <<< "$wf_24"; echo $?)" "#24 E10: concurrency factory-update, ohne Cancel"
assert_true "$(grep -qxF 'permissions:' <<< "$wf_24" && grep -qxF '  contents: read' <<< "$wf_24"; echo $?)" "#24 E10: GITHUB_TOKEN nur contents: read"
assert_true "$(grep -qxF '          fetch-depth: 0' <<< "$wf_24" && grep -qxF '          persist-credentials: false' <<< "$wf_24"; echo $?)" "#24 E10: Checkout mit fetch-depth 0 und ohne gespeicherte Anmeldung"
# Reihenfolge: yq bereitstellen vor der echten run:-Zeile, Token aus dem Secret als Env
wf_wired_24() {
  local y r
  y="$(grep -nF 'run: sudo bash scripts/install-yq.sh' <<< "$1" | head -1 | cut -d: -f1)"
  r="$(grep -nxF '        run: bash scripts/factory-update.sh' <<< "$1" | head -1 | cut -d: -f1)"
  [ -n "$y" ] && [ -n "$r" ] && [ "$y" -lt "$r" ] && grep -qxF '          FACTORY_SYNC_TOKEN: ${{ secrets.FACTORY_SYNC_TOKEN }}' <<< "$1"
}
wf_wired_24 "$wf_24"; assert_exit 0 "$?" "#24 AK2.4: yq, dann factory-update.sh mit FACTORY_SYNC_TOKEN aus dem Secret (echte Zeilen)"
wf_wired_24 "$(grep -vF 'FACTORY_SYNC_TOKEN: ${{ secrets.FACTORY_SYNC_TOKEN }}' <<< "$wf_24")"
assert_exit 1 "$?" "#24 AK2.4 (Mutation): ohne die Token-Zeile wird derselbe Guard rot"
assert_absent "$wf_24" 'GITHUB_TOKEN' "#24 AK2.4: factory-update.yml reicht GITHUB_TOKEN nicht weiter"
assert_absent "$wf_24" 'pr merge' "#24 AK2.4: factory-update.yml merged nie"

rm -rf "$T23"
fi
