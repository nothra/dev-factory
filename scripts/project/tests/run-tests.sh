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
source "$CHECKS_DIR/tests/lib/assert-helpers.sh" || {
  echo "run-tests: geteilte Helfer-Lib nicht ladbar: $CHECKS_DIR/tests/lib/assert-helpers.sh (fail-closed, Factory-Issue #22 F-22.5)" >&2
  exit 2
}

SCRIPTS_DIR="$(cd "$CHECKS_DIR/.." && pwd)"
IMPORT_CHECK="$CHECKS_DIR/import-context-limit-check.sh"
IC_LIMIT_319="$(sed -n 's/^MAX_IMPORT_LINES=\([0-9]*\).*/\1/p' "$IMPORT_CHECK" | head -1)"
OWN_CHECK_426="$CHECKS_DIR/ownership-check.sh"
FACTORY_MD_431="$FACTORY_ROOT/docs/factory/FACTORY.md"
CLAUDE_MD_431="$FACTORY_ROOT/CLAUDE.md"
FCI_431="$FACTORY_ROOT/.github/workflows/factory-ci.yml"
PCI_431="$FACTORY_ROOT/.github/workflows/ci.yml"
own_side_426() { local l; l="$(OWNERSHIP_FILE="$FACTORY_ROOT/docs/factory/OWNERSHIP.md" FACTORY_LOCK_FILE="$NO_LOCK_FILE" bash "$OWN_CHECK_426" --list "$1" 2>/dev/null)"; grep -qxF -- "$2" <<< "$l"; }
jobs_of_431() { awk '/^jobs:/{j=1;next} j && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{sub(/^  /,"");sub(/:.*/,"");print}' "$1" | sort | tr '\n' ' '; }
# Nummern der Factory-ADRs: die Verzeichnisliste selbst (die ausgelieferte Suite belegt sie in AK-B1 gegen eine feste Liste)
FACTORY_ADR_NUMS_426="$(for f in "$FACTORY_ROOT"/docs/factory/adr/[0-9][0-9][0-9]-*.md; do [ -e "$f" ] && basename "$f" | cut -c1-3; done | sort -u | tr '\n' ' ' | sed 's/ $//')"

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
  FACTORY_LOCK_FILE="$NO_LOCK_FILE" OWNERSHIP_FILE="$table" OWNERSHIP_FILE_LIST="$work/entries.txt" \
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
assert_true "$(! grep -qE '^(tasks|docs/specs)/' "$POINTS_22"; echo $?)" \
  "#22 AK2.15b-2 (Kontrolle): tasks/** und docs/specs/** stehen nicht in der Liste (Teilmenge, nicht Gesamtheit)"

# Richtung 1 gebrochen: Eintrag in der Tabelle auf `factory` gesetzt → Guard nennt genau diesen Pfad
dir_22="$(mktemp -d)"
sed 's#^| project | `README.md` |#| factory | `README.md` |#' "$TABLE_22" > "$dir_22/OWNERSHIP.md"
assert_true "$(! cmp -s "$TABLE_22" "$dir_22/OWNERSHIP.md"; echo $?)" "#22 AK2.15b-2 (Kontrolle): die Mutation der Tabelle hat gewirkt"
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
own_side_426 project docs/factory/OWNERSHIP.md
assert_exit 0 $? "#22 AK2.15d-0: docs/factory/OWNERSHIP.md steht auf Seite project"
own_side_426 factory docs/factory/OWNERSHIP.md
assert_exit 1 $? "#22 AK2.15d-0: docs/factory/OWNERSHIP.md steht nicht auf Seite factory (nicht im Release-Manifest)"
# Security-Review (Task 22): Im Factory-Repo gilt die Tabelle. Ein committetes `factory.lock` würde ownership-check.sh dort still in den
# Lock-Modus schalten und die Vollständigkeitsprüfung der Tabelle abschalten – darum darf es im Factory-Repo keins geben.
# (Gehört in die Projekt-Suite: ein Konsument HAT einen Lock; die ausgelieferte Suite bleibt neutral.)
repo_without_lock_22() { [ ! -e "$1/factory.lock" ] && [ ! -L "$1/factory.lock" ]; }
repo_without_lock_22 "$FACTORY_ROOT"
assert_exit 0 $? "#22 Security: das Factory-Repo trägt kein factory.lock (sonst wäre die Tabellenprüfung abgeschaltet)"
dir_22="$(mktemp -d)"; : > "$dir_22/factory.lock"
repo_without_lock_22 "$dir_22"
assert_exit 1 $? "#22 Security (Kontrolle): ein factory.lock im Verzeichnis wird vom Guard erkannt"
rm -rf "$dir_22"

# AK2.16b-3: der Projekt-Test-Ordner trägt keine factory-Zeile
own_side_426 factory scripts/project/tests/run-tests.sh
assert_exit 1 $? "#22 AK2.16b-3: scripts/project/tests/run-tests.sh steht nicht auf Seite factory"
own_side_426 project scripts/project/tests/run-tests.sh
assert_exit 0 $? "#22 AK2.16b-3: scripts/project/tests/run-tests.sh steht auf Seite project"

# ─── Aus der ausgelieferten Suite verschoben (Factory-ADR-064 D6): Prüfungen, die dieses Repo voraussetzen ───
# ── verschoben aus der ausgelieferten Suite: CI-Lint-Job führt commands.lint aus (ci.yml + factory.config.yml dieses Repos) ──
# CI-Lint des Factory-Repos: der Job `lint` in ci.yml führt exakt commands.lint aus factory.config.yml aus
# (eine Quelle – ändert eine Seite ihren Wortlaut allein, schlägt dieser Guard an).
if [ "$HAS_YQ" = 1 ]; then
  ci_lint_cmd="$(yq '.commands.lint' "$FACTORY_ROOT/factory.config.yml")"
  { [ -n "$ci_lint_cmd" ] && grep -qF -- "run: $ci_lint_cmd" "$PCI_431"; }
  assert_true "$?" "CI-Lint-Job führt commands.lint aus factory.config.yml aus (eine Quelle)"
else
  skip_yq "CI-Lint-Job führt commands.lint aus factory.config.yml aus"
fi

# ── verschoben aus der ausgelieferten Suite: Phase 1b: realer Override dieses Repos löst implement auf den Default auf (#348) ──
if [ "$HAS_YQ" = 1 ]; then
  DEFAULTS="$FACTORY_ROOT/factory.defaults.yml"; PIPELINE="$FACTORY_ROOT/scripts/run-pipeline.sh"
  TMP_CFG="$(mktemp -d)"; mkdir -p "$TMP_CFG/scripts/checks" "$TMP_CFG/scripts/lib" "$TMP_CFG/tasks" "$TMP_CFG/docs/factory"
  cp "$PIPELINE" "$TMP_CFG/scripts/"; cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_CFG/scripts/checks/"; cp "$DEFAULTS" "$TMP_CFG/"
  cp_pipeline_libs "$TMP_CFG"
  echo "# ctx" > "$TMP_CFG/docs/factory/PROJECT-CONTEXT.md"; echo "# Task 1: x" > "$TMP_CFG/tasks/task-1-x.md"
  # 18 AK (Größe Task 47) → oberste Turn-Stufe der Defaults (#49, Factory-ADR-065).
  mk_spec_fixture "$TMP_CFG" 1 18
  git -C "$TMP_CFG" init -q; git -C "$TMP_CFG" add .
  git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  # Der REALE Team-Override des Factory-Repos setzt keine skills.*-Knöpfe: die effektive Config löst
  # /implement end-to-end auf den Default aus factory.defaults.yml auf (kein stiller Fallback, kein
  # fremder Wert aus einem adoptierenden Projekt).
  cp "$FACTORY_ROOT/factory.config.yml" "$TMP_CFG/factory.config.yml"
  git -C "$TMP_CFG" add .; git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m real-override
  real_out=$(bash "$TMP_CFG/scripts/run-pipeline.sh" 1 --dry-run 2>&1 || true)
  def_turns_348="$(yq '.skills.implement.max_turns_by_size.high.max_turns' "$DEFAULTS")"
  printf '%s' "$real_out" | grep -qE "Starte: /implement 1 \(model: [^,]+, max ${def_turns_348} turns\)"
  assert_true "$?" "#348/#49 AK19: realer Repo-Override löst implement (18 AK) end-to-end auf die Default-Staffelung (max ${def_turns_348} turns) auf"
  assert_true "$([ "$(yq 'has("skills")' "$FACTORY_ROOT/factory.config.yml")" = "false" ]; echo $?)" \
    "#348/#49 AK19: factory.config.yml dieses Repos setzt keine skills.*-Werte (Dogfooding-Garantie)"
  rm -rf "$TMP_CFG"
else
  skip_yq "#348 realer Repo-Override"
fi

# ── verschoben aus der ausgelieferten Suite: #197 AK12: factory.config.yml dieses Repos führt kein statisches implement.tier ──
if [ "$HAS_YQ" = 1 ]; then
  # AK12: der provisorische implement-Tier-Override ist aufgelöst (kein .skills.implement.tier mehr).
  if [ -f "$FACTORY_ROOT/factory.config.yml" ]; then
    [ "$(yq '.skills.implement | has("tier")' "$FACTORY_ROOT/factory.config.yml")" = "false" ]
    assert_true "$?" "#197 AK12: factory.config.yml führt kein statisches implement.tier mehr (Override aufgelöst)"
  fi
else
  skip_yq "#197 AK12"
fi

