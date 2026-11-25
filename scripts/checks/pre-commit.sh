#!/usr/bin/env bash
# pre-commit.sh – Quality Gate vor jedem Commit
#
# Wird ausgeführt: git commit (über .git/hooks/pre-commit)
# Blockiert den Commit wenn ein Check fehlschlägt.
#
# Lint-Befehl: factory.config.yml → commands.lint (Env FACTORY_LINT_COMMAND hat Vorrang).
# Projekteigene Checks: ausführbare Skripte in scripts/project/checks/pre-commit.d/.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=../lib/gate-config.sh
source "$FACTORY_DIR/scripts/lib/gate-config.sh"

echo ""
echo -e "${YELLOW}Pre-Commit Checks...${NC}"

FAILED=0

# Staged-Diff einmal lesen und per Here-String prüfen, nie `git diff --cached | grep -q …`: grep -q endet beim ersten
# Treffer, git stirbt bei großem Diff an SIGPIPE, pipefail macht die if-Bedingung falsch → Check grün trotz Treffer
# (Factory-Issue #70, bash-gotchas §3). Fail-closed: ist der Diff nicht lesbar, prüft kein Check auf leerer Eingabe.
if ! STAGED_DIFF="$(git diff --cached)"; then
  echo -e "  ${RED}✗${NC} Staged-Diff nicht lesbar (git diff --cached) – commit blockiert"
  exit 1
fi

# diff_check <grep-option> <muster> – Treffer im Staged-Diff? Status 0 = Treffer, 1 = kein Treffer, 2 = Prüfung
# gescheitert. `grep -c` statt `-q`: nur ein sauberes „0" mit Exit 1 ist „kein Treffer". Ein grep-Fehler (Exit > 1) oder
# eine gescheiterte Here-String-Umleitung (bash kann die Temp-Datei nicht anlegen, Status 1 ohne Ausgabe) ist kein
# „✓", sondern blockiert (fail-closed, Factory-Issue #70 AK10).
diff_check() {
  local count rc=0
  count="$(grep -c "$1" "$2" <<< "$STAGED_DIFF")" || rc=$?
  if [ "$rc" -eq 0 ]; then return 0; fi
  if [ "$rc" -eq 1 ] && [ "$count" = "0" ]; then return 1; fi
  return 2
}

# check_not_runnable <check> – eigene Meldung, wenn diff_check Status 2 liefert; blockiert den Commit.
check_not_runnable() {
  echo -e "  ${RED}✗${NC} $1: Prüfung nicht ausführbar (grep fehlgeschlagen) – commit blockiert"
  FAILED=1
}

# ─── Check 1: Keine ungelösten Merge-Konflikte ───────────────────────────────
check_rc=0; diff_check -E "^[+](<<<<<<<|=======|>>>>>>>)" || check_rc=$?
if [ "$check_rc" -eq 0 ]; then
  echo -e "  ${RED}✗${NC} Ungelöste Merge-Konflikte gefunden"
  FAILED=1
elif [ "$check_rc" -eq 1 ]; then
  echo -e "  ${GREEN}✓${NC} Keine Merge-Konflikte"
else
  check_not_runnable "Merge-Konflikte"
fi

# ─── Check 2: Keine Debug-Statements ─────────────────────────────────────────
# Semikolon als Zeichenklasse `[;]`: gleiche Regex, aber die Zeile trifft sich als geänderte Diff-Zeile nicht selbst.
check_rc=0; diff_check -E "^\+.*(console\.log|System\.out\.print|debugger[;]|binding\.pry|pdb\.set_trace)" || check_rc=$?
if [ "$check_rc" -eq 0 ]; then
  echo -e "  ${RED}✗${NC} Debug-Statements gefunden (console.log / System.out.print / debugger)"
  echo -e "     Bitte vor dem Commit entfernen"
  FAILED=1
elif [ "$check_rc" -eq 1 ]; then
  echo -e "  ${GREEN}✓${NC} Keine Debug-Statements"
