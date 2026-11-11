#!/usr/bin/env bash
# factory-lock-fixtures.sh – gemeinsame Fixtures der Testgruppen zu Abholen, factory.lock und Integritäts-Gate (Factory-Issue #23),
# Update-Workflow (#24) und Token-Trennung (#37); Schnitt in Teilgruppen: Factory-ADR-066 D2
#
# Wird gesourct, nie direkt ausgeführt – von scripts/checks/tests/factory-lock-{23,24a,24b,37a,37b}-tests.sh. Alles läuft offline
# gegen ein Fixture-Factory-Repo (lokales Git-Repo mit Tags) und handgebaute Release-Manifeste; Netzzugriffe sind über
# FACTORY_UPSTREAM_GIT_URL/FACTORY_RELEASE_BASE_URL (`file://`) umgelenkt. Konsumenten-neutral: liest nur Dateien der Seite
# `factory` und baut alles Übrige selbst. Setzt die Helfer aus lib/assert-helpers.sh und lib/test-groups.sh voraus.
#
# Jede Testgruppe ruft factory_lock_setup: eigenes Temp-Verzeichnis T23 (Aufräumen per EXIT-Trap), eigene Vorlage, kein
# geteilter Zustand mit anderen Gruppen. Gruppen mit #24-/#37-Tests rufen danach factory_lock_setup_24 (gh-Stub).

FACTORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SYNC_23="$FACTORY_ROOT/scripts/factory-sync.sh"
GATE_23="$FACTORY_ROOT/scripts/checks/factory-integrity-check.sh"
OWN_23="$FACTORY_ROOT/scripts/checks/ownership-check.sh"
UPD_24="$FACTORY_ROOT/scripts/factory-update.sh"
WF_24="$FACTORY_ROOT/.github/workflows/factory-update.yml"
BR_24="chore/factory-update"
GOOD_TOKEN_24="pat-gueltig-24"

# Umgebung wie an der früheren source-Stelle in run-tests.sh: dort waren die Gate-Kommandos der Pipeline-Tests schon
# wieder entfernt, und die Markierung gegen verschachtelte Hook-Läufe war gesetzt – auch beim Einzelstart einer Gruppe.
unset FACTORY_LINT_COMMAND FACTORY_TEST_COMMAND FACTORY_COVERAGE_COMMAND
export FACTORY_SELF_TEST_RUN=1

# ═══ #23: Vorlage und Welten ══════════════════════════════════════════════════════════════════════════════════════════
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

# strip_literal_37 <text> <literal> – <text> ohne jedes Vorkommen von <literal>; gleiches Ergebnis wie "${text//"$literal"/}",
# aber linear: bash 3.2 rechnet die Mustersubstitution auf großen Texten quadratisch (8 s je Mutante der ADR-063, Factory-ADR-066
# D7). Text und Literal kommen per stdin bzw. ENVIRON (keine Escape-Verarbeitung wie bei -v); der Punkt am Ende schützt
# abschließende Zeilenumbrüche vor der Kommandosubstitution.
strip_literal_37() {
  local out
  out="$(printf '%s.' "$1" | LIT_37="$2" LC_ALL=C awk '
    { s = (NR == 1) ? $0 : s "\n" $0 }
    END {
      s = substr(s, 1, length(s) - 1); lit = ENVIRON["LIT_37"]; n = length(lit); r = ""
      if (n > 0) while ((i = index(s, lit)) > 0) { r = r substr(s, 1, i - 1); s = substr(s, i + n) }
      printf "%s.", r s
    }')"
  printf '%s' "${out%.}"
}

# factory_lock_setup – Temp-Verzeichnis (EXIT-Trap) und Vorlage dieser Testgruppe; setzt T23 und TMPL_SNAP_23 (Fingerprint
# der Vorlage für factory_lock_template_unchanged). Scheitert der Aufbau, endet die Gruppe fail-closed (Spec #52 F1).
factory_lock_setup() {
  T23="$(mktemp -d)" || { echo "factory_lock_setup: kein Temp-Verzeichnis (fail-closed)" >&2; exit 2; }
  test_group_trap "$T23"
  build_template_23 "$T23/tmpl" || { echo "factory_lock_setup: Aufbau der Vorlage gescheitert (fail-closed)" >&2; exit 2; }
  TMPL_SNAP_23="$(snap_23 "$T23/tmpl")"
}

# factory_lock_template_unchanged – Assertion: kein Fall dieser Gruppe hat die geteilte Vorlage verändert (Spec #52 AK8/F2)
factory_lock_template_unchanged() {
  assert_true "$([ "$TMPL_SNAP_23" = "$(snap_23 "$T23/tmpl")" ]; echo $?)" \
    "#52 AK8: Vorlage der Testgruppe $(basename "$0" .sh) nach allen Fällen unverändert (Fingerprint über Dateien und .git)"
}