# ── verschoben aus der ausgelieferten Suite: #264: Index-Zeilen, seit #44 in lessons/INDEX.md ──
PC264="$FACTORY_ROOT/docs/factory/lessons/INDEX.md"
assert_true "$(! grep -qF 'Härtung ausgelagert: nothra/tch-gastro-services#264' "$PC264"; echo $?)" \
  "#264: Index-Zeile in lessons/INDEX.md nennt die Härtung nicht mehr als ausgelagert"
grep -qF 'Härtung umgesetzt in nothra/tch-gastro-services#264' "$PC264"
assert_true "$?" "#264: Index-Zeile in lessons/INDEX.md nennt den Erledigt-Stand"

# ── verschoben aus der ausgelieferten Suite: #262: CONTRIBUTING.md nennt die Hook-Installation (Einstieg für Menschen in diesem Repo) ──
# Die Schleife der ausgelieferten Suite prüft FACTORY.md, git-workflow.md und OPERATING.md; CONTRIBUTING.md gehört dem Projekt.
CONTRIBUTING_MD="$FACTORY_ROOT/CONTRIBUTING.md"
doc_file="$CONTRIBUTING_MD"
[ -r "$doc_file" ]
assert_true "$?" "#262: $(basename "$doc_file") ist lesbar (Vorbedingung der Doku-Checks)"
grep -qF 'scripts/install-hooks.sh' "$doc_file"
assert_true "$?" "#262: $(basename "$doc_file") nennt scripts/install-hooks.sh als Installationsweg"
grep -qF '`commit-msg`-Hook' "$doc_file"
assert_true "$?" "#262: $(basename "$doc_file") nennt den commit-msg-Hook als Hook"

# ── verschoben aus der ausgelieferten Suite: #262: README.md nennt die Hook-Installation (Setup-Anleitung dieses Repos) ──
# Setup-Anleitung für einen frischen Clone: die Hook-Installation gehört in den Ablauf, sonst
# folgt ihr jemand vollständig und hat danach keinen einzigen lokalen Hook.
README_MD="$FACTORY_ROOT/README.md"
[ -r "$README_MD" ]
assert_true "$?" "#262: README.md ist lesbar (Vorbedingung des Setup-Checks)"
grep -qF 'bash scripts/install-hooks.sh' "$README_MD"
assert_true "$?" "#262: README.md nennt 'bash scripts/install-hooks.sh' im lokalen Setup"

# ── verschoben aus der ausgelieferten Suite: #319 AC4: PROJECT-CONTEXT.md ist Teil des gedeckelten @import-Sets (CLAUDE.md dieses Repos) ──
# AC4 – „Index-Wachstum mitentschieden" hängt allein daran, dass PROJECT-CONTEXT.md (der
# Projekt-Gedächtnis inkl. Index der Projekt-Lessons; der Factory-Index steht seit #44 in lessons/INDEX.md) Teil der gedeckelten
# Summe IST. Verschwände die @import-Zeile, liefe der Index wieder unbegrenzt – und alle
# übrigen Deckel-Tests blieben grün, weil sie nur die Guidelines betrachten.
grep -qE '^@docs/factory/PROJECT-CONTEXT\.md$' "$FACTORY_ROOT/CLAUDE.md"
assert_true "$?" "#319 AC4: PROJECT-CONTEXT.md ist Teil des gedeckelten @import-Sets"
# Mutationsbeleg mit demselben Assert-Ausdruck: ohne die Zeile wird der Guard rot.
IC_AC4_MUT_319="$(mktemp)"
grep -vE '^@docs/factory/PROJECT-CONTEXT\.md$' "$FACTORY_ROOT/CLAUDE.md" > "$IC_AC4_MUT_319"
grep -qE '^@docs/factory/PROJECT-CONTEXT\.md$' "$IC_AC4_MUT_319"
assert_true "$([ $? -ne 0 ]; echo $?)" "#319 AC4 (Mutation): ohne die Import-Zeile wird derselbe Guard rot"
rm -f "$IC_AC4_MUT_319"

# ── verschoben aus der ausgelieferten Suite: #319 AC8: kein toter relativer Link in den Dateien dieses Tasks (inkl. CLAUDE.md, CONTRIBUTING.md, PROJECT-CONTEXT.md) ──
ic_dead_links_319() {  # $1 = Markdown-Datei → gibt "datei → ziel" je totem relativen Link aus
  local f="$1" d ziel
  d="$(dirname "$f")"
  grep -oE '\]\([^)#][^)]*\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//; s/#.*//' | while read -r ziel; do
    case "$ziel" in http*|"") continue ;; esac
    [ -e "$d/$ziel" ] || printf '%s → %s\n' "$f" "$ziel"
  done
}
# Positiv-/Negativ-Kontrolle des Helfers gegen ein eigenes Fixture (clean-code.md: ein
# Gate-Regex braucht beide Richtungen) – unabhängig vom Repo-Inhalt.
TMP_LNK_319="$(mktemp -d)"
printf 'Ziel\n' > "$TMP_LNK_319/ziel.md"
printf 'Ein [guter Link](ziel.md) und sonst nichts.\n' > "$TMP_LNK_319/doc.md"
assert_true "$([ -z "$(ic_dead_links_319 "$TMP_LNK_319/doc.md")" ]; echo $?)" \
  "#319 AC8 (Kontrolle): ein auflösender Link wird nicht gemeldet"
printf 'Ein [toter Link](gibt-es-nicht.md).\n' >> "$TMP_LNK_319/doc.md"
assert_true "$([ -n "$(ic_dead_links_319 "$TMP_LNK_319/doc.md")" ]; echo $?)" \
  "#319 AC8 (Kontrolle): ein toter Link wird gemeldet"
rm -rf "$TMP_LNK_319"
# Der eigentliche Guard über die Dateien dieses Tasks.
ic_dead_links_found_319=""
for f in CLAUDE.md CONTRIBUTING.md docs/factory/PROJECT-CONTEXT.md docs/factory/OPERATING.md \
         docs/factory/kleinfunde.md docs/factory/lessons/testing.md docs/factory/lessons/code-style.md \
         docs/factory/adr/047-import-kontext-guidelines-nach-erzwungenheit.md \
         docs/factory/guidelines/tdd-principles.md docs/factory/guidelines/testing-standards.md \
         docs/factory/guidelines/token-efficiency.md docs/factory/lessons/INDEX.md \
         docs/factory/adr/037-lessons-auslagern-aus-import-kontext.md; do
  ic_dead_links_found_319="$ic_dead_links_found_319$(ic_dead_links_319 "$FACTORY_ROOT/$f")"
done
assert_true "$([ -z "$ic_dead_links_found_319" ]; echo $?)" \
  "#319 AC8: kein toter relativer Link in den Dateien dieses Tasks"
[ -z "$ic_dead_links_found_319" ] || printf '%s\n' "$ic_dead_links_found_319" | sed 's/^/      /'

# ── verschoben aus der ausgelieferten Suite: #426 AK-A4: Anpassungsstellen sind laut echter Tabelle 'project' zugeordnet ──
for f_426 in CLAUDE.md factory.config.yml docs/factory/PROJECT-CONTEXT.md .gitignore \
    .claude/settings.json README.md CONTRIBUTING.md CHANGELOG.md; do
  own_side_426 project "$f_426"
  assert_exit 0 $? "#426 AK-A4: $f_426 ist 'project' zugeordnet"
done

# ── verschoben aus der ausgelieferten Suite: #426 AK-B1: git log --follow zeigt die Historie vor dem Umzug (Historie dieses Repos) ──
# `git mv` statt Kopie: die Historie vor dem Umzug ist über --follow erreichbar. Ein flacher
# Klon (CI) hat nur einen Commit – dort bleibt der Beleg lokal, der Rest oben gilt überall.
if [ "$(git -C "$FACTORY_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = "false" ]; then
  follow_n_426="$(git -C "$FACTORY_ROOT" log --follow --oneline -- docs/factory/adr/018-central-issue-seam.md | wc -l | tr -d ' ')"
  assert_true "$([ "$follow_n_426" -ge 2 ]; echo $?)" \
    "#426 AK-B1: git log --follow zeigt die Historie vor dem Umzug (ADR-018: $follow_n_426 Commits)"
else
  echo "  • #426 AK-B1: --follow-Beleg übersprungen (flacher Klon)"
fi

# ── verschoben aus der ausgelieferten Suite: #426 AK-B5: aktive Projekt-Dateien schreiben Factory-ADR-NNN statt ADR-NNN ──
bare_426=""
for f_426 in CLAUDE.md docs/factory/PROJECT-CONTEXT.md README.md CONTRIBUTING.md; do
  hits_426="$(bare_factory_adr_426 "$FACTORY_ROOT/$f_426" "$FACTORY_ADR_NUMS_426" | head -3)"
  [ -z "$hits_426" ] || bare_426="$bare_426
$f_426: $hits_426"
done
assert_true "$([ -z "$bare_426" ]; echo $?)" \
  "#426 AK-B5: aktive Projekt-Dateien schreiben Factory-ADR-NNN statt ADR-NNN für Factory-ADRs"
[ -z "$bare_426" ] || echo "$bare_426" | head -12 | sed 's/^/      /'

# ── #44 AK5: PROJECT-CONTEXT.md trägt keinen Factory-Index mehr (er steht ausgeliefert in lessons/INDEX.md; Guard: ausgelieferte Suite, #44 AK6) ──
# Datei-grep statt assert_absent: der Haystack ist groß (SIGPIPE-Lesson #426)
! grep -qF -- '#### Factory-Lessons' "$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md"
assert_true "$?" "#44 AK5: PROJECT-CONTEXT.md enthält keinen Abschnitt „#### Factory-Lessons“ mehr"
grep -qF -- '](lessons/INDEX.md)' "$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md"
assert_true "$?" "#44 AK5: „Bekannte Stolpersteine“ verweist auf lessons/INDEX.md"

