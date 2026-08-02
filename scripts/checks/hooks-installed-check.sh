#!/usr/bin/env bash
# hooks-installed-check.sh – prüft, dass die drei Factory-Git-Hooks installiert sind
# (pre-commit, pre-push, commit-msg).
#
# Fail-closed: fehlt einer der Hooks im gemeinsamen Git-Verzeichnis ODER ist er nicht
# ausführbar, schlägt der Check fehl (Exit 1) und nennt den/die betroffenen Hook-Namen
# sowie den Remediation-Befehl `bash scripts/install-hooks.sh`. Reine Existenzprüfung
# reicht nicht – nicht ausführbare Hooks laufen bei Git ins Leere (Issue #265,
# ADR-042 §Consequences).
#
# Kein Inhaltsvergleich gegen install-hooks.sh (bewusst, siehe spec-265 „Nicht
# inbegriffen") – nur Präsenz + Ausführbarkeit.
#
# Verwendet das GEMEINSAME Git-Verzeichnis (`git rev-parse --git-common-dir`), damit der
# Check aus jedem Worktree dieses Repos dasselbe Ergebnis liefert wie install-hooks.sh
# (ADR-042) – nicht ein worktree-lokales `.git`.
#
# Projektwurzel: FACTORY_DIR (Tests/Override) sonst zwei Ebenen über scripts/checks/.

set -uo pipefail

ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

cd "$ROOT" || {
  echo -e "${RED}✗${NC} Projektwurzel nicht erreichbar: $ROOT"
  exit 1
}

if ! GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  echo -e "${RED}✗${NC} hooks-installed-check: '$ROOT' ist kein git-Repository – Hooks können nicht geprüft werden (fail-closed)."
  exit 1
fi

# `--git-common-dir` liefert je nach Aufrufort einen relativen Pfad (typisch ".git") –
# relativ zur Projektwurzel (analog zu install-hooks.sh).
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$ROOT/$GIT_COMMON_DIR" ;;
esac

HOOKS_DIR="$GIT_COMMON_DIR/hooks"

# Einzige Quelle für die drei Factory-Hook-Namen (Loop + Erfolgsmeldung teilen sich die
# Liste) – ein künftig vierter Hook müsste sonst an zwei Stellen synchron gepflegt werden.
FACTORY_HOOKS="pre-commit pre-push commit-msg"

MISSING=""
for hook in $FACTORY_HOOKS; do
  hook_file="$HOOKS_DIR/$hook"
  if [ ! -f "$hook_file" ] || [ ! -x "$hook_file" ]; then
    MISSING="$MISSING $hook"
  fi
done

if [ -n "$MISSING" ]; then
  echo -e "${RED}✗${NC} Fehlende oder nicht ausführbare Git-Hooks:$MISSING"
  echo "     Beheben mit: bash scripts/install-hooks.sh"
  exit 1
fi

echo -e "${GREEN}✓${NC} Alle Factory-Git-Hooks ($FACTORY_HOOKS) installiert und ausführbar"
exit 0
