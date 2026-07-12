#!/usr/bin/env bash
# start-work.sh – Neue Task starten: main pullen, Branch anlegen, pushen, Draft-PR erstellen
#
# Verwendung: bash scripts/start-work.sh <task-id> <kurzbeschreibung> [branch-typ]
# Beispiel:   bash scripts/start-work.sh 42 user-login-implementieren
#             bash scripts/start-work.sh 43 npm-deps-aktualisieren chore
#
# branch-typ (optional, Standard: feature): bestimmt Branch-Präfix und
# leitet den Conventional-Commits-Typ des PR-Titels ab.
#
# Ablauf (deterministisch):
#   1. Issue sicherstellen (Issue-first) + Default-Branch aktualisieren (fetch)
#   2. Eigenen git-Worktree für den Feature-Branch anlegen (Isolation, Default)
#   3. Task-Datei erstellen
#   4. Branch pushen
#   5. Draft Pull Request erstellen (gh)
#
# WORKTREE-DEFAULT (Kern-Vorkehrung gegen Session-Kollisionen): Jede neue Task
# bekommt einen EIGENEN Arbeitsbaum (git worktree) statt eines checkout im
# geteilten Haupt-Baum. So verschieben parallele Sessions nie gegenseitig HEAD
# (Ursache des Kollisionsvorfalls aus #71). Env-Schalter:
#   FACTORY_NO_WORKTREE=1     altes In-Place-Verhalten (Branch im aktuellen Baum)
#   FACTORY_WORKTREE_BASE=…   Basisverzeichnis der Worktrees (Default: Geschwister-Ordner)
#   FACTORY_WT_SKIP_INSTALL=1 kein 'pnpm install' im neuen Worktree
#   FACTORY_DIR=…             Repo-Wurzel überschreiben (v. a. für Tests)
#   FACTORY_ISSUE_LABEL=…     Art-Label für ein neu angelegtes Issue erzwingen
#                             (Default aus dem Branch-Typ abgeleitet)

set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Argumente & Modus ───────────────────────────────────────────────────────
# Zwei Modi (ADR-013 – Task-ID = GitHub-Issue-Nummer):
#   Beschreibungs-Modus: start-work.sh <kurzbeschreibung> [branch-typ]
#                        legt ein Issue an; dessen Nummer wird die Task-ID (Issue-first).
#   ID-Modus           : start-work.sh <issue-id> <kurzbeschreibung> [branch-typ]
#                        erstes Argument numerisch → bestehendes Issue #<id> (wird validiert).

usage() {
  echo -e "${RED}Fehler:${NC} $1"
  echo "Verwendung:"
  echo "  bash scripts/start-work.sh <kurzbeschreibung> [branch-typ]             # Issue-first (empfohlen)"
  echo "  bash scripts/start-work.sh <issue-id> <kurzbeschreibung> [branch-typ]  # bestehendes Issue"
  echo "branch-typ: feature (Standard), fix, improvement, hotfix, chore, docs, test, refactor"
  exit 1
}

[[ $# -ge 1 ]] || usage "Beschreibung (oder Issue-ID + Beschreibung) erforderlich"

if [[ "$1" =~ ^[0-9]+$ ]]; then
  ISSUE_MODE="existing"
  [[ $# -ge 2 ]] || usage "Im ID-Modus ist eine Beschreibung erforderlich"
  TASK_ID="$1"
  RAW_DESC="$2"
  BRANCH_TYPE="${3:-feature}"
else
  ISSUE_MODE="create"
  RAW_DESC="$1"
  BRANCH_TYPE="${2:-feature}"
  TASK_ID=""   # wird aus der Issue-Nummer abgeleitet
fi

TASK_DESC=$(echo "$RAW_DESC" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

# Branch-Typ gegen die erlaubten Präfixe prüfen (analog branch-name-check.sh)
case "$BRANCH_TYPE" in
  feature|fix|improvement|hotfix|chore|docs|test|refactor) ;;
  *)
    echo -e "${RED}Fehler:${NC} Ungültiger Branch-Typ: ${BRANCH_TYPE}"
    echo "  Erlaubt: feature, fix, improvement, hotfix, chore, docs, test, refactor"
    exit 1
    ;;
esac

# Conventional-Commits-Typ für den PR-Titel aus dem Branch-Typ ableiten
case "$BRANCH_TYPE" in
  feature)     COMMIT_TYPE="feat" ;;
  hotfix)      COMMIT_TYPE="fix" ;;
  improvement) COMMIT_TYPE="refactor" ;;
  *)           COMMIT_TYPE="$BRANCH_TYPE" ;;
esac