# ── verschoben aus der ausgelieferten Suite: #431 AK-D2: CLAUDE.md importiert genau FACTORY.md und PROJECT-CONTEXT.md; Projekt-Regel, dünn ──
imports_431="$(grep -E '^@' "$CLAUDE_MD_431" | sort | tr '\n' ' ')"
assert_true "$([ "$imports_431" = "@docs/factory/FACTORY.md @docs/factory/PROJECT-CONTEXT.md " ]; echo $?)" \
  "#431 AK-D2: CLAUDE.md importiert genau FACTORY.md und PROJECT-CONTEXT.md (Ist: $imports_431)"
claude_flat_431="$(flat_286 "$CLAUDE_MD_431")"
assert_contains_286 "$claude_flat_431" 'Ownership pflegen' "#431 AK-D2: CLAUDE.md trägt die Projekt-Regel des Factory-Repos (Ownership pflegen)"
for gen_431 in '## Kernprinzip' '## Guardrails' '## Pipeline-Übersicht' '## Agent-Rollen'; do
  assert_absent "$claude_flat_431" "$gen_431" "#431 AK-D2: CLAUDE.md enthält den generischen Abschnitt '$gen_431' nicht mehr"
done
assert_true "$([ "$(awk 'END{print NR}' "$CLAUDE_MD_431")" -le 60 ]; echo $?)" "#431 AK-D2: CLAUDE.md bleibt dünn (≤ 60 Zeilen)"

# ── verschoben aus der ausgelieferten Suite: #431 AK-D4: verschachtelte Imports zählen vollständig (echte CLAUDE.md dieses Repos) ──
# AK-D4: verschachtelte Imports (CLAUDE.md → FACTORY.md → Guideline) zählen vollständig.
# Fixture nutzt die ECHTEN Dateien; nur eine nur über FACTORY.md eingebundene Guideline wird aufgebläht.
TMP_D4_431="$(mktemp -d)"
mkdir -p "$TMP_D4_431/docs/factory/guidelines"
cp "$CLAUDE_MD_431" "$TMP_D4_431/CLAUDE.md"
cp "$FACTORY_MD_431" "$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md" "$TMP_D4_431/docs/factory/"
cp "$FACTORY_ROOT"/docs/factory/guidelines/{clean-code,tdd-principles,testing-standards}.md "$TMP_D4_431/docs/factory/guidelines/"
FACTORY_DIR="$TMP_D4_431" bash "$IMPORT_CHECK" >/dev/null 2>&1
assert_exit 0 "$?" "#431 AK-D4 (Kontrolle): die kopierte echte Import-Kette ist unter der Grenze"
seq 1 "$IC_LIMIT_319" >> "$TMP_D4_431/docs/factory/guidelines/tdd-principles.md"
d4_out_431="$(FACTORY_DIR="$TMP_D4_431" bash "$IMPORT_CHECK" 2>&1)"; d4_rc_431=$?
assert_exit 1 "$d4_rc_431" "#431 AK-D4: Import nur über FACTORY.md reißt die Grenze → exit 1"
assert_contains_286 "$d4_out_431" 'tdd-principles.md' "#431 AK-D4: die Beitragsliste nennt die nur über FACTORY.md eingebundene Datei"
rm -rf "$TMP_D4_431"

# ── verschoben aus der ausgelieferten Suite: #431 AK-D5: Dauerkontext dieses Repos liegt unter dem Deckel; PROJECT-CONTEXT.md bleibt im Import ──
ctx_431="$(FACTORY_DIR="$FACTORY_ROOT" bash "$IMPORT_CHECK" 2>&1)"; ctx_rc_431=$?
assert_exit 0 "$ctx_rc_431" "#431 AK-D5 / #44 AK16: Dauerkontext liegt unter beiden Grenzen, Zeilen und Bytes ($ctx_431)"
# Factory-Issue #32: der Realstand-Test lebt nur hier (Projekt-QS); bei Rot ist die Breakdown-Liste die einzige Information.
[ "$ctx_rc_431" -eq 0 ] || printf '%s\n' "$ctx_431" | sed 's/^/      /'

# ── verschoben aus der ausgelieferten Suite: #431 AK-D5: PROJECT-CONTEXT.md bleibt im Dauerkontext (Import in CLAUDE.md) ──
grep -qxF '@docs/factory/PROJECT-CONTEXT.md' "$CLAUDE_MD_431"
assert_exit 0 "$?" "#431 AK-D5: PROJECT-CONTEXT.md bleibt im Dauerkontext (Import in CLAUDE.md)"

# ── verschoben aus der ausgelieferten Suite: #431 AK-E2: ignorierte Pfade bleiben unverändert (zusammengesetzte .gitignore dieses Repos) ──
# AK-E2: ignorierte Pfade unverändert – feste Probenliste gegen die committete .gitignore (Temp-Repo, --no-index).
TMP_GI_431="$(mktemp -d)"; git -C "$TMP_GI_431" init -q; cp "$FACTORY_ROOT/.gitignore" "$TMP_GI_431/"
ign_431="coverage/x .coverage-tmp431/x .env.local .DS_Store logs/a.log tasks/metrics-1.md tasks/pipeline-stuck-1.md foo.tmp.sh foo.tmp.config.ts .verify-x/a"
keep_431=".env.example tasks/interrupt-log.jsonl scripts/start-work.sh README.md"
for pr_431 in $ign_431; do
  git -C "$TMP_GI_431" check-ignore -q --no-index -- "$pr_431"
  assert_exit 0 "$?" "#431 AK-E2: $pr_431 bleibt ignoriert"
done
for pr_431 in $keep_431; do
  git -C "$TMP_GI_431" check-ignore -q --no-index -- "$pr_431"
  assert_exit 1 "$?" "#431 AK-E2: $pr_431 bleibt nicht ignoriert"
done
rm -rf "$TMP_GI_431"

# ── verschoben aus der ausgelieferten Suite: #431 AK-F2: .github/workflows/ci.yml existiert ──
assert_true "$([[ -f "$PCI_431" ]]; echo $?)" "#431 AK-F2: .github/workflows/ci.yml existiert"

# ── verschoben aus der ausgelieferten Suite: #431 AK-F2: ci.yml: genau der Job lint, Trigger push main + pull_request, valides YAML ──
assert_true "$([ "$(jobs_of_431 "$PCI_431")" = "lint project-self-test " ]; echo $?)" \
  "#431 AK-F2: ci.yml enthält genau die Jobs lint und project-self-test (Ist: $(jobs_of_431 "$PCI_431"))"
{ grep -q '^  push:' "$PCI_431" && grep -q 'branches: \[main\]' "$PCI_431" && grep -q '^  pull_request:' "$PCI_431"; }
assert_exit 0 "$?" "#431 AK-F2: ci.yml hat denselben Trigger wie vorher (push main + pull_request)"
# (Die Quelle des Lint-Kommandos prüft der Guard „CI-Lint-Job führt commands.lint aus" weiter oben.)
if command -v yq >/dev/null 2>&1; then
  yq '.' "$PCI_431" >/dev/null 2>&1
  assert_exit 0 "$?" "#431 AK-F2: ci.yml ist valides YAML"
else
  skip_yq "#431 AK-F2: ci.yml ist valides YAML"
fi

# ── verschoben aus der ausgelieferten Suite: #431 AK-F3: Required Check lint wird von der ci.yml dieses Repos gemeldet ──
all_jobs_431="$(jobs_of_431 "$FCI_431") $(jobs_of_431 "$PCI_431")"
chk_431=lint
assert_contains_286 "$all_jobs_431" "$chk_431 " "#431 AK-F3: Required Check '$chk_431' wird von einem Workflow gemeldet"

# ── verschoben aus der ausgelieferten Suite: #431 AK-F4: Workflows sind in OWNERSHIP.md geführt ──
# AK-F4: Workflows in OWNERSHIP.md zugeordnet, Skriptpfade existieren.
own_f_431="$FACTORY_ROOT/docs/factory/OWNERSHIP.md"
for wf_431 in "project|.github/workflows/ci.yml" "factory|.github/workflows/factory-poll.yml" "factory|.github/workflows/factory-ci.yml"; do
  grep -qF "| ${wf_431%%|*} | \`${wf_431#*|}\`" "$own_f_431"
  assert_exit 0 "$?" "#431 AK-F4: ${wf_431#*|} ist als ${wf_431%%|*} in OWNERSHIP.md geführt"
done