# ═══ #24: gh-Stub, Bare-Origin, Läufe von factory-update.sh ═══════════════════════════════════════════════════════════
# Gleiche Welt wie #23 (world_23), dazu ein Bare-Repo als `origin` des Konsumenten und ein gh-Stub im PATH, der
# Repo-Rechte, Release-Liste und PR-Zustand aus Dateien liefert und jeden Aufruf protokolliert (Factory-ADR-063 E16).
# In GitHub Actions sind GITHUB_ACTIONS=true und GITHUB_OUTPUT gesetzt: die Kurzform von factory-update.sh verweigert dort den
# Lauf (#37), und die Modi guard/preflight würden in die Ausgabedatei des echten Jobs schreiben. Tests, die das brauchen, setzen
# die Variablen je Aufruf selbst (`GITHUB_ACTIONS=true upd_24`, `GITHUB_OUTPUT=…`).
factory_lock_setup_24() {
  unset GITHUB_ACTIONS GITHUB_OUTPUT
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
}

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
# token_refused_24 <exit> <ausgabe> <protokoll-datei> – rot, Meldung nennt Token + OPERATING.md, Release-Liste nie gelesen
token_refused_24() {
  [ "$1" -eq 1 ] && grep -qF 'FACTORY_SYNC_TOKEN' <<< "$2" && grep -qF 'OPERATING.md' <<< "$2" && ! grep -qF 'releases' "$3"
}

# ═══ #37: Mutanten, Modus publish, Übergabe-Bundles ═══════════════════════════════════════════════════════════════════
# ── Hilfen für die Verhaltenstests ───────────────────────────────────────────────────────────────────────────────────
# mutant_37 <name> <sed-ausdruck> – Mutante von factory-update.sh samt Umgebung; setzt MUT37 (Pfad); fail-closed, wenn der Ausdruck nichts ändert
mutant_37() {
  sed -E "$2" "$UPD_24" > "$T23/m37-$1.sh"
  [ "$(diff "$UPD_24" "$T23/m37-$1.sh" | grep -c '^<')" -ge 1 ] || { echo "mutant_37: '$1' ändert nichts – Ausdruck anpassen (fail-closed)" >&2; exit 2; }
  factory_scripts_24 "$T23/m37-$1" "$T23/m37-$1.sh"; MUT37="$T23/m37-$1/scripts/factory-update.sh"
}
# refused_ok_37 <meldung> – rot (Exit 1), Meldung enthalten, kein Push, kein schreibender gh-Aufruf
refused_ok_37() { [ "$rc_24" -eq 1 ] && grep -qF -- "$1" <<< "$out_24" && [ -z "$(sha_24 "$BR_24")" ] && [ -z "$(writes_24)" ]; }
pub_37() { # [<update-skript>] [<bundle>] – Modus publish gegen C1; setzt out_24/rc_24
  out_24="$(env_23 "$C1_23" env PATH="$GH_STUB_24:$PATH" GH_STUB_STATE="$GS_24" GH_STUB_TOKEN="$GOOD_TOKEN_24" GITHUB_REPOSITORY=acme/consumer \
    FACTORY_SYNC_TOKEN="$GOOD_TOKEN_24" bash "${1:-$UPD_24}" publish "${VER_37-v1.1.0}" "$BASE_37" "${2:-$BUNDLE_37}")"; rc_24=$?
}
# bundle_37 <welt> [<snippet>] – legitimes Bundle (Modus fetch im frischen Klon, ohne Token), danach <snippet> im Klon und neu gebündelt
bundle_37() {
  world_24 "$1"; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; VER_37=v1.1.0
  BASE_37="$(git -C "$ORIGIN_24" rev-parse main)"; CL_37="$W24/clone37"; BUNDLE_37="$W24/u.bundle"
  git clone -q "$C1_23" "$CL_37"
  env_23 "$CL_37" env -u FACTORY_SYNC_TOKEN bash "$UPD_24" fetch v1.1.0 "$BASE_37" "$BUNDLE_37" >/dev/null
  if [ -n "${2:-}" ]; then
    ( cd "$CL_37" && eval "$2" ) >/dev/null 2>&1 || { echo "bundle_37: Snippet fehlgeschlagen: $2" >&2; exit 2; }
    rm -f "$BUNDLE_37"; git -C "$CL_37" bundle create -q "$BUNDLE_37" "$BASE_37..HEAD"
  fi
}