# GitHub-Art-Label aus dem Branch-Typ ableiten (Schema „genau ein Art-Label",
# git-workflow.md): fix/hotfix → bug, docs → documentation, sonst enhancement.
# Override via FACTORY_ISSUE_LABEL, falls die Ableitung nicht passt.
case "$BRANCH_TYPE" in
  fix|hotfix) ISSUE_LABEL="bug" ;;
  docs)       ISSUE_LABEL="documentation" ;;
  *)          ISSUE_LABEL="enhancement" ;;
esac
ISSUE_LABEL="${FACTORY_ISSUE_LABEL:-$ISSUE_LABEL}"

# Worktree-Default (Kern-Vorkehrung, #74). Ausschalten via FACTORY_NO_WORKTREE=1.
if [ "${FACTORY_NO_WORKTREE:-0}" = "1" ]; then WORKTREE_MODE=false; else WORKTREE_MODE=true; fi

# ─── Uncommitted Changes prüfen (nur In-Place-Modus) ──────────────────────────
# Der Worktree-Modus fasst den aktuellen Baum nicht an (kein checkout/rebase dort)
# und darf daher gerade dann starten, wenn der Haupt-Baum belegt/schmutzig ist –
# das ist der eigentliche Sinn der Isolation.
if [ "$WORKTREE_MODE" = false ] \
   && { ! git -C "$FACTORY_DIR" diff --quiet || ! git -C "$FACTORY_DIR" diff --cached --quiet; }; then
  echo -e "  ${RED}✗ Uncommitted Changes vorhanden – bitte erst committen oder stashen${NC}"
  git -C "$FACTORY_DIR" status --short
  exit 1
fi