# ── verschoben aus der ausgelieferten Suite: #431 AK-F4: alle in den Projekt-Workflows (ci.yml, release.yml) genannten Skriptpfade existieren ──
miss_431=""
for wfp_431 in "$PCI_431" "$FACTORY_ROOT/.github/workflows/release.yml"; do
  [ -f "$wfp_431" ] || continue
  for sp_431 in $(grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' "$wfp_431" | sort -u); do
    [[ -f "$FACTORY_ROOT/$sp_431" ]] || miss_431="$miss_431 $(basename "$wfp_431"):$sp_431"
  done
done
assert_true "$([ -z "$miss_431" ]; echo $?)" "#431 AK-F4: alle in den Projekt-Workflows genannten Skriptpfade existieren (fehlt:${miss_431:- nichts})"

# ── verschoben aus der ausgelieferten Suite: #431 AK-H1: factory.config.yml dieses Repos trägt commands.* (format bewusst leer) ──
if [ "$HAS_YQ" = 1 ]; then
  for k_431 in lint test typecheck format coverage; do
    v_431="$(yq ".commands.$k_431" "$FACTORY_ROOT/factory.config.yml")"
    # format ist im Factory-Repo bewusst leer (Format-Gate deaktiviert); alle anderen tragen ein Kommando.
    if [ "$k_431" = format ]; then
      assert_true "$([ -z "$(yq '.commands.format // ""' "$FACTORY_ROOT/factory.config.yml")" ]; echo $?)" "#431 AK-H1: factory.config.yml hält commands.format bewusst leer"
    else
      assert_true "$([ -n "$v_431" ] && [ "$v_431" != null ]; echo $?)" "#431 AK-H1: factory.config.yml trägt commands.$k_431 (Ist: $v_431)"
    fi
  done
else
  skip_yq "#431 AK-H1"
fi

# ── verschoben aus der ausgelieferten Suite: #431 AK-H1: commands.* tragen die Werte des Factory-Repos ──
if [ "$HAS_YQ" = 1 ]; then
  # Die Werte des Factory-Repos (ADR-063 D9): Syntaxprüfung per `bash -n`, Self-Test-Suite, kein install, kein pnpm.
  cfg_431="$FACTORY_ROOT/factory.config.yml"
  # commands.test ist seit Factory-Issue #51 der Suite-Gate-Wrapper (überspringt die Suite bei reinem Spec-/Task-Diff).
  assert_true "$([ "$(yq '.commands.lint' "$cfg_431")" = "git ls-files -z '*.sh' | xargs -0 -n1 bash -n" ] && [ "$(yq '.commands.test' "$cfg_431")" = "bash scripts/project/checks/factory-suite-gate.sh" ] && [ -z "$(yq '.commands.install // ""' "$cfg_431")" ] && ! grep -v '^[[:space:]]*#' "$cfg_431" | grep -q pnpm; echo $?)" \
    "#431 AK-H1: commands.* tragen die Werte des Factory-Repos (bash -n, Suite-Gate-Wrapper, kein install, kein pnpm)"
else
  skip_yq "#431 AK-H1 Werte"
fi

# ── verschoben aus der ausgelieferten Suite: #431 AK-I1: das Factory-Repo trägt keine projekteigenen Aspekt-Labels ──
if [ "$HAS_YQ" = 1 ]; then
  CFG_431="$FACTORY_ROOT/factory.config.yml"
  assert_true "$([ "$(yq '.labels.aspects_extra // []' -o=json -I=0 "$CFG_431")" = '[]' ]; echo $?)" "#431 AK-I1: das Factory-Repo trägt keine projekteigenen Aspekt-Labels (labels.aspects_extra leer)"
else
  skip_yq "#431 AK-I1 aspects_extra"
fi

# ── verschoben aus der ausgelieferten Suite: #431 AK-I2: Label-Doku und Konfiguration dieses Repos stimmen überein ──
if [ "$HAS_YQ" = 1 ]; then
  DEF_431="$FACTORY_ROOT/factory.defaults.yml"; CFG_431="$FACTORY_ROOT/factory.config.yml"
  GW_431="$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md"; PCX_431="$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md"
  label_drift_431() {
    local eff g l out="" gw pc
    eff="$(yq eval-all '. as $i ireduce ({}; . * $i)' "$1" "$2")"
    gw="$(flat_286 "$3")"; pc="$(flat_286 "$4")"
    for g in $(printf '%s' "$eff" | yq '.labels.kinds[], .labels.aspects[]' -); do
      grep -qF -- "| \`$g\` |" <<< "$gw" || out="$out generisch-fehlt-in-git-workflow:$g"
    done
    for l in $(printf '%s' "$eff" | yq '.labels.aspects_extra[]' -); do
      grep -qF -- "| \`$l\` |" <<< "$pc" || out="$out projekt-fehlt-in-PROJECT-CONTEXT:$l"
      grep -qF -- "| \`$l\` |" <<< "$gw" && out="$out projekt-steht-in-git-workflow:$l"
    done
    printf '%s' "$out"
  }
  drift_431="$(label_drift_431 "$DEF_431" "$CFG_431" "$GW_431" "$PCX_431")"
  assert_true "$([ -z "$drift_431" ]; echo $?)" "#431 AK-I2: Label-Doku und Konfiguration stimmen überein (Abweichung:${drift_431:- keine})"
else
  skip_yq "#431 AK-I2 Label-Drift"
fi

# ── verschoben aus der ausgelieferten Suite: release.yml dieses Repos: Tag-Trigger, Rechte, Reihenfolge Prüfung → Release, valides YAML ──
RELEASE_YML_10="$FACTORY_ROOT/.github/workflows/release.yml"
assert_true "$([ -f "$RELEASE_YML_10" ]; echo $?)" "release.yml vorhanden"
if [ -f "$RELEASE_YML_10" ]; then
  grep -qE "^\s+tags: \['v\*'\]|^\s+- 'v\*'|^\s+tags:\s*$" "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: läuft auf Tag-Push (v*)"
  grep -q '^  push:' "$RELEASE_YML_10" && ! grep -q 'pull_request' "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: nur push, kein pull_request"
  grep -qE 'contents: write' "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: contents: write für das Release"
  grep -qF 'bash scripts/factory-release-check.sh' "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: ruft die Release-Prüfung auf"
  grep -qF 'bash scripts/factory-release-manifest.sh' "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: erzeugt das Manifest"
  grep -qF 'gh release create' "$RELEASE_YML_10" && grep -qF 'factory-release.json' "$RELEASE_YML_10"
  assert_exit 0 "$?" "release.yml: legt das Release mit dem Manifest als Asset an"
  # Anker ist die exakte `run:`-Zeile, nie ein Fragment: der Kopfkommentar nennt beide Schritte ebenfalls.
  ln_check_10="$(grep -nF 'run: bash scripts/factory-release-check.sh "$TAG"' "$RELEASE_YML_10" | head -1 | cut -d: -f1)"
  ln_create_10="$(grep -nF 'run: gh release create' "$RELEASE_YML_10" | head -1 | cut -d: -f1)"
  { [ -n "$ln_check_10" ] && [ -n "$ln_create_10" ] && [ "$ln_check_10" -lt "$ln_create_10" ]; }
  assert_true "$?" "release.yml: die Prüfung läuft vor dem Anlegen des Release (kein Release bei Abweichung)"
  if [ "$HAS_YQ" = 1 ]; then yq '.' "$RELEASE_YML_10" >/dev/null 2>&1; assert_exit 0 "$?" "release.yml ist valides YAML"; else skip_yq "release.yml ist valides YAML"; fi
fi

# ── verschoben aus der ausgelieferten Suite: C1: Herkunftsbegriffe nur an dokumentierten erlaubten Stellen (alle getrackten Dateien dieses Repos) ──
echo ""
echo "C1 Herkunftsbegriffe (PROJECT-CONTEXT.md → Konventionen → erlaubte Stellen):"
# Die Begriffe werden zur Laufzeit zusammengesetzt: als Literal stünden sie in dieser Datei selbst, und der
# Guard wäre immer rot (Content-Scan-Guard, dessen Phrase in der gescannten Datei steht – Lesson nothra/tch-gastro-services#319).
# Lange Begriffe (ab sieben Zeichen) zählen auch als Wortteil – Komposita wie `delete<Begriff>Action` (Factory-Issue
# #45, Q2); kurze Begriffe nur als ganzes Wort, sonst schlügen `match`, `switch` oder `neonatal` an.
C1_LONG_TERMS="Veranstal""tung|Montags""runde|Theken""wart|Heuchel""heim|tc""h-gastro"
C1_SHORT_TERMS="T""CH|Ne""on|Ver""cel"
# c1_hits_in <datei> → höchstens drei Treffer als `<zeile>:<text>`; der qualifizierte Herkunftsverweis zählt nicht.
c1_hits_in() {
  local unqualified
  unqualified="$(sed 's#nothra/tch-gastro-services##g' "$1")"
  { grep -nIiE -- "$C1_LONG_TERMS" <<< "$unqualified"
    grep -nIiwE -- "$C1_SHORT_TERMS" <<< "$unqualified"; } | sort -t: -k1,1n -u | head -3
}
# c1_allowed_place <pfad> → Exit 0, wenn der Pfad eine der erlaubten Stellen aus PROJECT-CONTEXT.md → „Konventionen" ist
c1_allowed_place() {
  case "$1" in README.md|CHANGELOG.md|docs/factory/PROJECT-CONTEXT.md|scripts/checks/tests/fixtures/lessons-split-426.tsv) return 0 ;; esac
  return 1
}
C1_PROBE="$(mktemp)"
c1_hits_on_line() { printf '%s\n' "$1" > "$C1_PROBE"; [ -n "$(c1_hits_in "$C1_PROBE")" ]; }
# AK8: jeder lange Begriff wird auch als Wortteil eines Kompositums gefunden (je Begriff ein Negativtest)
IFS='|' read -r -a c1_long_list <<< "$C1_LONG_TERMS"
for t_c1 in "${c1_long_list[@]}"; do
  c1_hits_on_line "const delete${t_c1}Action = 1"
  assert_true "$?" "C1 #45 AK8: Kompositum mit langem Begriff ist ein Treffer (delete<${#t_c1} Zeichen>Action)"
done
c1_hits_on_line "import Form from './${c1_long_list[0]}MetaForm.tsx'"
assert_true "$?" "C1 #45 AK8: <B1>MetaForm.tsx ist ein Treffer"
# AK9: kurze Begriffe als ganzes Wort weiter gefunden, als Wortteil nicht
IFS='|' read -r -a c1_short_list <<< "$C1_SHORT_TERMS"
for t_c1 in "${c1_short_list[@]}"; do
  c1_hits_on_line "Die ${t_c1}-Regel"
  assert_true "$?" "C1 #45 AK9: kurzer Begriff als ganzes Wort ist ein Treffer (${#t_c1} Zeichen)"
