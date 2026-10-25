#!/usr/bin/env bash
# pre-push.sh – Quality Gate vor jedem Push
#
# Wird ausgeführt: git push (über .git/hooks/pre-push)
# Blockiert den Push wenn Tests fehlschlagen.
#
# Gate-Kommandos: factory.config.yml → commands.* (Env FACTORY_*_COMMAND hat Vorrang).
# Projekteigene Checks: ausführbare Skripte in scripts/project/checks/pre-push.d/.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=../lib/gate-config.sh
source "$FACTORY_DIR/scripts/lib/gate-config.sh"

echo ""
echo -e "${YELLOW}Pre-Push Checks...${NC}"

FAILED=0

# ─── Check 1: Test-Suite ausführen ───────────────────────────────────────────
# Kommando aus commands.test bzw. FACTORY_TEST_COMMAND – kein stiller Default.
if TEST_COMMAND="$(gate_command test required)"; then
  echo -e "  ${YELLOW}→${NC} Tests: $TEST_COMMAND"
  if eval "$TEST_COMMAND"; then
    echo -e "  ${GREEN}✓${NC} Alle Tests grün"
  else
    echo -e "  ${RED}✗${NC} Tests fehlgeschlagen – push blockiert"
    echo ""
    echo -e "  Ausführen für Details: $TEST_COMMAND"
    FAILED=1
  fi
else
  echo -e "  ${RED}✗${NC} Tests: Kommando nicht konfiguriert – push blockiert (commands.test)"
  FAILED=1
fi

# ─── Check 2: Typecheck ───────────────────────────────────────────────────────
# Fängt Typfehler (z.B. fehlende `import type`), die Lint und Vitest nicht
# erkennen: Vitest transpiliert über esbuild (Typen werden vor der Ausführung
# gestrippt, kein Type-Check) und das ESLint-Setup hier ist nicht typed-aware.
# Nur `tsc`/`next build` sieht diese Fehler – aus nothra/tch-gastro-services#137 (Build-Break unbemerkt
# bis zum manuellen `pnpm build` vor dem Merge).
if TYPECHECK_COMMAND="$(gate_command typecheck required)"; then
  echo -e "  ${YELLOW}→${NC} Typecheck: $TYPECHECK_COMMAND"
  if eval "$TYPECHECK_COMMAND" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Typecheck bestanden"
  else
    echo -e "  ${RED}✗${NC} Typecheck fehlgeschlagen – push blockiert"
    echo -e "     Ausführen für Details: $TYPECHECK_COMMAND"
    FAILED=1
  fi
else
  echo -e "  ${RED}✗${NC} Typecheck: Kommando nicht konfiguriert – push blockiert (commands.typecheck)"
  FAILED=1
fi

# ─── Check 3: Format (Prettier) ──────────────────────────────────────────────
# Erzwingt Prettier-Konformität vor dem Push. Ohne dieses Gate drifteten unbemerkt
# 38 Dateien aus dem Format (nothra/tch-gastro-services#149) – weder pre-commit noch CI prüften `format:check`.
# Ausgabe NICHT unterdrücken: `prettier --check` listet bei Drift die betroffenen
# Dateien ([warn] …) – direkt umsetzbar mit `pnpm format` (anders als der verbose tsc).
# Optionales Kommando (commands.format bzw. FACTORY_FORMAT_COMMAND): ein BEWUSST leer gesetztes
# FACTORY_FORMAT_COMMAND="" – oder ein leerer commands.format – deaktiviert das Gate (expliziter
# Opt-out, unten der else-Zweig); ein leerer Env-Wert fällt nicht still auf die Config zurück.
FORMAT_COMMAND="$(gate_command format optional)" || FAILED=1
if [ -n "$FORMAT_COMMAND" ]; then
  echo -e "  ${YELLOW}→${NC} Format: $FORMAT_COMMAND"
  if eval "$FORMAT_COMMAND"; then
    echo -e "  ${GREEN}✓${NC} Format bestanden"
  else
    echo -e "  ${RED}✗${NC} Format-Drift – push blockiert"
    echo -e "     Beheben mit dem Format-Kommando des Projekts (commands.format)"
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Format: deaktiviert (commands.format / FACTORY_FORMAT_COMMAND leer)"
fi

# ─── Check 4: Projekt-Erweiterungspunkt ──────────────────────────────────────
# Ausführbare Skripte aus scripts/project/checks/pre-push.d/ (lexikalisch), u. a. der
# Routen-Doku-Drift-Check (nothra/tch-gastro-services#145). Fehlendes oder leeres Verzeichnis ist kein Fehler;
# Fehlschlag oder fehlendes Ausführbar-Bit blockiert den Push (Skriptname in der Meldung).
run_project_checks "$FACTORY_DIR/scripts/project/checks/pre-push.d" || FAILED=1

# ─── Check 5: Git-Hooks installiert ──────────────────────────────────────────
# Fail-closed-Verifikation, dass pre-commit/pre-push/commit-msg im gemeinsamen
# Git-Verzeichnis vorhanden und ausführbar sind – ein vergessener Retrofit von
# install-hooks.sh (frischer Clone, gelöschtes .git/hooks) bliebe sonst unbemerkt
# (Issue nothra/tch-gastro-services#265, ADR-042 §Consequences).
HOOKS_INSTALLED_CHECK="$FACTORY_DIR/scripts/checks/hooks-installed-check.sh"
if [ -f "$HOOKS_INSTALLED_CHECK" ]; then
  echo -e "  ${YELLOW}→${NC} Git-Hooks: pre-commit/pre-push/commit-msg installiert?"
  if HOOKS_INSTALLED_OUTPUT="$(FACTORY_DIR="$FACTORY_DIR" bash "$HOOKS_INSTALLED_CHECK" 2>&1)"; then
    echo -e "  ${GREEN}✓${NC} Git-Hooks installiert und ausführbar"
  else
    echo -e "  ${RED}✗${NC} Git-Hooks fehlen oder sind nicht ausführbar – push blockiert"
    echo "$HOOKS_INSTALLED_OUTPUT" | sed 's/^/     /'
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Git-Hooks-Check fehlt ($HOOKS_INSTALLED_CHECK) – übersprungen"
fi

