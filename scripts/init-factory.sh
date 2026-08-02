#!/usr/bin/env bash
# init-factory.sh – Factory-Bootstrap für ein neues Projekt
#
# Verwendung: bash scripts/init-factory.sh
# Ausführen EINMALIG zu Beginn eines neuen Projekts.

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_CONTEXT="$FACTORY_DIR/docs/factory/PROJECT-CONTEXT.md"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     dm Development Factory Setup      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# ─── 1. Basis-Informationen abfragen ────────────────────────────────────────

echo -e "${YELLOW}Schritt 1: Projekt-Informationen${NC}"
echo ""

read -p "Projektname (z.B. preisbestimmungsservice): " PROJECT_NAME
read -p "Kurze Beschreibung: " PROJECT_DESCRIPTION
read -p "Projekttyp (microservice/monolith/library/frontend): " PROJECT_TYPE
read -p "Team-Name: " TEAM_NAME

echo ""
echo -e "${YELLOW}Schritt 2: Repository${NC}"
read -p "Repository-URL (leer lassen falls noch nicht vorhanden): " REPOSITORY_URL
REPOSITORY_URL="${REPOSITORY_URL:-noch nicht festgelegt}"

# ─── 2. Tech-Stack abfragen ─────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Schritt 3: Tech-Stack${NC}"
echo "  Hinweis: Öffne danach Claude Code und führe /setup-project aus."
echo "  Claude erkennt den Stack automatisch und vervollständigt die Konfiguration."
echo ""

read -p "Primärsprache (java/typescript/python/go/other): " PRIMARY_LANGUAGE
read -p "Framework (z.B. Spring Boot, Next.js, Express, Django): " FRAMEWORK
read -p "Datenbank (z.B. PostgreSQL, MySQL, MongoDB, SQLite): " DATABASE

# ─── 3. PROJECT-CONTEXT.md befüllen ─────────────────────────────────────────

echo ""
echo -e "${YELLOW}Schritt 4: PROJECT-CONTEXT.md wird initialisiert...${NC}"

START_DATE=$(date +"%Y-%m-%d")

# Platzhalter ersetzen (macOS-kompatibel mit sed -i '')
sed -i '' \
  -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
  -e "s/{{PROJECT_DESCRIPTION}}/$PROJECT_DESCRIPTION/g" \
  -e "s/{{PROJECT_TYPE}}/$PROJECT_TYPE/g" \
  -e "s/{{TEAM_NAME}}/$TEAM_NAME/g" \
  -e "s/{{START_DATE}}/$START_DATE/g" \
  -e "s|{{REPOSITORY_URL}}|$REPOSITORY_URL|g" \
  -e "s/{{PRIMARY_LANGUAGE}}/$PRIMARY_LANGUAGE/g" \
  -e "s/{{FRAMEWORK}}/$FRAMEWORK/g" \
  -e "s/{{DATABASE}}/$DATABASE/g" \
  "$PROJECT_CONTEXT"

echo -e "  ${GREEN}✓${NC} PROJECT-CONTEXT.md initialisiert"

# ─── 4. Git Hooks installieren ───────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Schritt 5: Git Hooks installieren...${NC}"

# Kanonische Quelle für Inhalt und Umfang der Hooks ist scripts/install-hooks.sh
# (ADR-042) – hier bewusst nur der Aufruf, damit Neuprojekt-Bootstrap und Retrofit
# bestehender Repos nicht auseinanderdriften.
HOOKS_INSTALLED=1
if ! bash "$FACTORY_DIR/scripts/install-hooks.sh"; then
  HOOKS_INSTALLED=0
  echo -e "  ${YELLOW}⚠${NC}  Hook-Installation fehlgeschlagen – siehe Meldung oben"
  echo -e "     Ursache beheben (z. B. 'git init') und dann 'bash scripts/install-hooks.sh'"
fi

# ─── 5. Scripts ausführbar machen ────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Schritt 6: Scripts ausführbar machen...${NC}"
chmod +x "$FACTORY_DIR/scripts/"*.sh
chmod +x "$FACTORY_DIR/scripts/checks/"*.sh
echo -e "  ${GREEN}✓${NC} Scripts sind ausführbar"

# ─── 6. Abschluss ────────────────────────────────────────────────────────────

# Der Installer bricht bei gesetztem core.hooksPath o. Ä. bewusst fail-closed ab (ADR-042).
# Diese Aufrufstelle darf das nicht zur Warnung degradieren: ein Bootstrap ohne Git-Hooks
# ist unvollständig und meldet das per Banner UND Exit-Code.
if [ "$HOOKS_INSTALLED" -eq 0 ]; then
  echo ""
  echo -e "${RED}╔═════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  Bootstrap unvollständig – keine Git-Hooks  ║${NC}"
  echo -e "${RED}╚═════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Alles außer den Git-Hooks ist eingerichtet. Ursache oben beheben, dann nachziehen:"
  echo "  bash scripts/install-hooks.sh"
  exit 1
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Factory erfolgreich initialisiert ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo "Projekt:  $PROJECT_NAME"
echo "Sprache:  $PRIMARY_LANGUAGE / $FRAMEWORK"
echo "Datum:    $START_DATE"
echo ""
echo -e "${YELLOW}Nächste Schritte:${NC}"
echo "  1. Öffne Claude Code in diesem Verzeichnis"
echo "  2. Führe aus: /setup-project"
echo "     → Claude analysiert den Tech-Stack und vervollständigt die Konfiguration"
echo "  3. Erste Task anlegen (Issue-first): bash scripts/start-work.sh \"erste feature beschreibung\""
echo ""