done
for w_c1 in match switch watch neonatal; do
  ! c1_hits_on_line "Ein Wort: $w_c1"
  assert_true "$?" "C1 #45 AK9: '$w_c1' ist kein Treffer"
done
# AK10: qualifizierter Herkunftsverweis und erlaubte Stellen bleiben Ausnahmen
! c1_hits_on_line 'siehe nothra/tch-gastro-services#12'
assert_true "$?" "C1 (Kontrolle): ein qualifizierter Herkunftsverweis ist kein Treffer"
for p_c1 in README.md CHANGELOG.md docs/factory/PROJECT-CONTEXT.md scripts/checks/tests/fixtures/lessons-split-426.tsv; do
  c1_allowed_place "$p_c1"
  assert_true "$?" "C1 #45 AK10: $p_c1 ist erlaubte Stelle"
done
! c1_allowed_place docs/factory/lessons/testing.md
assert_true "$?" "C1 #45 AK10: eine Lesson ist keine erlaubte Stelle"
rm -f "$C1_PROBE"
c1_files=0; c1_hits=""
while IFS= read -r -d '' f_c1; do
  c1_allowed_place "$f_c1" && continue
  [ -f "$FACTORY_ROOT/$f_c1" ] || continue
  c1_files=$((c1_files + 1))
  hit_c1="$(c1_hits_in "$FACTORY_ROOT/$f_c1")"
  [ -z "$hit_c1" ] || c1_hits="$c1_hits$f_c1: $hit_c1"$'\n'
done < <(git -C "$FACTORY_ROOT" ls-files -z)
assert_true "$([ "$c1_files" -gt 50 ]; echo $?)" "C1 (fail-closed): der Scan liest wirklich die getrackten Dateien (Ist: $c1_files)"
assert_true "$([ -z "$c1_hits" ]; echo $?)" "C1: Herkunftsbegriffe stehen nur an den dokumentierten erlaubten Stellen"
[ -z "$c1_hits" ] || printf '%s' "$c1_hits" | head -10 | sed 's/^/      /'

# ── Factory-Issue #45: Stack-Begriffe des Ursprungs-Projekts nicht in den ausgelieferten Anweisungstexten ──
# Ein Agent im Konsumenten liest Skills, Personas und Guidelines als Handlungsanweisung; Stack-Details des
# Ursprungs-Projekts (Werkzeuge, Pfade, Gates) gelten dort nicht. Die Liste ist Wissen über das Ursprungs-Projekt und
# steht darum hier, nicht in der ausgelieferten Suite (Factory-ADR-064 D6). ADRs, Lessons und Tests prüft der Guard
# bewusst nicht: dort stehen die Begriffe als Historie oder Testdaten (Spec 45, Q1).
echo ""
echo "#45 Stack-Begriffe des Ursprungs-Projekts (Anweisungstexte):"
STACK_TERMS_45=(pnpm db:seed drizzle playwright docs/routes.md db.transaction runAtomic vitest esbuild page.tsx next-auth frontend-react)
STACK_PATHS_45=(.claude/commands docs/factory/agents docs/factory/guidelines docs/factory/gitignore.factory scripts/checks/pre-push.sh)
# stack_hits_45 <wurzel> → je Treffer `<datei>:<zeile>:<text>`; Exit 0 = sauber, 1 = Treffer,
# 2 = keine geprüfte Datei gefunden oder eine nicht lesbar (fail-closed, nie still grün).
stack_hits_45() {
  local root="$1" f n=0 rc=0 t
  local -a pat=()
  for t in "${STACK_TERMS_45[@]}"; do pat+=(-e "$t"); done
  while IFS= read -r -d '' f; do
    n=$((n + 1))
    [ -r "$root/$f" ] || { echo "✗ nicht lesbar: $f"; return 2; }
    grep -nIiF "${pat[@]}" -- "$root/$f" | awk -v file="$f" '{ print file ":" $0 }' | grep . && rc=1
  done < <(git -C "$root" ls-files -z -- "${STACK_PATHS_45[@]}" 2>/dev/null)
  [ "$n" -gt 0 ] || { echo "✗ keine geprüfte Datei gefunden unter $root"; return 2; }
  return "$rc"
}
FX_45="$(mktemp -d)"
git -C "$FX_45" init -q
mkdir -p "$FX_45/.claude/commands" "$FX_45/docs/factory/agents" "$FX_45/docs/factory/adr" "$FX_45/docs/factory/lessons"
printf 'sauber\n' > "$FX_45/.claude/commands/skill.md"
printf 'sauber\n' > "$FX_45/docs/factory/agents/persona.md"
git -C "$FX_45" add -A
stack_hits_45 "$FX_45" >/dev/null
assert_exit 0 "$?" "#45 AK12 (Kontrolle): saubere Wegwerf-Kopie ist grün"
# AK12: jeder Begriff, in der Schreibweise der Liste und in Großbuchstaben, ist rot und nennt Datei und Zeile
for t_45 in "${STACK_TERMS_45[@]}"; do
  for v_45 in "$t_45" "$(printf '%s' "$t_45" | tr '[:lower:]' '[:upper:]')"; do
    printf 'sauber\nZeile mit %s darin\n' "$v_45" > "$FX_45/.claude/commands/skill.md"
    out_45="$(stack_hits_45 "$FX_45")"; rc_45=$?
    assert_true "$([ "$rc_45" -eq 1 ] && grep -qF -- ".claude/commands/skill.md:2:" <<< "$out_45"; echo $?)" "#45 AK12: '$v_45' ist rot mit Datei und Zeile (Exit $rc_45)"
  done
done
printf 'sauber\n' > "$FX_45/.claude/commands/skill.md"
# AK12/AK13 je Pfad aus Scope 4 der Spec: eine Datei je Pfad trägt einen Begriff und ist rot mit Datei und Zeile.
# Die Liste steht bewusst unabhängig von STACK_PATHS_45 – sie ist das Orakel; fehlt dort ein Pfad, wird genau
# dessen Test rot statt still nicht mehr geprüft.
SPEC_FILES_45=(.claude/commands/skill.md docs/factory/agents/persona.md docs/factory/guidelines/regel.md docs/factory/gitignore.factory scripts/checks/pre-push.sh)
for f_45 in "${SPEC_FILES_45[@]}"; do mkdir -p "$FX_45/$(dirname "$f_45")"; printf 'sauber\n' > "$FX_45/$f_45"; done
git -C "$FX_45" add -A
for f_45 in "${SPEC_FILES_45[@]}"; do
  printf 'pnpm test\n' > "$FX_45/$f_45"
  out_45="$(stack_hits_45 "$FX_45")"; rc_45=$?
  assert_true "$([ "$rc_45" -eq 1 ] && grep -qF -- "$f_45:1:" <<< "$out_45"; echo $?)" "#45 AK12: Begriff in $f_45 ist rot mit Datei und Zeile (Exit $rc_45)"
  printf 'sauber\n' > "$FX_45/$f_45"
done
# AK13: ein Begriff außerhalb der geprüften Dateien (ADR, Lesson) ist kein Treffer
# Dateiname zusammengesetzt: als Literal läse der ADR-Link-Check der ausgelieferten Suite ihn als toten Link.
adr_45="001""-x.md"
printf 'Playwright und Drizzle\n' > "$FX_45/docs/factory/adr/$adr_45"
printf 'pnpm build\n' > "$FX_45/docs/factory/lessons/testing.md"
git -C "$FX_45" add -A
stack_hits_45 "$FX_45" >/dev/null
assert_exit 0 "$?" "#45 AK13: Stack-Begriff in ADR/Lesson ist kein Treffer"
# AK14: keine geprüfte Datei (leeres Repo, falsche Wurzel) bzw. eine nicht lesbare ist rot statt grün
EMPTY_45="$(mktemp -d)"; git -C "$EMPTY_45" init -q
stack_hits_45 "$EMPTY_45" >/dev/null
assert_exit 2 "$?" "#45 AK14: leere Dateiliste ist rot (fail-closed)"
stack_hits_45 "$EMPTY_45/gibt-es-nicht" >/dev/null
assert_exit 2 "$?" "#45 AK14: falsche Wurzel ist rot (fail-closed)"
rm -f "$FX_45/docs/factory/agents/persona.md"
out_45="$(stack_hits_45 "$FX_45")"; rc_45=$?
assert_true "$([ "$rc_45" -eq 2 ] && grep -qF 'nicht lesbar: docs/factory/agents/persona.md' <<< "$out_45"; echo $?)" "#45 AK14: getrackte, aber nicht lesbare Datei ist rot (Exit $rc_45)"
rm -rf "$FX_45" "$EMPTY_45"
# AK15: jeder Pfad aus Scope 4 hat im echten Baum mindestens eine getrackte Datei – sonst wäre „sauber" trivial
for p_45 in .claude/commands docs/factory/agents docs/factory/guidelines docs/factory/gitignore.factory scripts/checks/pre-push.sh; do
  assert_true "$([ -n "$(git -C "$FACTORY_ROOT" ls-files -- "$p_45")" ]; echo $?)" "#45 AK15: $p_45 hat getrackte Dateien"
done
# AK15: der echte Baum ist sauber
out_45="$(stack_hits_45 "$FACTORY_ROOT")"; rc_45=$?
assert_exit 0 "$rc_45" "#45 AK15: die Anweisungstexte dieses Repos nennen keinen Stack-Begriff"
[ "$rc_45" -eq 0 ] || printf '%s\n' "$out_45" | head -10 | sed 's/^/      /'