# ─── Check 6: Deckel für den @import-Dauerkontext ────────────────────────────
# CLAUDE.md + rekursiv alle @-eingebundenen Dateien werden bei jeder Session und jedem
# Pipeline-Schritt vollständig geladen. ADR-037 wollte diesen Kontext per Prosa-Konvention
# schlank halten – der Lessons-Index lief trotzdem von ~80 auf 341 Zeilen. Deshalb ein Gate
# statt einer zweiten Konvention (ADR-047 §4). Fail-closed auch bei nicht lesbarer Referenz.
IMPORT_CONTEXT_CHECK="$FACTORY_DIR/scripts/checks/import-context-limit-check.sh"
if [ -f "$IMPORT_CONTEXT_CHECK" ]; then
  echo -e "  ${YELLOW}→${NC} @import-Kontext: CLAUDE.md + Imports unter der Grenze?"
  if IMPORT_CONTEXT_OUTPUT="$(FACTORY_DIR="$FACTORY_DIR" bash "$IMPORT_CONTEXT_CHECK" 2>&1)"; then
    # Ausgabe des Checks verbatim (enthält bereits ✓ + Ist/Grenze) – die Zahl zeigt,
    # wie viel Luft bis zum Deckel bleibt, bevor er blockiert.
    echo "$IMPORT_CONTEXT_OUTPUT" | sed 's/^/  /'
  else
    echo -e "  ${RED}✗${NC} @import-Kontext-Deckel rot – push blockiert"
    echo "$IMPORT_CONTEXT_OUTPUT" | sed 's/^/     /'
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  @import-Kontext-Deckel fehlt ($IMPORT_CONTEXT_CHECK) – übersprungen"
fi

# ─── Check 6a: Zuordnung Factory/Projekt vollständig ──────────────────────────
# Jede getrackte Datei gehört genau einer Seite (docs/factory/OWNERSHIP.md, ADR-063 D11).
# Eine neue Datei ohne Zeile in der Tabelle blockiert den Push – dasselbe prüft CI über die
# Self-Test-Suite (factory-self-test), damit ein umgangener Hook nicht reicht (nothra/tch-gastro-services#426).
OWNERSHIP_CHECK="$FACTORY_DIR/scripts/checks/ownership-check.sh"
if [ -f "$OWNERSHIP_CHECK" ]; then
  echo -e "  ${YELLOW}→${NC} Zuordnung: jede getrackte Datei genau einer Seite (factory|project)?"
  if OWNERSHIP_OUTPUT="$(FACTORY_DIR="$FACTORY_DIR" bash "$OWNERSHIP_CHECK" 2>&1)"; then
    echo "$OWNERSHIP_OUTPUT" | sed 's/^/  /'
  else
    echo -e "  ${RED}✗${NC} Zuordnungstabelle unvollständig oder mehrdeutig – push blockiert"
    echo "$OWNERSHIP_OUTPUT" | sed 's/^/     /'
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Zuordnungs-Check fehlt ($OWNERSHIP_CHECK) – übersprungen"
fi

# ─── Check 6b: Übernommene Factory-Dateien unverändert ───────────────────────
# Lokale Stufe des Integritäts-Gates (offline, Factory-ADR-063 E8): Hashes aus factory.lock + zusammengesetzte
# Dateien == Fragmente. Im Factory-Repo (kein factory.lock) ein No-op; die CI-Stufe prüft zusätzlich das Manifest.
INTEGRITY_CHECK="$FACTORY_DIR/scripts/checks/factory-integrity-check.sh"
if [ -f "$INTEGRITY_CHECK" ]; then
  if INTEGRITY_OUTPUT="$(FACTORY_DIR="$FACTORY_DIR" bash "$INTEGRITY_CHECK" 2>&1)"; then
    echo -e "  ${GREEN}✓${NC} Factory-Integrität (übernommene Dateien)"
  else
    echo -e "  ${RED}✗${NC} Übernommene Factory-Dateien geändert – push blockiert"
    echo "$INTEGRITY_OUTPUT" | sed 's/^/     /'
    FAILED=1
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Integritäts-Check fehlt ($INTEGRITY_CHECK) – übersprungen"
fi

# ─── Check 7: Nicht auf main/master pushen ohne PR ───────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo -e "  ${RED}✗${NC} Direkter Push auf $CURRENT_BRANCH nicht erlaubt"
  echo -e "     Bitte einen Pull Request erstellen (gh pr create)"
  FAILED=1
else
  echo -e "  ${GREEN}✓${NC} Branch: $CURRENT_BRANCH (nicht main/master)"
fi

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 1 ]; then
  echo -e "${RED}Pre-Push fehlgeschlagen. Push blockiert.${NC}"
  exit 1
else
  echo -e "${GREEN}Pre-Push bestanden.${NC}"
  exit 0
fi