else
  check_not_runnable "Debug-Statements"
fi

# ─── Check 3: Keine TODO ohne Ticket-Referenz ────────────────────────────────
if awk '/^\+.*TODO/ && !/#[0-9]/ {f=1} END{exit !f}' <<< "$STAGED_DIFF"; then
  echo -e "  ${YELLOW}⚠${NC}  TODO ohne Ticket-Referenz gefunden"
  echo -e "     Format: // TODO #123 oder // TODO(username): mit Ticket"
  # Nur Warnung, kein Block
fi

# ─── Check 4: Keine Secrets/Keys hardkodiert ─────────────────────────────────
check_rc=0; diff_check -iE "^\+.*(password|secret|api_key|apikey|private_key)[[:space:]]*=[[:space:]]*['\"][^'\"]{8,}['\"]" || check_rc=$?
if [ "$check_rc" -eq 0 ]; then
  echo -e "  ${RED}✗${NC} Mögliche hardkodierte Credentials gefunden"
  echo -e "     Bitte prüfen und ggf. durch Environment-Variablen ersetzen"
  FAILED=1
elif [ "$check_rc" -eq 1 ]; then
  echo -e "  ${GREEN}✓${NC} Keine offensichtlichen Credentials"
else
  check_not_runnable "Credentials"
fi

# ─── Check 5: Linting ────────────────────────────────────────────────────────
# Kommando aus factory.config.yml (commands.lint) bzw. FACTORY_LINT_COMMAND – kein
# stiller Default: fehlt beides, blockiert das Gate und nennt den Schlüssel.
if LINT_COMMAND="$(gate_command lint required)"; then
  echo -e "  ${YELLOW}→${NC} Lint: $LINT_COMMAND"
  if eval "$LINT_COMMAND" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Lint bestanden"
  else
    echo -e "  ${RED}✗${NC} Lint fehlgeschlagen – commit blockiert"
    echo -e "     Ausführen für Details: $LINT_COMMAND"
    FAILED=1
  fi
else
  echo -e "  ${RED}✗${NC} Lint: Kommando nicht konfiguriert – commit blockiert (commands.lint)"
  FAILED=1
fi

# ─── Check 5a: Übernommene Factory-Dateien unverändert ───────────────────────
# Lokale Stufe des Integritäts-Gates (offline, Factory-ADR-063 E8): Hashes aus factory.lock + zusammengesetzte
# Dateien == Fragmente. Im Factory-Repo (kein factory.lock) ein No-op; die CI-Stufe prüft zusätzlich das Manifest.
INTEGRITY_CHECK="$FACTORY_DIR/scripts/checks/factory-integrity-check.sh"
if [ -f "$INTEGRITY_CHECK" ]; then
  if INTEGRITY_OUTPUT="$(FACTORY_DIR="$FACTORY_DIR" bash "$INTEGRITY_CHECK" 2>&1)"; then
    echo -e "  ${GREEN}✓${NC} Factory-Integrität (übernommene Dateien)"
  else
    echo -e "  ${RED}✗${NC} Übernommene Factory-Dateien geändert – commit blockiert"
    echo "$INTEGRITY_OUTPUT" | sed 's/^/     /'
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Integritäts-Check fehlt ($INTEGRITY_CHECK) – übersprungen"
fi

# ─── Check 6: Projekt-Erweiterungspunkt ──────────────────────────────────────
# Ausführbare Skripte aus scripts/project/checks/pre-commit.d/ (lexikalisch). Fehlendes
# oder leeres Verzeichnis ist kein Fehler; Fehlschlag oder fehlendes Ausführbar-Bit blockiert.
run_project_checks "$FACTORY_DIR/scripts/project/checks/pre-commit.d" || FAILED=1

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 1 ]; then
  echo -e "${RED}Pre-Commit fehlgeschlagen. Commit blockiert.${NC}"
  exit 1
else
  echo -e "${GREEN}Pre-Commit bestanden.${NC}"
  exit 0
fi
