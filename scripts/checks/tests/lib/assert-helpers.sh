#!/usr/bin/env bash
# assert-helpers.sh – gemeinsame Prüf-Helfer der Test-Suiten (Factory-Datei, #432 / Q10)
#
# Wird gesourct – nie direkt ausgeführt – von `scripts/checks/tests/run-tests.sh` (Factory-Suite)
# und `scripts/project/tests/run-project-tests.sh` (Projekt-Suite). Es gibt genau eine Kopie:
# die Helfer gehören der Factory und kommen ab T2 mit Factory-Updates.
#
# Stellt bereit: die Zähler PASS/FAIL, die Farben, assert_exit/assert_true/assert_contains_286/
# assert_absent, flat_286, mk_feature_repo, ls_mode_matches, HAS_YQ/skip_yq, ci_job_block und
# print_summary (Ergebnis-Fußzeile samt Exit-Code).
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

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
# ("grep -qF-Fixed-String-Regressionstest gegen Markdown-Prosa", #240/#249/#286): ab zwei
# Mehrwort-Checks gegen dieselbe Datei lohnt der Helper mehr als Zeilen-für-Zeile-Vorsicht.
# Der Namenssuffix stammt aus dem #286-Block, in dem der Helper entstand; er steht hier oben,
# weil ihn inzwischen mehrere Blöcke nutzen (#236, #286).
# Das zweite `tr` fasst Leerzeichen-Folgen zusammen: der dominante Markdown-Stil dieser Doku
# rückt Folgezeilen um zwei Leerzeichen ein, sonst wäre die Umbruch-Toleranz genau bei
# eingerückten Fortsetzungen wieder wirkungslos. Preis: Phrasen mit MEHREREN aufeinander
# folgenden Leerzeichen sind über diesen Lesepfad nicht ankerbar.
flat_286() { tr '\n' ' ' < "$1" | tr -s ' '; }

# assert_contains_286 <geflachter-inhalt> <phrase> <beschreibung>
#
# Das `--` vor dem Pattern (seit #334) ist nicht kosmetisch: ohne es liest grep eine Phrase,
# die mit `-` beginnt (`--no-telemetry`, `-v`, …), als OPTION und bricht mit einem
# Usage-Fehler ab – der Test wird rot bzw. der Abwesenheits-Spiegel grün, ohne dass die
# Phrase je gesucht wurde. Genau diese Falle traf #319 dreimal im selben PR und #334 erneut;
# clean-code.md („Config-/nutzerkontrollierte Werte als Daten behandeln") verlangt das `--`
# ohnehin. Die Kontroll-Assertion dazu steht im #334-Block.
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
# existiert (Lesson aus #265). Genutzt von den pre-push-Verhaltenstests in #149 und #319.
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
# des Folge-Jobs (kein "wort:"-Muster) fälschlich mit einschließen (Lesson #255).
ci_job_block() {
  awk -v j="$1" '$0 ~ "^  " j ":" {f=1; next} /^  ([A-Za-z0-9_-]+:|# ───)/{if (f) exit} f' "$2"
}

# print_summary – Ergebnis-Fußzeile; der Rückgabewert (0 nur ohne Rot) ist der Exit-Code der Suite.
print_summary() {
  echo ""
  echo -e "Ergebnis: ${GREEN}${PASS} grün${NC}, ${RED}${FAIL} rot${NC}"
  [[ "$FAIL" -eq 0 ]]
}