# ─── Issue-Pendant sicherstellen (Task-ID = Issue-Nummer, ADR-013) ────────────
# Repo-Slug für gh (Env bevorzugt, sonst aus der Remote).
REPO="${FACTORY_REPO:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
  _url=$(git remote get-url origin 2>/dev/null || echo "")
  REPO=$(printf '%s' "$_url" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
fi

if [ "$ISSUE_MODE" = "create" ]; then
  command -v gh >/dev/null 2>&1 || { echo -e "${RED}Fehler:${NC} gh nötig, um im Beschreibungs-Modus ein Issue anzulegen."; echo "  Alternativ: Issue selbst anlegen und die Nummer als <issue-id> übergeben."; exit 1; }
  echo -e "${YELLOW}0/5  Lege GitHub-Issue an (Issue-first)...${NC}"
  ISSUE_BODY="Angelegt via start-work.sh. Task-ID = Issue-Nummer (ADR-013)."
  # Mit Art-Label anlegen. Fällt das fehl (Label existiert im Repo nicht),
  # ohne Label erneut versuchen – die Issue-Anlage selbst darf nicht scheitern.
  _url=$(gh issue create --repo "$REPO" --title "$RAW_DESC" --label "$ISSUE_LABEL" --body "$ISSUE_BODY" 2>/dev/null) || true
  if [ -z "$_url" ]; then
    _url=$(gh issue create --repo "$REPO" --title "$RAW_DESC" --body "$ISSUE_BODY" 2>/dev/null) || true
    [ -n "$_url" ] && echo -e "  ${YELLOW}⚠${NC}  Label '${ISSUE_LABEL}' nicht gesetzt (im Repo nicht vorhanden?) – Issue bitte manuell klassifizieren"
    ISSUE_LABEL=""
  fi
  TASK_ID=$(printf '%s' "$_url" | grep -oE '[0-9]+$')
  [ -n "$TASK_ID" ] || { echo -e "  ${RED}✗ Issue-Anlage fehlgeschlagen${NC}"; exit 1; }
  echo -e "  ${GREEN}✓${NC} Issue #${TASK_ID} angelegt → Task-ID ${TASK_ID}${ISSUE_LABEL:+ (Label: ${ISSUE_LABEL})}"
else
  # ID-Modus: das Issue MUSS existieren, sonst bricht die Invariante.
  if command -v gh >/dev/null 2>&1 && [ -n "$REPO" ]; then
    if ! gh issue view "$TASK_ID" --repo "$REPO" --json number >/dev/null 2>&1; then
      echo -e "${RED}Fehler:${NC} Issue #${TASK_ID} existiert nicht in ${REPO}."
      echo "  Lege es zuerst an, oder nutze den Beschreibungs-Modus (legt das Issue automatisch an):"
      echo "  bash scripts/start-work.sh \"<beschreibung>\""
      exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Issue #${TASK_ID} existiert"
  else
    echo -e "  ${YELLOW}⚠${NC}  gh nicht verfügbar – Issue-Existenz für #${TASK_ID} nicht geprüft"
  fi
fi

BRANCH_NAME="${BRANCH_TYPE}/${TASK_ID}-${TASK_DESC}"

echo ""
echo -e "${CYAN}── Task ${TASK_ID}: ${TASK_DESC} ──────────────────────────────────${NC}"

# ─── Default-Branch ermitteln ────────────────────────────────────────────────

DEFAULT_BRANCH=$(git -C "$FACTORY_DIR" remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="main"

# WORKDIR = das Verzeichnis, in dem gebaut wird. Worktree-Modus: ein isolierter
# neuer Baum. In-Place-Modus: der Haupt-Baum selbst.
if [ "$WORKTREE_MODE" = true ]; then
  # ── Worktree-Modus (Default): KEIN checkout im geteilten Haupt-Baum ─────────
  echo ""
  echo -e "${YELLOW}1/5  Aktualisiere ${DEFAULT_BRANCH} (fetch, best-effort)...${NC}"
  git -C "$FACTORY_DIR" fetch --quiet origin 2>/dev/null || true

  # Basis-Ref: origin/<default> (aktuellster Stand), sonst lokaler <default>, sonst HEAD.
  if git -C "$FACTORY_DIR" rev-parse --verify --quiet "origin/${DEFAULT_BRANCH}" >/dev/null; then
    BASE_REF="origin/${DEFAULT_BRANCH}"
  elif git -C "$FACTORY_DIR" rev-parse --verify --quiet "${DEFAULT_BRANCH}" >/dev/null; then
    BASE_REF="${DEFAULT_BRANCH}"
  else
    BASE_REF="HEAD"
  fi
  echo -e "  ${GREEN}✓${NC} Basis: ${BASE_REF}"

  # Worktree-Pfad: Geschwister-Ordner (konfigurierbar); Branch-Slashes → '-'.
  WT_BASE="${FACTORY_WORKTREE_BASE:-$(dirname "$FACTORY_DIR")/$(basename "$FACTORY_DIR").worktrees}"
  WORKDIR="$WT_BASE/${BRANCH_NAME//\//-}"
  mkdir -p "$WT_BASE"

  echo ""
  echo -e "${YELLOW}2/5  Lege Worktree an: ${WORKDIR}${NC}"
  if git -C "$FACTORY_DIR" worktree list --porcelain | grep -qxF "worktree $WORKDIR"; then
    echo -e "  ${YELLOW}⚠  Worktree existiert bereits – wird wiederverwendet${NC}"
  elif [ -e "$WORKDIR" ]; then
    echo -e "  ${YELLOW}⚠  Pfad existiert bereits (kein Worktree) – wird wiederverwendet${NC}"
  elif git -C "$FACTORY_DIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git -C "$FACTORY_DIR" worktree add "$WORKDIR" "$BRANCH_NAME"
    echo -e "  ${GREEN}✓${NC} Worktree für bestehenden Branch angelegt"
  else
    git -C "$FACTORY_DIR" worktree add -b "$BRANCH_NAME" "$WORKDIR" "$BASE_REF"
    echo -e "  ${GREEN}✓${NC} Worktree + Branch angelegt"
  fi

  # Abhängigkeiten im Worktree bereitstellen, damit die Gates (lint/test) dort laufen.
  if [ "${FACTORY_WT_SKIP_INSTALL:-0}" != "1" ] && [ -f "$WORKDIR/package.json" ] && command -v pnpm >/dev/null 2>&1; then
    echo -e "  ${YELLOW}→${NC} pnpm install im Worktree (FACTORY_WT_SKIP_INSTALL=1 überspringt)..."
    if (cd "$WORKDIR" && pnpm install --frozen-lockfile >/dev/null 2>&1); then
      echo -e "  ${GREEN}✓${NC} Abhängigkeiten installiert"
    else
      echo -e "  ${YELLOW}⚠  pnpm install fehlgeschlagen – im Worktree manuell nachziehen${NC}"
    fi
  fi
else
  # ── In-Place-Modus (FACTORY_NO_WORKTREE=1): bisheriges Verhalten ────────────
  WORKDIR="$FACTORY_DIR"
  CURRENT_BRANCH=$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD)

  echo ""
  echo -e "${YELLOW}1/5  Aktualisiere ${DEFAULT_BRANCH}...${NC}"
  if [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
    git -C "$WORKDIR" checkout "$DEFAULT_BRANCH"
  fi
  git -C "$WORKDIR" pull --rebase origin "$DEFAULT_BRANCH"
  echo -e "  ${GREEN}✓${NC} ${DEFAULT_BRANCH} ist aktuell"

  echo ""
  echo -e "${YELLOW}2/5  Lege Branch an: ${BRANCH_NAME}${NC}"
  if git -C "$WORKDIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo -e "  ${YELLOW}⚠  Branch existiert bereits – wechsle zu ihm${NC}"
    git -C "$WORKDIR" checkout "$BRANCH_NAME"
  else
    git -C "$WORKDIR" checkout -b "$BRANCH_NAME"
    echo -e "  ${GREEN}✓${NC} Branch erstellt"
  fi
fi

TASK_FILE="$WORKDIR/tasks/task-${TASK_ID}-${TASK_DESC}.md"

# ─── Task-Datei erstellen ────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}3/5  Task-Datei anlegen...${NC}"

if [[ -f "$TASK_FILE" ]]; then
  echo -e "  ${YELLOW}⚠  Task-Datei existiert bereits${NC}"
else
  mkdir -p "$WORKDIR/tasks"
  cat > "$TASK_FILE" << EOF
# Task ${TASK_ID}: ${TASK_DESC}

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

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
# (leerer Draft-PR) und die Datei bliebe uncommitted im Working Tree.
git -C "$WORKDIR" add "$TASK_FILE"
if ! git -C "$WORKDIR" diff --cached --quiet; then
  git -C "$WORKDIR" commit -q -m "chore: Task ${TASK_ID} anlegen (${TASK_DESC//-/ })"
  echo -e "  ${GREEN}✓${NC} Task-Datei committet"
fi

# ─── Branch pushen ───────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}4/5  Pushe Branch nach origin...${NC}"

PUSH_OK=0
if git -C "$WORKDIR" push -u origin "$BRANCH_NAME" 2>&1; then
  echo -e "  ${GREEN}✓${NC} Branch gepusht"
  PUSH_OK=1
else
  echo -e "  ${RED}✗ Push fehlgeschlagen – PR-Erstellung wird übersprungen${NC}"
  echo -e "    Manuell pushen: git push -u origin ${BRANCH_NAME}"
fi

# ─── Draft Pull Request erstellen ─────────────────────────────────────────────

echo ""
echo -e "${YELLOW}5/5  Erstelle Draft Pull Request...${NC}"

PR_TITLE="${COMMIT_TYPE}: ${TASK_DESC//-/ } (#${TASK_ID})"
# "Closes #<id>" schließt das Issue beim Merge automatisch. Eine bloße Referenz
# wie "(#<id>)" ist nur eine Erwähnung und lässt das Issue offen (siehe #74/#71/#76).
PR_DESC="Closes #${TASK_ID}

Task #${TASK_ID}: ${TASK_DESC//-/ }"

PR_CREATED=0

# gh erkennt das Repo über das cwd → im WORKDIR ausführen (Worktree-sicher).
if [[ $PUSH_OK -eq 1 ]] && command -v gh &>/dev/null; then
  if (cd "$WORKDIR" && gh pr create \
      --draft \
      --title "$PR_TITLE" \
      --body "$PR_DESC" \
      --base "$DEFAULT_BRANCH" 2>/dev/null); then
    echo -e "  ${GREEN}✓${NC} Draft-PR erstellt (GitHub)"
    PR_CREATED=1
  fi
fi

if [[ $PR_CREATED -eq 0 ]]; then
  echo -e "  ${YELLOW}⚠  PR manuell anlegen:${NC}"
  echo -e "     gh pr create --draft --title \"${PR_TITLE}\" --body \"${PR_DESC}\" --base ${DEFAULT_BRANCH}"
fi

# ─── Abschluss ───────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Bereit!${NC}"
echo "  Branch:     ${BRANCH_NAME}"
echo "  Arbeitsbaum: ${WORKDIR}"
echo "  Task-Datei: tasks/task-${TASK_ID}-${TASK_DESC}.md"
echo ""
echo -e "${CYAN}Nächste Schritte:${NC}"
if [ "$WORKTREE_MODE" = true ]; then
  echo "  0. In den isolierten Worktree wechseln:"
  echo "       cd \"${WORKDIR}\""
  echo "     (Aufräumen nach dem Merge: git worktree remove \"${WORKDIR}\")"
fi
echo "  1. Task-Datei mit Beschreibung und Akzeptanzkriterien befüllen"
echo "     (oder: /requirements ${TASK_ID} in Claude Code)"
echo "  2. Implementieren starten: /implement ${TASK_ID} in Claude Code"
echo ""
echo -e "${YELLOW}⚡ Tipp: Starte für Task ${TASK_ID} eine neue Claude-Session in diesem Worktree.${NC}"
echo "   Eigener Arbeitsbaum = parallele Sessions kollidieren nicht (kein geteilter HEAD)."
echo ""