# ── verschoben aus der ausgelieferten Suite: #212 AK9/AK10: .gitignore dieses Repos deckt Coverage-Temp generisch ab ──
GI212="$FACTORY_ROOT/.gitignore"
grep -qF '.coverage-tmp*/' "$GI212"
assert_true "$?" "#212 AK9: .gitignore enthält generisches Muster .coverage-tmp*/"
TMP_GI="$(mktemp -d)"; git -C "$TMP_GI" init -q; cp "$GI212" "$TMP_GI/.gitignore"
git -C "$TMP_GI" check-ignore -q ".coverage-tmp209/coverage-summary.json"
assert_true "$?" "#212 AK9: .coverage-tmp209/ (Vorfall-id) ist ignoriert"
git -C "$TMP_GI" check-ignore -q ".coverage-tmp999/x.json"
assert_true "$?" "#212 AK9: .coverage-tmp999/ (beliebige id) ist ignoriert"
# AK10: Vitest-Default-Coverage-Verzeichnis coverage/ ist ebenfalls ignoriert (getrackt-frei)
git -C "$TMP_GI" check-ignore -q "coverage/index.html"
assert_true "$?" "#212 AK10: Vitest-Default coverage/ ist ignoriert"
rm -rf "$TMP_GI"

# ─── Factory-Issue #22 · Verdrahtung der Projekt-Suite (AK2.16b-2, Factory-ADR-064 D6) ───────────────────────────────
# Der Schnitt darf im Factory-Repo keinen Gate-Verlust bedeuten: lokal führt pre-push.sh die Projekt-Checks aus
# scripts/project/checks/pre-push.d/ aus, in CI ein eigener Job in ci.yml. Angeker wird an der ECHTEN Aufrufzeile,
# nie an einem Dateinamen-Fragment (Lesson factory-workflow.md „Kommando ≠ Prosa-Erwähnung").
echo ""
echo "Verdrahtung der Projekt-Suite (pre-push.d + ci.yml):"
HOOK_22="$FACTORY_ROOT/scripts/project/checks/pre-push.d/10-project-tests.sh"
CALL_22='exec bash "$ROOT/scripts/project/tests/run-tests.sh"'
assert_true "$([ -x "$HOOK_22" ]; echo $?)" "#22 AK2.16b-2: pre-push.d/10-project-tests.sh existiert und ist ausführbar (sonst blockiert run_project_checks)"
assert_true "$(grep -qxF -- "$CALL_22" "$HOOK_22" 2>/dev/null; echo $?)" "#22 AK2.16b-2: der Hook ruft die Projekt-Suite über die echte Aufrufzeile auf"
# Verhalten statt Grep: der Hook gibt den Exit-Code der Suite weiter (rot blockiert den Push, grün lässt ihn durch)
hook_22() { # $1 = Exit-Code der Attrappe, $2… = zusätzliche Umgebung (NAME=WERT) → Exit-Code des Hooks
  local code="$1" dir rc; shift
  dir="$(mktemp -d)"; mkdir -p "$dir/scripts/project/tests"
  printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$dir/scripts/project/tests/run-tests.sh"
  env -u FACTORY_SELF_TEST_RUN FACTORY_DIR="$dir" "$@" bash "$HOOK_22" > /dev/null 2>&1; rc=$?   # eine von außen exportierte Markierung zählt nicht
  rm -rf "$dir"; return $rc
}
hook_22 0; assert_exit 0 $? "#22 AK2.16b-2: grüne Projekt-Suite → Hook grün"
hook_22 1; assert_exit 1 $? "#22 AK2.16b-2: rote Projekt-Suite → Hook rot (Push wird blockiert)"
# Kopplungsschutz: die ausgelieferte Suite ruft pre-push.sh echt gegen dieses Repo auf (#149, #265 …). Dort darf der Hook die
# Projekt-Suite nicht erneut starten – sonst läuft sie mehrfach verschachtelt, und ein Rot der Projekt-Suite färbt
# unbeteiligte Gate-Tests der ausgelieferten Suite falsch rot. Die ausgelieferte Suite markiert sich mit FACTORY_SELF_TEST_RUN.
hook_22 1 FACTORY_SELF_TEST_RUN=1; assert_exit 0 $? "#22 AK2.16b-2: innerhalb der ausgelieferten Suite (FACTORY_SELF_TEST_RUN) startet der Hook die Projekt-Suite nicht"
FACTORY_SELF_TEST_RUN=1 hook_22 1; assert_exit 1 $? "#22 AK2.16b-2: eine von außen exportierte Markierung verfälscht den Hook-Test nicht (hook_22 isoliert die Umgebung)"
assert_true "$(grep -qxF 'export FACTORY_SELF_TEST_RUN=1' "$CHECKS_DIR/tests/run-tests.sh"; echo $?)" "#22 AK2.16b-2: die ausgelieferte Suite setzt die Markierung FACTORY_SELF_TEST_RUN selbst"
# CI: ein Job führt die Suite aus, nachdem yq bereitgestellt ist (ohne yq würden die Config-Prüfungen nur überspringen)
JOB_22="$(ci_job_block project-self-test "$PCI_431")"
ci_ok_22() { # $1 = Job-Block → 0, wenn yq VOR der Suite bereitgestellt wird und die Suite per run:-Zeile läuft
  local yq_ln run_ln
  yq_ln="$(printf '%s\n' "$1" | grep -nF 'run: sudo bash scripts/install-yq.sh' | head -1 | cut -d: -f1)"
  run_ln="$(printf '%s\n' "$1" | grep -nxF '        run: bash scripts/project/tests/run-tests.sh' | head -1 | cut -d: -f1)"
  [ -n "$yq_ln" ] && [ -n "$run_ln" ] && [ "$yq_ln" -lt "$run_ln" ]
}
ci_ok_22 "$JOB_22"; assert_exit 0 $? "#22 AK2.16b-2: ci.yml Job project-self-test: yq bereitstellen, dann die Projekt-Suite (echte run:-Zeilen)"
ci_ok_22 "$(printf '%s\n' "$JOB_22" | grep -vxF '        run: bash scripts/project/tests/run-tests.sh')"
assert_exit 1 $? "#22 AK2.16b-2 (Mutation): ohne die run:-Zeile wird derselbe Guard rot"
ci_ok_22 "$(printf '%s\n' "$JOB_22" | grep -vF 'run: sudo bash scripts/install-yq.sh')"
assert_exit 1 $? "#22 AK2.16b-2 (Mutation): ohne die yq-Bereitstellung wird derselbe Guard rot"

# ─── Factory-Issue #23 · AK-28b: Zustand der Projekt-Fragmente und zusammengesetzten Dateien des echten Repos ─────────
# Aus der ausgelieferten Suite hierher verschoben (Factory-ADR-064 D6, AK-28c): Die Compose-Tests dort bauen ihre Fragmente
# selbst; was den Zustand der projekteigenen Dateien DIESES Repos prüft, gehört in die Projekt-Suite. Im Konsumenten
# übernimmt das Integritäts-Gate (`factory-integrity-check.sh`, lokale Stufe) den Abgleich „committet == Zusammensetzung“.
echo ""
echo "#23 AK-28b: Projekt-Fragmente und zusammengesetzte Dateien dieses Repos:"
for f_23 in .claude/settings.project.json .gitignore.project; do
  assert_true "$([[ -f "$FACTORY_ROOT/$f_23" ]]; echo $?)" "#431 AK-E1/E2 (verschoben): Projekt-Fragment $f_23 existiert"
done
jq -e . "$FACTORY_ROOT/.claude/settings.project.json" >/dev/null 2>&1
assert_exit 0 "$?" "#431 AK-E1 (verschoben): .claude/settings.project.json ist gültiges JSON"
FACTORY_DIR="$FACTORY_ROOT" bash "$FACTORY_ROOT/scripts/factory-sync.sh" --compose --check >/dev/null 2>&1
assert_exit 0 "$?" "#431 AK-E3 (verschoben): committete settings.json/.gitignore == Zusammensetzung der Fragmente (--check)"
FX_23="$(mktemp -d)"; mkdir -p "$FX_23/.claude" "$FX_23/docs/factory"
cp "$FACTORY_ROOT/.claude/settings.factory.json" "$FACTORY_ROOT/.claude/settings.project.json" "$FX_23/.claude/"
cp "$FACTORY_ROOT/docs/factory/gitignore.factory" "$FX_23/docs/factory/"
cp "$FACTORY_ROOT/.gitignore.project" "$FX_23/"
FACTORY_DIR="$FX_23" bash "$FACTORY_ROOT/scripts/factory-sync.sh" --compose >/dev/null 2>&1
cmp -s "$FX_23/.claude/settings.json" "$FACTORY_ROOT/.claude/settings.json"
assert_exit 0 "$?" "#431 AK-E3 (verschoben): settings.json byte-identisch zur Zusammensetzung der echten Fragmente"
cmp -s "$FX_23/.gitignore" "$FACTORY_ROOT/.gitignore"
assert_exit 0 "$?" "#431 AK-E3 (verschoben): .gitignore byte-identisch zur Zusammensetzung der echten Fragmente"
rm -rf "$FX_23"
# Guard (E8): das Factory-Repo trackt kein factory.lock – sonst wäre das Integritäts-Gate hier kein No-op mehr
git -C "$FACTORY_ROOT" ls-files --error-unmatch factory.lock >/dev/null 2>&1
assert_exit 1 "$?" "#23 E8: das Factory-Repo trackt kein factory.lock (Integritäts-Gate bleibt hier ein No-op)"
[ ! -e "$FACTORY_ROOT/factory.lock" ] && [ ! -L "$FACTORY_ROOT/factory.lock" ]
assert_exit 0 "$?" "#23 E8: im Arbeitsbaum des Factory-Repos liegt kein factory.lock"

