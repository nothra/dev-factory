#!/usr/bin/env bash
# assert-helpers.sh – gemeinsame Prüf-Helfer der Test-Suiten (Factory-Datei, nothra/tch-gastro-services#432 / Q10)
#
# Wird gesourct – nie direkt ausgeführt – von `scripts/checks/tests/run-tests.sh` (Factory-Suite)
# und `scripts/project/tests/run-tests.sh` (Projekt-Suite). Es gibt genau eine Kopie:
# die Helfer gehören der Factory und kommen ab T2 mit Factory-Updates.
#
# Stellt bereit: die Zähler PASS/FAIL, die Farben, assert_exit/assert_true/assert_contains_286/
# assert_absent, flat_286, label_drift_431, mk_feature_repo, ls_mode_matches, HAS_YQ/skip_yq, ci_job_block, cp_pipeline_libs, bare_factory_adr_426 und
# print_summary (Ergebnis-Fußzeile samt Exit-Code).
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# NO_LOCK_FILE: Pfad, den es nie gibt – Tests des Tabellenmodus setzen ihn als FACTORY_LOCK_FILE, damit ein factory.lock im Repo
# (Konsument) sie nicht in den Lock-Modus zieht. Eine Stelle, falls der Env-Name von ownership-check.sh sich je ändert.
NO_LOCK_FILE=/nicht/vorhanden/factory.lock

# Repo-lokale Git-Variablen neutralisieren (Factory-Issue #6): Läuft eine Suite aus einem Git-Hook (z. B. als
# commands.test im pre-push-Hook eines Worktrees), exportiert Git GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE. Sie würden
# in jedes Wegwerf-Repo der Tests durchschlagen und den echten Worktree verändern (Branch, Remote, Dateien).
# Bewusst eine feste Liste statt `git rev-parse --local-env-vars`: GIT_CONFIG_* bleibt erhalten (kein Repo-Bezug).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_IMPLICIT_WORK_TREE \
      GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES


PASS=0
FAIL=0

# assert_exit <erwarteter-code> <tatsächlicher-code> <beschreibung>
assert_exit() {
  local expected="$1" actual="$2" desc="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${desc}"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}✗${NC} ${desc} (erwartet exit=${expected}, war ${actual})"
  fi
}

# assert_true <bedingung-exit> <beschreibung>  (0 = erfüllt)
assert_true() {
  local cond="$1" desc="$2"
  if [[ "$cond" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}✓${NC} ${desc}"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}✗${NC} ${desc}"
  fi
}

# flat_286 <datei> – Datei-Inhalt lesen, Zeilenumbrüche durch Leerzeichen ersetzt.
# Mehrwort-Content-Checks gegen Markdown-Prosa prüfen eine Aussage, keine Kommando-/Aufrufzeile –
# ein harmloser Umbruch mitten im Satz macht einen reinen `grep -qF`-Mehrwort-Anker sonst lautlos
# rot (Präsenz-Guard) bzw. lautlos grün (Abwesenheits-Guard). Lesson factory-workflow.md
# ("grep -qF-Fixed-String-Regressionstest gegen Markdown-Prosa", nothra/tch-gastro-services#240/#249/#286): ab zwei
# Mehrwort-Checks gegen dieselbe Datei lohnt der Helper mehr als Zeilen-für-Zeile-Vorsicht.
# Der Namenssuffix stammt aus dem nothra/tch-gastro-services#286-Block, in dem der Helper entstand; er steht hier oben,
# weil ihn inzwischen mehrere Blöcke nutzen (nothra/tch-gastro-services#236, nothra/tch-gastro-services#286).
# Das zweite `tr` fasst Leerzeichen-Folgen zusammen: der dominante Markdown-Stil dieser Doku
# rückt Folgezeilen um zwei Leerzeichen ein, sonst wäre die Umbruch-Toleranz genau bei
# eingerückten Fortsetzungen wieder wirkungslos. Preis: Phrasen mit MEHREREN aufeinander
# folgenden Leerzeichen sind über diesen Lesepfad nicht ankerbar.
flat_286() { tr '\n' ' ' < "$1" | tr -s ' '; }

# label_drift_431 <defaults> <config> <git-workflow.md> <PROJECT-CONTEXT.md> → Liste der Abweichungen (leer = ok); braucht yq.
# Generische Labels stehen als Tabellenzeile in git-workflow.md, projekteigene (labels.aspects_extra) als Tabellenzeile in
# PROJECT-CONTEXT.md – und nicht umgekehrt. Hier statt in einer Suite, weil die ausgelieferte Suite den Guard gegen eine
# Fixture-PROJECT-CONTEXT.md fährt und die Projekt-Suite gegen die echte (Factory-Issue #28).
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

# assert_contains_286 <geflachter-inhalt> <phrase> <beschreibung>
#
# Das `--` vor dem Pattern (seit nothra/tch-gastro-services#334) ist nicht kosmetisch: ohne es liest grep eine Phrase,
# die mit `-` beginnt (`--no-telemetry`, `-v`, …), als OPTION und bricht mit einem
# Usage-Fehler ab – der Test wird rot bzw. der Abwesenheits-Spiegel grün, ohne dass die
# Phrase je gesucht wurde. Genau diese Falle traf nothra/tch-gastro-services#319 dreimal im selben PR und nothra/tch-gastro-services#334 erneut;
# clean-code.md („Config-/nutzerkontrollierte Werte als Daten behandeln") verlangt das `--`
# ohnehin. Die Kontroll-Assertion dazu steht im nothra/tch-gastro-services#334-Block.
# Verdichtet das wiederkehrende "enthält der geflachte Inhalt die Phrase?" auf einen Aufruf.
assert_contains_286() {
  printf '%s' "$1" | grep -qF -- "$2"
  assert_true "$?" "$3"
}

# assert_absent <haystack> <phrase> <beschreibung>
# Spiegel zu assert_contains_286: die Phrase darf NICHT vorkommen. Kapselt die Subtilität, dass
# `$?` beim Expandieren der Command Substitution aus dem Elternkontext geerbt wird – ausgeschrieben
# (`assert_true "$([ $? -ne 0 ]; echo $?)"`) ist das korrekt, aber an jeder Aufrufstelle neu zu
# entziffern.
assert_absent() {
  printf '%s' "$1" | grep -qF -- "$2"
  assert_true "$([ $? -ne 0 ]; echo $?)" "$3"
}

# mk_feature_repo <verzeichnis> <branch> – leeres git-Repo auf einem Feature-Branch, bereit für
# einen echten pre-push.sh-Lauf. Die lokale Git-Identität wird explizit gesetzt: ohne sie
# scheitert der Commit in einer identitätslosen Umgebung (CI), wo kein globaler Fallback
# existiert (Lesson aus nothra/tch-gastro-services#265). Genutzt von den pre-push-Verhaltenstests in nothra/tch-gastro-services#149 und nothra/tch-gastro-services#319.
mk_feature_repo() {
  git -C "$1" init -q
  git -C "$1" checkout -q -b "$2"
  git -C "$1" -c user.email=t@t.com -c user.name=t commit -q --allow-empty -m init
}

# ls_mode_matches <datei> <modus-präfix, z. B. '-rw-------'>
# Modus-Vergleich über `ls -l` (die `stat`-Flags sind zwischen BSD und GNU unvereinbar).
# Präfix-Match, weil macOS bei ACLs/xattrs ein '+'/'@' an die Modus-Spalte anhängt.
ls_mode_matches() {
  case "$(ls -l "$1" 2>/dev/null)" in "$2"*) return 0 ;; *) return 1 ;; esac
}

