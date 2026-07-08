#!/usr/bin/env bash
# start-work.sh – Neue Task starten: main pullen, Branch anlegen, pushen, Draft-MR erstellen
#
# Verwendung: bash scripts/start-work.sh <task-id> <kurzbeschreibung> [branch-typ]
# Beispiel:   bash scripts/start-work.sh 42 user-login-implementieren
#             bash scripts/start-work.sh 43 npm-deps-aktualisieren chore
#
# branch-typ (optional, Standard: feature): bestimmt Branch-Präfix und
# leitet den Conventional-Commits-Typ des MR-Titels ab.
#
# Ablauf (deterministisch):
#   1. Uncommitted Changes prüfen
#   2. main/master pullen (--rebase)
#   3. Feature-Branch anlegen
#   4. Task-Datei erstellen
#   5. Branch pushen
#   6. Draft Merge Request erstellen (glab, Fallback: gh)

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Argumente prüfen ────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo -e "${RED}Fehler:${NC} Task-ID und Beschreibung erforderlich"
  echo "Verwendung: bash scripts/start-work.sh <task-id> <kurzbeschreibung> [branch-typ]"
  echo "Beispiel:   bash scripts/start-work.sh 42 user-login-implementieren"
  echo "branch-typ: feature (Standard), fix, improvement, hotfix, chore, docs, test, refactor"
  exit 1
fi

TASK_ID="$1"
TASK_DESC=$(echo "$2" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
BRANCH_TYPE="${3:-feature}"

# Branch-Typ gegen die erlaubten Präfixe prüfen (analog branch-name-check.sh)
case "$BRANCH_TYPE" in
  feature|fix|improvement|hotfix|chore|docs|test|refactor) ;;
  *)
    echo -e "${RED}Fehler:${NC} Ungültiger Branch-Typ: ${BRANCH_TYPE}"
    echo "  Erlaubt: feature, fix, improvement, hotfix, chore, docs, test, refactor"
    exit 1
    ;;
esac

# Conventional-Commits-Typ für den MR-Titel aus dem Branch-Typ ableiten
case "$BRANCH_TYPE" in
  feature)     COMMIT_TYPE="feat" ;;
  hotfix)      COMMIT_TYPE="fix" ;;
  improvement) COMMIT_TYPE="refactor" ;;
  *)           COMMIT_TYPE="$BRANCH_TYPE" ;;
esac

BRANCH_NAME="${BRANCH_TYPE}/${TASK_ID}-${TASK_DESC}"
TASK_FILE="$FACTORY_DIR/tasks/task-${TASK_ID}-${TASK_DESC}.md"

echo ""
echo -e "${CYAN}── Task ${TASK_ID}: ${TASK_DESC} ──────────────────────────────────${NC}"

# ─── Uncommitted Changes prüfen ──────────────────────────────────────────────

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo -e "  ${RED}✗ Uncommitted Changes vorhanden – bitte erst committen oder stashen${NC}"
  git status --short
  exit 1
fi

# ─── Default-Branch ermitteln ────────────────────────────────────────────────

DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# ─── main/master pullen ──────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}1/5  Aktualisiere ${DEFAULT_BRANCH}...${NC}"