# ─── Factory-Issue #22 · F-22.5: fehlende gesourcte Lib → rot und laut, nie still ─────────────────────────────────────
# Hängt eine Suite von einer Datei ab, die im Konsumenten fehlt, darf sie nicht mit „command not found" weiterlaufen und
# dabei womöglich grün enden. Beide Suiten werden dazu in einen Baum OHNE die geteilte Lib kopiert und müssen hart
# mit Exit 2 und dem Dateinamen abbrechen.
echo ""
echo "F-22.5 fehlende Helfer-Lib:"
nolib_22() { # $1 = Pfad der Suite relativ zur Repo-Wurzel → Ausgabe der Suite im Baum ohne Lib; Exit-Code durchreichen
  local dir rc; dir="$(mktemp -d)"; mkdir -p "$dir/$(dirname "$1")"
  cp "$FACTORY_ROOT/$1" "$dir/$1"
  env -u FACTORY_SELF_TEST_RUN bash "$dir/$1" 2>&1; rc=$?
  rm -rf "$dir"; return $rc
}
out_22="$(nolib_22 scripts/checks/tests/run-tests.sh)"
assert_exit 2 $? "#22 F-22.5: ausgelieferte Suite ohne assert-helpers.sh → Exit 2"
assert_contains_286 "$out_22" 'assert-helpers.sh' "#22 F-22.5: die Meldung nennt die fehlende Lib"
assert_absent "$out_22" 'command not found' "#22 F-22.5: kein Weiterlaufen mit „command not found“"
out_22="$(nolib_22 scripts/project/tests/run-tests.sh)"
assert_exit 2 $? "#22 F-22.5: Projekt-Suite ohne assert-helpers.sh → Exit 2"
assert_contains_286 "$out_22" 'assert-helpers.sh' "#22 F-22.5: die Meldung der Projekt-Suite nennt die fehlende Lib"

# ─── Factory-Issue #28 AK5: Label-Drift-Guard gegen die echte PROJECT-CONTEXT.md (aus der ausgelieferten Suite herausgelöst) ───
# Vorher prüfte #431 AK-I2 die echten Dateien dieses Repos; die ausgelieferte Suite nutzt jetzt eine Fixture. Der Zustand der
# echten Datei (jedes Label aus labels.aspects_extra beschrieben, keines in der generischen Tabelle) steht hier.
if [ "$HAS_YQ" = 1 ]; then
  drift_28="$(label_drift_431 "$FACTORY_ROOT/factory.defaults.yml" "$FACTORY_ROOT/factory.config.yml" \
    "$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md" "$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md")"
  assert_true "$([ -z "$drift_28" ]; echo $?)" "#28 AK5: Labels aus Defaults + factory.config.yml sind in git-workflow.md bzw. PROJECT-CONTEXT.md beschrieben ${drift_28:+($drift_28)}"
  assert_true "$(grep -qF -- '| Label | Aspekt |' "$FACTORY_ROOT/docs/factory/PROJECT-CONTEXT.md"; echo $?)" "#28 AK5: PROJECT-CONTEXT.md trägt die Label-Tabelle (Projekt-Labels)"
else
  skip_yq "#28 AK5: Label-Drift-Guard gegen die echte PROJECT-CONTEXT.md"
fi

# ─── Factory-Issue #51: Suite-Gate – ausgelieferte Suite bei reinem Spec-/Task-Diff überspringen ───
# Der Wrapper läuft gegen Wegwerf-Repos (FACTORY_DIR), in denen ein Stub am Pfad der ausgelieferten Suite liegt:
# SUITE_RAN_51 belegt den Start, STUB_RC_51 steuert ihren Exit-Code. Kein echter Suite-Lauf in der Projekt-Suite.
echo ""
echo "#51 Suite-Gate (Skip bei reinem Spec-/Task-Diff):"
GATE_51="$FACTORY_ROOT/scripts/project/checks/factory-suite-gate.sh"
REAL_GIT_51="$(command -v git)"
SKIP_MSG_51='nur Spec-/Task-Dateien geändert'
OUTSIDE_MSG_51='außerhalb von tasks/ und docs/specs/:'
commit_51() { git -C "$1" add -A && git -C "$1" -c user.email=t@t.com -c user.name=t commit -q -m "$2"; }
# mk_gate_repo_51 <dir> – main mit Suite-Stub, src.txt, tasks/old.md und .gitignore (*.log); origin/main als Ref
# auf main (kein Remote nötig); danach Feature-Branch ohne eigene Änderungen.
mk_gate_repo_51() {
  local d="$1"
  mk_feature_repo "$d" main
  mkdir -p "$d/scripts/checks/tests" "$d/tasks"
  printf '#!/usr/bin/env bash\necho SUITE_RAN_51\nexit "${STUB_RC_51:-0}"\n' > "$d/scripts/checks/tests/run-tests.sh"
  printf 'x\n' > "$d/src.txt"; printf 'alt\n' > "$d/tasks/old.md"; printf '*.log\n' > "$d/.gitignore"
  commit_51 "$d" base
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  git -C "$d" checkout -q -b feature/51-fixture
}
# mk_spec_only_51 <dir> – Repo wie oben plus ein Commit nur unter tasks/ und docs/specs/ (Ausgangslage AK1)
mk_spec_only_51() {
  mk_gate_repo_51 "$1"
  mkdir -p "$1/docs/specs"; printf 't\n' > "$1/tasks/task-1.md"; printf 's\n' > "$1/docs/specs/spec-1.md"
  commit_51 "$1" spec
}
# run_gate_51 <dir> [VAR=wert …] – Wrapper gegen das Wegwerf-Repo; Override nur, wenn der Test ihn übergibt
run_gate_51() { local d="$1"; shift; (cd "$d" && env -u FACTORY_FORCE_FULL_SUITE FACTORY_DIR="$d" "$@" bash "$GATE_51" 2>&1); }

# AK1: nur tasks/ + docs/specs/ → kein Suite-Start, Exit 0, Grund in der Ausgabe
d_51="$(mktemp -d)"; mk_spec_only_51 "$d_51"
out_51="$(run_gate_51 "$d_51")"; rc_51=$?
assert_exit 0 "$rc_51" "#51 AK1: reiner Spec-/Task-Diff → Exit 0"
assert_absent "$out_51" SUITE_RAN_51 "#51 AK1: die ausgelieferte Suite startet nicht"
assert_contains_286 "$out_51" "übersprungen" "#51 AK1: die Ausgabe nennt den Skip"
assert_contains_286 "$out_51" "$SKIP_MSG_51" "#51 AK1: die Ausgabe nennt den Grund (nur Spec-/Task-Dateien)"
# Gegenprobe: ignorierte Dateien zählen nicht (--exclude-standard) – Skip bleibt
printf 'l\n' > "$d_51/debug.log"
out_51="$(run_gate_51 "$d_51")"
assert_absent "$out_51" SUITE_RAN_51 "#51 AK3: ignorierte Datei (*.log) zählt nicht zur Änderungsmenge – Skip bleibt"

# AK5: Override erzwingt den vollen Lauf trotz AK1-Lage
out_51="$(run_gate_51 "$d_51" FACTORY_FORCE_FULL_SUITE=1)"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 AK5: FACTORY_FORCE_FULL_SUITE=1 → Suite läuft"
assert_contains_286 "$out_51" "Override FACTORY_FORCE_FULL_SUITE" "#51 AK5: die Ausgabe nennt den Override als Grund"
rm -rf "$d_51"

# AK2: Datei außerhalb → voller Lauf, Exit-Code der Suite unverändert (grün und rot)
d_51="$(mktemp -d)"; mk_spec_only_51 "$d_51"
printf 'y\n' > "$d_51/code.sh"; commit_51 "$d_51" code
out_51="$(run_gate_51 "$d_51")"; rc_51=$?
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 AK2: Datei außerhalb der erlaubten Pfade → Suite läuft"
assert_contains_286 "$out_51" "$OUTSIDE_MSG_51 code.sh" "#51 AK2: die Ausgabe nennt die Datei außerhalb als Grund"
assert_exit 0 "$rc_51" "#51 AK2: grüne Suite → Exit 0 durchgereicht"
out_51="$(run_gate_51 "$d_51" STUB_RC_51=3)"; rc_51=$?
assert_exit 3 "$rc_51" "#51 AK2: rote Suite (Exit 3) → Exit 3 unverändert durchgereicht"
rm -rf "$d_51"

# AK3: uncommittet (unstaged, staged) und untracked außerhalb zählen mit
for case_51 in untracked unstaged staged; do
  d_51="$(mktemp -d)"; mk_spec_only_51 "$d_51"
  case "$case_51" in
    untracked) printf 'n\n' > "$d_51/neu.txt" ;;
    unstaged)  printf 'geändert\n' > "$d_51/src.txt" ;;
    staged)    printf 'geändert\n' > "$d_51/src.txt"; git -C "$d_51" add src.txt ;;
  esac
  out_51="$(run_gate_51 "$d_51")"
  assert_contains_286 "$out_51" SUITE_RAN_51 "#51 AK3: $case_51 Datei außerhalb bei committet reinem Spec-/Task-Diff → Suite läuft"
  assert_contains_286 "$out_51" "$OUTSIDE_MSG_51" "#51 AK3: $case_51 – Grund ist die Datei außerhalb"
  rm -rf "$d_51"
done

# AK4: Umbenennung über die Pfadgrenze, in beide Richtungen
for case_51 in hinein heraus; do
  d_51="$(mktemp -d)"; mk_gate_repo_51 "$d_51"
  if [ "$case_51" = hinein ]; then git -C "$d_51" mv src.txt tasks/src.txt; else git -C "$d_51" mv tasks/old.md old.md; fi
  commit_51 "$d_51" "mv $case_51"
  out_51="$(run_gate_51 "$d_51")"
  assert_contains_286 "$out_51" SUITE_RAN_51 "#51 AK4: Umbenennung $case_51 (tasks/ ↔ außerhalb) → Suite läuft"
  assert_contains_286 "$out_51" "$OUTSIDE_MSG_51" "#51 AK4: Umbenennung $case_51 – Grund ist der Pfad außerhalb"
  rm -rf "$d_51"
