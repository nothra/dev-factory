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

GIT_HOOKS_DIR="$FACTORY_DIR/.git/hooks"

if [ -d "$GIT_HOOKS_DIR" ]; then
  # pre-commit Hook
  cat > "$GIT_HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env bash
bash scripts/checks/pre-commit.sh
EOF
  chmod +x "$GIT_HOOKS_DIR/pre-commit"
  echo -e "  ${GREEN}✓${NC} pre-commit Hook installiert"

  # pre-push Hook
  cat > "$GIT_HOOKS_DIR/pre-push" << 'EOF'
#!/usr/bin/env bash
bash scripts/checks/pre-push.sh
EOF
  chmod +x "$GIT_HOOKS_DIR/pre-push"
  echo -e "  ${GREEN}✓${NC} pre-push Hook installiert"
else
  echo -e "  ${YELLOW}⚠${NC}  Kein .git Verzeichnis gefunden – Hooks nicht installiert"
  echo -e "     Führe 'git init' aus und dann nochmal 'bash scripts/init-factory.sh'"
fi

# ─── 5. Scripts ausführbar machen ────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Schritt 6: Scripts ausführbar machen...${NC}"
chmod +x "$FACTORY_DIR/scripts/"*.sh
chmod +x "$FACTORY_DIR/scripts/checks/"*.sh
echo -e "  ${GREEN}✓${NC} Scripts sind ausführbar"

# ─── 6. Abschluss ────────────────────────────────────────────────────────────

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
echo "  3. Erste Task anlegen: bash scripts/start-work.sh 1 erste-feature-beschreibung"
echo ""