if [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
  git checkout "$DEFAULT_BRANCH"
fi

git pull --rebase origin "$DEFAULT_BRANCH"
echo -e "  ${GREEN}✓${NC} ${DEFAULT_BRANCH} ist aktuell"

# ─── Feature-Branch anlegen ──────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}2/5  Lege Branch an: ${BRANCH_NAME}${NC}"

if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  echo -e "  ${YELLOW}⚠  Branch existiert bereits – wechsle zu ihm${NC}"
  git checkout "$BRANCH_NAME"
else
  git checkout -b "$BRANCH_NAME"
  echo -e "  ${GREEN}✓${NC} Branch erstellt"
fi

# ─── Task-Datei erstellen ────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}3/5  Task-Datei anlegen...${NC}"

if [[ -f "$TASK_FILE" ]]; then
  echo -e "  ${YELLOW}⚠  Task-Datei existiert bereits${NC}"
else
  mkdir -p "$FACTORY_DIR/tasks"
  cat > "$TASK_FILE" << EOF
# Task ${TASK_ID}: ${TASK_DESC}

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / MR erstellt

## Beschreibung
<!-- Was soll implementiert werden? -->

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] GIVEN ... WHEN ... THEN ...

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: \`${BRANCH_NAME}\`
Erstellt: $(date +"%Y-%m-%d %H:%M")
EOF
  echo -e "  ${GREEN}✓${NC} Task-Datei erstellt: tasks/task-${TASK_ID}-${TASK_DESC}.md"
fi

# Task-Datei committen – sonst ist der gepushte Branch identisch zu main
# (leerer Draft-MR) und die Datei bliebe uncommitted im Working Tree.
git add "$TASK_FILE"
if ! git diff --cached --quiet; then
  git commit -q -m "chore: Task ${TASK_ID} anlegen (${TASK_DESC//-/ })"
  echo -e "  ${GREEN}✓${NC} Task-Datei committet"
fi

# ─── Branch pushen ───────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}4/5  Pushe Branch nach origin...${NC}"

PUSH_OK=0
if git push -u origin "$BRANCH_NAME" 2>&1; then
  echo -e "  ${GREEN}✓${NC} Branch gepusht"
  PUSH_OK=1
else
  echo -e "  ${RED}✗ Push fehlgeschlagen – MR-Erstellung wird übersprungen${NC}"
  echo -e "    Manuell pushen: git push -u origin ${BRANCH_NAME}"
fi

# ─── Draft Merge Request erstellen ───────────────────────────────────────────

echo ""
echo -e "${YELLOW}5/5  Erstelle Draft Merge Request...${NC}"

MR_TITLE="${COMMIT_TYPE}: ${TASK_DESC//-/ } (#${TASK_ID})"
MR_DESC="Task #${TASK_ID}: ${TASK_DESC//-/ }"

MR_CREATED=0

if [[ $PUSH_OK -eq 1 ]]; then
  # GitLab (primär bei dm)
  if command -v glab &>/dev/null; then
    if glab mr create \
        --draft \
        --title "$MR_TITLE" \
        --description "$MR_DESC" \
        --target-branch "$DEFAULT_BRANCH" \
        --remove-source-branch \
        < /dev/null 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Draft-MR erstellt (GitLab)"
      MR_CREATED=1
    fi
  fi

  # GitHub (Fallback)
  if [[ $MR_CREATED -eq 0 ]] && command -v gh &>/dev/null; then
    if gh pr create \
        --draft \
        --title "$MR_TITLE" \
        --body "$MR_DESC" \
        --base "$DEFAULT_BRANCH" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Draft-PR erstellt (GitHub)"
      MR_CREATED=1
    fi
  fi
fi

if [[ $MR_CREATED -eq 0 ]]; then
  echo -e "  ${YELLOW}⚠  MR manuell anlegen:${NC}"
  echo -e "     GitLab: glab mr create --draft --title \"${MR_TITLE}\" --target-branch ${DEFAULT_BRANCH} --remove-source-branch"
  echo -e "     GitHub: gh pr create --draft --title \"${MR_TITLE}\" --base ${DEFAULT_BRANCH}"
fi

# ─── Abschluss ───────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Bereit!${NC}"
echo "  Branch:     ${BRANCH_NAME}"
echo "  Task-Datei: tasks/task-${TASK_ID}-${TASK_DESC}.md"
echo ""
echo -e "${CYAN}Nächste Schritte:${NC}"
echo "  1. Task-Datei mit Beschreibung und Akzeptanzkriterien befüllen"
echo "     (oder: /requirements ${TASK_ID} in Claude Code)"
echo "  2. Implementieren starten: /implement ${TASK_ID} in Claude Code"
echo ""
echo -e "${YELLOW}⚡ Tipp: Starte für Task ${TASK_ID} eine neue Claude-Session.${NC}"
echo "   Kleiner Kontext = fokussierte Arbeit + weniger Token-Verbrauch."
echo ""