done

# F1: origin/main fehlt → voller Lauf mit Grund
d_51="$(mktemp -d)"; mk_spec_only_51 "$d_51"
git -C "$d_51" update-ref -d refs/remotes/origin/main
out_51="$(run_gate_51 "$d_51")"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F1: origin/main fehlt → Suite läuft"
assert_contains_286 "$out_51" "Merge-Base mit origin/main nicht bestimmbar" "#51 F1: die Ausgabe nennt die fehlende Merge-Base"
rm -rf "$d_51"
# F1/F3: gar kein Git-Repo → voller Lauf (Merge-Base-Pfad greift zuerst)
d_51="$(mktemp -d)"; mkdir -p "$d_51/scripts/checks/tests"
printf '#!/usr/bin/env bash\necho SUITE_RAN_51\n' > "$d_51/scripts/checks/tests/run-tests.sh"
out_51="$(run_gate_51 "$d_51" GIT_CEILING_DIRECTORIES="$(dirname "$d_51")")"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F1/F3: kein Git-Repo → Suite läuft"
assert_contains_286 "$out_51" "Merge-Base mit origin/main nicht bestimmbar" "#51 F1/F3: kein Git-Repo – es greift der Merge-Base-Pfad"
rm -rf "$d_51"

# F2: leere Änderungsmenge (HEAD = origin/main) → voller Lauf
d_51="$(mktemp -d)"; mk_gate_repo_51 "$d_51"
out_51="$(run_gate_51 "$d_51")"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F2: leere Änderungsmenge → Suite läuft"
assert_contains_286 "$out_51" "leere Änderungsmenge" "#51 F2: die Ausgabe nennt die leere Änderungsmenge"
rm -rf "$d_51"

# F3: jeder Git-Befehl der Änderungsmenge scheitert einzeln (Stub im PATH bricht die Messung, nicht den Input)
# Der Stub scheitert, wenn die Argumentzeile auf das Glob-Muster FAIL_GIT_51 passt, sonst ruft er das echte git.
# Je Muster genau ein Aufruf: committeter diff (Basis-SHA hinter --no-renames), Working-Tree-diff (HEAD dahinter),
# ls-files (--others) – die Meldung muss den jeweiligen Schritt nennen, nie einen Skip.
bin_51="$(mktemp -d)"
cat > "$bin_51/git" <<EOF
#!/usr/bin/env bash
case "\$*" in *\$FAIL_GIT_51*) echo "git-stub: scheitert" >&2; exit 128 ;; esac
exec "$REAL_GIT_51" "\$@"
EOF
chmod +x "$bin_51/git"
for case_51 in "--no-renames [0-9a-f]*HEAD|git diff (committet)" "--no-renames HEAD|git diff (Working Tree)" "--others|git ls-files (untracked)"; do
  fail_51="${case_51%%|*}"; step_51="${case_51#*|}"
  d_51="$(mktemp -d)"; mk_spec_only_51 "$d_51"
  out_51="$(run_gate_51 "$d_51" PATH="$bin_51:$PATH" FAIL_GIT_51="$fail_51")"
  assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F3: $step_51 scheitert → Suite läuft"
  assert_contains_286 "$out_51" "Git-Fehler bei $step_51" "#51 F3: die Ausgabe nennt den gescheiterten Schritt ($step_51)"
  assert_absent "$out_51" "übersprungen" "#51 F3: $step_51 – ein Fehler wird nie als Skip gelesen"
  rm -rf "$d_51"
done
rm -rf "$bin_51"

# F4: Sonderzeichen – Zeilenumbruch/Leerzeichen in tasks/ bleibt erlaubt, Leerzeichen-Pfad außerhalb nicht
d_51="$(mktemp -d)"; mk_gate_repo_51 "$d_51"
printf 't\n' > "$d_51/tasks/a b"$'\n'"c.md"; commit_51 "$d_51" sonderzeichen
out_51="$(run_gate_51 "$d_51")"
assert_absent "$out_51" SUITE_RAN_51 "#51 F4: Datei mit Leerzeichen und Zeilenumbruch unter tasks/ → Skip (NUL-getrennt gelesen)"
printf 'x\n' > "$d_51/my tasks"; out_51="$(run_gate_51 "$d_51")"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F4: Datei 'my tasks' außerhalb → Suite läuft"
rm -rf "$d_51"

# F5: Präfix-Verwechslung – tasks-old/ und docs/specs-archive/ sind nicht erlaubt
for p_51 in tasks-old/x.md docs/specs-archive/x.md; do
  d_51="$(mktemp -d)"; mk_gate_repo_51 "$d_51"
  mkdir -p "$d_51/$(dirname "$p_51")"; printf 'x\n' > "$d_51/$p_51"; commit_51 "$d_51" praefix
  out_51="$(run_gate_51 "$d_51")"
  assert_contains_286 "$out_51" SUITE_RAN_51 "#51 F5: $p_51 zählt nicht als erlaubt → Suite läuft"
  assert_contains_286 "$out_51" "$OUTSIDE_MSG_51 $p_51" "#51 F5: die Ausgabe nennt $p_51"
  rm -rf "$d_51"
done

# AK6 (Verhalten): Wrapper im echten pre-push-Hook eines Worktrees – dort exportiert Git GIT_DIR u. a.; der Hook ist ein
# Einzeiler (geprüft wird der Git-Hook-Kontext, nicht pre-push.sh). Bare-Remote liefert ein echtes origin/main.
r_51="$(mktemp -d)"; mkdir -p "$r_51/main"; mk_gate_repo_51 "$r_51/main"
git init -q --bare "$r_51/origin.git"
git -C "$r_51/main" remote add origin "$r_51/origin.git"
git -C "$r_51/main" push -q origin main && git -C "$r_51/main" fetch -q origin
mkdir -p "$r_51/hooks"
printf '#!/usr/bin/env bash\nFACTORY_DIR="$PWD" exec bash "%s"\n' "$GATE_51" > "$r_51/hooks/pre-push"; chmod +x "$r_51/hooks/pre-push"
git -C "$r_51/main" config core.hooksPath "$r_51/hooks"
git -C "$r_51/main" worktree add -q -b feature/51-wt "$r_51/wt"
wt_51="$r_51/wt"
push_51() { (cd "$wt_51" && env -u FACTORY_FORCE_FULL_SUITE git push origin feature/51-wt 2>&1); }
printf 't\n' > "$wt_51/tasks/task-wt.md"; commit_51 "$wt_51" "wt spec"
out_51="$(push_51)"; rc_51=$?
assert_exit 0 "$rc_51" "#51 AK6: Push eines reinen Task-Commits aus einem Worktree gelingt"
assert_contains_286 "$out_51" "$SKIP_MSG_51" "#51 AK6: pre-push-Hook im Worktree → Skip-Meldung"
assert_absent "$out_51" SUITE_RAN_51 "#51 AK6: pre-push-Hook im Worktree → die Suite startet nicht"
printf 'u\n' > "$wt_51/neu-wt.txt"; printf 't2\n' > "$wt_51/tasks/task-wt2.md"; git -C "$wt_51" add tasks
git -C "$wt_51" -c user.email=t@t.com -c user.name=t commit -q -m "wt spec 2"
out_51="$(push_51)"; rc_51=$?
assert_exit 0 "$rc_51" "#51 AK6: Push mit grüner Suite-Attrappe im Worktree-Hook gelingt (Exit der Suite durchgereicht)"
assert_contains_286 "$out_51" SUITE_RAN_51 "#51 AK6: untracked Datei außerhalb im Worktree → Suite läuft im Hook"
assert_contains_286 "$out_51" "$OUTSIDE_MSG_51 neu-wt.txt" "#51 AK6: Hook im Worktree – Grund ist die Datei außerhalb"
unset -f push_51; rm -rf "$r_51"

# AK6: pre-push.sh und run-pipeline.sh lösen commands.test über dieselbe gate_command-Funktion auf → beide erhalten den Wrapper
if [ "$HAS_YQ" = 1 ]; then
  cmd_51="$(env -u FACTORY_TEST_COMMAND bash -c 'FACTORY_DIR="$1"; source "$1/scripts/lib/gate-config.sh"; gate_command test required' _ "$FACTORY_ROOT")"
  assert_true "$([ "$cmd_51" = "bash scripts/project/checks/factory-suite-gate.sh" ]; echo $?)" "#51 AK6: gate_command test liefert den Suite-Gate-Wrapper (Ist: $cmd_51)"
  assert_true "$(grep -qF -- 'TEST_COMMAND="$(gate_command test required)"' "$CHECKS_DIR/pre-push.sh"; echo $?)" "#51 AK6: pre-push.sh löst das Test-Kommando über gate_command auf"
  assert_true "$(grep -qF -- 'TEST_CMD="$(gate_command test required)"' "$SCRIPTS_DIR/run-pipeline.sh"; echo $?)" "#51 AK6: run-pipeline.sh löst das Test-Kommando über gate_command auf"
else
  skip_yq "#51 AK6"
fi
# Der Wrapper startet die ausgelieferte Suite per exec (Exit-Code unverändert, AK2)
assert_true "$(grep -qF -- 'exec bash "$SUITE"' "$GATE_51"; echo $?)" "#51 AK2: der Wrapper startet die Suite per exec"

# ─── Ergebnis ────────────────────────────────────────────────────────────────
print_summary