# yq ist Prerequisite für run-pipeline.sh (ADR-009 A: verbindlich, kein Fallback) –
# ABER die Test-Suite bleibt yq-frei lauffähig: Struktur-Checks (grep) laufen immer,
# yq-abhängige Resolution-/Config-Wert-Checks (und Tests, die run-pipeline.sh starten)
# nur, wenn yq vorhanden ist. Sonst lautes Skip statt rot – so läuft die Suite auch in
# Test-Images adoptierter Projekte ohne yq grün; die echte Resolution wird dort getestet,
# wo yq da ist (Template-CI, Runtime-Image, Devs mit yq).
command -v yq >/dev/null 2>&1 && HAS_YQ=1 || HAS_YQ=0
skip_yq() { echo "  • ${1} – übersprungen (yq fehlt, ADR-009)"; }

# ci_job_block <job-name> <workflow-datei> – gibt den Block genau EINES Workflow-Jobs aus.
# Nötig, weil eine Prüfung über das ganze File an einem Fremd-Job vorbeirutschen kann (ein
# anderer Job nutzt pnpm/yq durchaus). Bricht sowohl am nächsten Job-Key als auch am nächsten
# Job-Trennkommentar ("  # ─── …") ab – reine Key-Erkennung würde den führenden Kommentarkopf
# des Folge-Jobs (kein "wort:"-Muster) fälschlich mit einschließen (Lesson nothra/tch-gastro-services#255).
ci_job_block() {
  awk -v j="$1" '$0 ~ "^  " j ":" {f=1; next} /^  ([A-Za-z0-9_-]+:|# ───)/{if (f) exit} f' "$2"
}

# cp_pipeline_libs <repo-root> – legt ALLE von run-pipeline.sh gesourcten scripts/lib/-Dateien
# in eine Temp-Repo-Kopie. Einziger Ort, an dem eine neu gesourcte Lib nachzutragen ist: fehlt
# sie, bricht run-pipeline.sh unter `set -euo pipefail` schon am `source` ab und der Test wird
# rot aus dem falschen Grund (bash-gotchas.md §5; Vorfälle nothra/tch-gastro-services#91, nothra/tch-gastro-services#197). Vor nothra/tch-gastro-services#334 stand dieselbe
# cp-Gruppe achtmal kopiert in der Suite – jede Kopie eine Stelle, die man beim nächsten Seam
# vergessen kann.
cp_pipeline_libs() {
  mkdir -p "$1/scripts/lib"
  cp "$SCRIPTS_DIR/lib/report-verdict.sh" \
     "$SCRIPTS_DIR/lib/tier-select.sh" \
     "$SCRIPTS_DIR/lib/verify-final-state.sh" \
     "$SCRIPTS_DIR/lib/telemetry-harvest.sh" \
     "$SCRIPTS_DIR/lib/gate-config.sh" \
     "$1/scripts/lib/"
}

# bare_factory_adr_426 <datei> <nummernliste> – Treffer `ADR-NNN` ohne Präfix (Spec nothra/tch-gastro-services#426 AK-B5); geteilt zwischen
# der ausgelieferten Suite (Kontrollen) und der Projekt-Suite (Prüfung der Projekt-Dateien).
bare_factory_adr_426() { # $1 = Datei, $2 = Nummernliste (Leerzeichen) → Treffer `ADR-NNN` ohne Präfix
  local alt; alt="$(printf '%s' "$2" | tr ' ' '|')"
  grep -noE "(^|[^A-Za-z-])ADR-($alt)([^0-9]|$)" "$1"
}

# print_summary – Ergebnis-Fußzeile; der Rückgabewert (0 nur ohne Rot) ist der Exit-Code der Suite.
print_summary() {
  echo ""
  echo -e "Ergebnis: ${GREEN}${PASS} grün${NC}, ${RED}${FAIL} rot${NC}"
  [[ "$FAIL" -eq 0 ]]
}
