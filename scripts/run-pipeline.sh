#!/usr/bin/env bash
# run-pipeline.sh – Stage-3-Pipeline-Runner
#
# Verwendung: bash scripts/run-pipeline.sh <task-id> [--dry-run]
# Beispiel:   bash scripts/run-pipeline.sh 42
# Dry-run:    bash scripts/run-pipeline.sh 42 --dry-run
#
# Orchestriert die vollständige Factory-Pipeline deterministisch.
# Agenten werden aufgerufen – nicht umgekehrt.
#
# Voraussetzung: claude CLI muss installiert UND authentifiziert sein.
#   Stage 3 ruft die CLI nicht-interaktiv auf (--print) – dort läuft KEIN
#   OAuth-Login-Flow. Die Authentifizierung muss also vorab bestehen: entweder
#   ANTHROPIC_API_KEY gesetzt oder ein gültiger Keychain-Login (claude /login in
#   einem interaktiven Terminal). Fehlt beides, meldet jeder Sub-Aufruf
#   "Not logged in" und die Pipeline bricht ab.
#
# KOSTEN-HINWEIS: Stage 3 führt pro Feature 6+ Claude-Sessions hintereinander aus.
# Das verbraucht deutlich mehr Token als interaktive Nutzung.
# Kostenkontrolle über mehrere Variablen (unten konfigurierbar):
#   CLAUDE_MODEL_HEAVY – Modell für schwere Schritte (Default: Opus 4.8)
#   CLAUDE_MODEL_LIGHT – Modell für leichte Schritte (Default: Sonnet)
#   CLAUDE_MODEL       – globaler Override für ALLE Skills (hebt die Tiers auf)
#   MAX_TURNS          – begrenzt agentic Loops pro Skill-Aufruf

set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Geteilter Verdict-Helper (ADR-019 §4): EINE Verdict-Erkennung für den Report-Guard
# in run_skill() UND für pipeline_summary() – damit beide nicht auseinanderdriften.
# shellcheck source=scripts/lib/report-verdict.sh
source "$FACTORY_DIR/scripts/lib/report-verdict.sh"

# ─── Argumente prüfen ────────────────────────────────────────────────────────

DRY_RUN=false
TASK_ID=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -*) echo -e "${RED}Fehler:${NC} Unbekannte Option: $arg"; exit 1 ;;
    *)  TASK_ID="$arg" ;;
  esac
done

if [ -z "$TASK_ID" ]; then
  echo -e "${RED}Fehler:${NC} Task-ID erforderlich"
  echo "Verwendung: bash scripts/run-pipeline.sh <task-id> [--dry-run]"
  exit 1
fi

TASK_FILE=$(find "$FACTORY_DIR/tasks" -name "task-${TASK_ID}-*.md" | head -1)

if [ -z "$TASK_FILE" ]; then
  echo -e "${RED}Fehler:${NC} Keine Task-Datei für ID ${TASK_ID} gefunden"
  echo "Erstelle sie zuerst: bash scripts/start-work.sh ${TASK_ID} <beschreibung>"
  exit 1
fi

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Factory Pipeline – Task ${TASK_ID}          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

# ── Konfiguration: Single Source of Truth = factory.defaults.yml (ADR-009) ────
# Tier/Turns pro Skill kommen NICHT mehr aus hartkodierten case-Blöcken, sondern
# aus der geschichteten Config (defaults * optionaler Team-Override). yq ist
# Prerequisite (siehe README) – kein Fallback, sonst entstünde wieder Drift.
CONFIG_DEFAULTS="$FACTORY_DIR/factory.defaults.yml"
CONFIG_OVERRIDE="$FACTORY_DIR/factory.config.yml"
FACTORY_CFG=""   # effektive (gemergte) Config, einmal in load_config gefüllt

load_config() {
  if ! command -v yq >/dev/null 2>&1; then
    echo -e "${RED}Fehler:${NC} yq nicht gefunden – Factory-Prerequisite (siehe README)." >&2
    exit 1
  fi
  if [ ! -f "$CONFIG_DEFAULTS" ]; then
    echo -e "${RED}Fehler:${NC} $CONFIG_DEFAULTS fehlt." >&2
    exit 1
  fi
  # Fail-closed Validierung vor jeder Nutzung (ADR-010): ungültige Config bricht den
  # Lauf VOR der ersten Agenten-Aktion ab, statt still auf Defaults zurückzufallen.
  if ! "$FACTORY_DIR/scripts/checks/config-validation-check.sh" "$CONFIG_DEFAULTS" "$CONFIG_OVERRIDE"; then
    echo -e "${RED}Fehler:${NC} Config-Validierung fehlgeschlagen – Lauf abgebrochen." >&2
    exit 1
  fi
  if [ -f "$CONFIG_OVERRIDE" ]; then
    # Override gewinnt: tiefes Merge defaults * override
    FACTORY_CFG=$(yq eval-all '. as $i ireduce ({}; . * $i)' "$CONFIG_DEFAULTS" "$CONFIG_OVERRIDE")
  else
    FACTORY_CFG=$(cat "$CONFIG_DEFAULTS")
  fi
}

# cfg_skill_field <skill> <feld>  – Wert aus skills.<skill>.<feld>, sonst default.<feld>
cfg_skill_field() {
  printf '%s' "$FACTORY_CFG" | yq eval ".skills.\"$1\".$2 // .default.$2" - 2>/dev/null
}

get_max_turns() {
  cfg_skill_field "$1" max_turns
}

get_model() {
  local skill="$1"
  # Globaler Override: CLAUDE_MODEL setzt das Modell für ALLE Skills
  if [ -n "$CLAUDE_MODEL" ]; then
    echo "$CLAUDE_MODEL"
    return
  fi
  # Sonst tier-gestuft (tier kommt aus der Config); tier→Modell über die Env-Tiers
  case "$(cfg_skill_field "$skill" tier)" in
    heavy) echo "$CLAUDE_MODEL_HEAVY" ;;
    *)     echo "$CLAUDE_MODEL_LIGHT" ;;
  esac
}

preflight_checks() {
  local errors=0

  # 1. PROJECT-CONTEXT.md auf ungefüllte Platzhalter prüfen
  local context_file="$FACTORY_DIR/docs/factory/PROJECT-CONTEXT.md"
  if [ -f "$context_file" ] && grep -q "{{" "$context_file"; then
    echo -e "${RED}✗${NC} PROJECT-CONTEXT.md contains unfilled placeholders."
    echo "  → Run /setup-project first."
    errors=$((errors + 1))
  fi

  # 2. Spec-Datei prüfen (Warnung, kein Abbruch)
  local spec_file
  spec_file=$(find "$FACTORY_DIR/docs/specs" -name "spec-${TASK_ID}-*.md" 2>/dev/null | head -1 || true)
  if [ -z "$spec_file" ]; then
    echo -e "${YELLOW}⚠${NC}  No spec file found for task ${TASK_ID}."
    echo "  → Recommended: run /requirements ${TASK_ID} first."
  fi

  # 3. Git Working Tree prüfen
  if ! git -C "$FACTORY_DIR" diff --quiet 2>/dev/null || \
     ! git -C "$FACTORY_DIR" diff --cached --quiet 2>/dev/null; then
    echo -e "${RED}✗${NC} Git working tree is not clean (uncommitted changes)."
    echo "  → Please commit or stash before running the pipeline."
    errors=$((errors + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    echo ""
    echo -e "${RED}Pre-flight failed. Pipeline aborted.${NC}"
    exit 1
  fi

  # 4. Stale Interrupt-Sentinel aus einem früheren Lauf entfernen
  #    (sonst würde der erste Schritt sofort wieder stoppen, siehe ADR-004)
  local sentinel="$FACTORY_DIR/tasks/INTERRUPT-${TASK_ID}.md"
  if [ -f "$sentinel" ]; then
    echo -e "${YELLOW}⚠${NC}  Entferne Interrupt-Sentinel aus vorherigem Lauf: $(basename "$sentinel")"
    rm -f "$sentinel"
  fi

  echo -e "${GREEN}✓${NC} Pre-flight checks passed"
  echo ""
}

# ─── Konfiguration ───────────────────────────────────────────────────────────

# Effektive Config laden (factory.defaults.yml [* factory.config.yml]).
load_config

# Modell-Tiers: WELCHE Modelle hinter heavy/light stehen, kommt aus der Config
# (model_tiers); Env-Var sticht weiterhin (Kosten-Hebel). Tier→Skill-Zuordnung
# und Turns siehe factory.defaults.yml + get_model/get_max_turns.
CLAUDE_MODEL_HEAVY="${CLAUDE_MODEL_HEAVY:-$(printf '%s' "$FACTORY_CFG" | yq '.model_tiers.heavy // "claude-opus-4-8"' -)}"
CLAUDE_MODEL_LIGHT="${CLAUDE_MODEL_LIGHT:-$(printf '%s' "$FACTORY_CFG" | yq '.model_tiers.light // "claude-sonnet-4-6"' -)}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"                    # Optional: globaler Override für ALLE Skills (sonst gestuft)
MAX_TURNS="${MAX_TURNS:-}"                          # Optional: globaler Override (sonst per-skill via get_max_turns)

MAX_REVIEW_ITERATIONS="${MAX_REVIEW_ITERATIONS:-2}"  # Überschreibbar: MAX_REVIEW_ITERATIONS=3 bash scripts/run-pipeline.sh 42
REVIEW_ITERATION=0

run_skill() {
  local skill="$1"
  local task_id="$2"
  local turns="${MAX_TURNS:-$(get_max_turns "$skill")}"
  local model
  model="$(get_model "$skill")"
  echo -e "${YELLOW}→ Starte: /${skill} ${task_id} (model: ${model}, max ${turns} turns)${NC}"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}  [DRY-RUN] claude --print ... --model ${model} --max-turns ${turns}${NC}"
    return 0
  fi

  local skill_file="$FACTORY_DIR/.claude/commands/${skill}.md"
  if [ ! -f "$skill_file" ]; then
    echo -e "${RED}Fehler:${NC} Skill-Datei nicht gefunden: $skill_file"
    exit 1
  fi

  # Prompt aus der Slash-Command-Datei aufbereiten. Zwei Dinge, die die interaktive
  # Slash-Command-Mechanik erledigt, müssen wir im --print-Modus selbst tun:
  #   1. $ARGUMENTS (die Task-ID) einsetzen – sonst sieht der Agent den literalen
  #      Platzhalter und lädt keine Task-Datei.
  #   2. Die konkrete Task-Datei als Kontext beilegen. Ersetzt das frühere
  #      `--input-file`, das die claude-CLI nicht kennt (der Aufruf schlug bisher
  #      bei jedem Skill fehl → Stage 3 lief nie durch).
  local skill_body prompt
  skill_body="$(sed "s/\$ARGUMENTS/${task_id}/g" "$skill_file")"
  printf -v prompt '%s\n\n---\n\n# Task-Datei: %s\n\n%s\n' \
    "$skill_body" "$(basename "$TASK_FILE")" "$(cat "$TASK_FILE")"

  # Retry mit exponentiellem Backoff (z.B. bei Rate-Limit-Fehlern)
  # FACTORY_STAGE=3 signalisiert dem Agenten den nicht-interaktiven Modus:
  # statt eine Entscheidung zu erfragen, löst er einen Interrupt aus (ADR-004).
  local attempt
  for attempt in 1 2 3; do
    if FACTORY_STAGE=3 claude --print "$prompt" \
        --model "$model" \
        --max-turns "$turns" 2>&1; then
      echo -e "${GREEN}✓${NC} /${skill} abgeschlossen"
      # Hat der Agent einen Interrupt signalisiert? Dann hart stoppen.
      bash "$FACTORY_DIR/scripts/checks/interrupt-check.sh" "$task_id" || exit $?
      return 0
    fi

    # Report-Guard (ADR-019 §4): review/security-review schreiben ihren Report und
    # reißen bisweilen DANACH das Turn-Limit (non-zero Exit, „Reached max turns").
    # Ein bereits geschriebener, gültiger Verdict zählt als Erfolg – NUR für diese
    # zwei report-erzeugenden Skills; für alle anderen bleibt non-zero ein Fehlversuch.
    local verdict
    verdict="$(report_verdict "$skill" "$task_id")"
    if [ -n "$verdict" ]; then
      echo -e "${GREEN}✓${NC} /${skill} abgeschlossen (Verdict '${verdict}' – Turn-Limit nach fertigem Report toleriert)"
      # Auch hier: ein signalisierter Interrupt stoppt hart (kein stiller Übergang).
      bash "$FACTORY_DIR/scripts/checks/interrupt-check.sh" "$task_id" || exit $?
      return 0
    fi

    if [ "$attempt" -lt 3 ]; then
      local wait_seconds=$((attempt * 10))
      echo -e "${YELLOW}⚠ Attempt ${attempt}/3 failed – retrying in ${wait_seconds}s...${NC}"
      sleep "$wait_seconds"
    fi
  done

  echo -e "${RED}✗${NC} /${skill} failed after 3 attempts."
  exit 1
}

quality_gate() {
  local gate_name="$1"
  local command="$2"
  echo -e "${YELLOW}→ Quality Gate: ${gate_name}${NC}"
  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}  [DRY-RUN] $command${NC}"
    return 0
  fi
  if eval "$command"; then
    echo -e "${GREEN}✓${NC} Gate bestanden: ${gate_name}"
  else
    echo -e "${RED}✗${NC} Gate fehlgeschlagen: ${gate_name}"
    echo ""
    echo "Pipeline gestoppt. Bitte manuell korrigieren und erneut ausführen."
    exit 1
  fi
}

circuit_breaker_check() {
  if [ "$REVIEW_ITERATION" -ge "$MAX_REVIEW_ITERATIONS" ]; then
    echo -e "${RED}Circuit Breaker ausgelöst!${NC}"
    echo "Review↔Implement hat ${MAX_REVIEW_ITERATIONS}x nicht konvergiert."
    echo "Manuelles Eingreifen erforderlich."
    echo ""
    echo "Aktueller Stand in: $TASK_FILE"
    exit 2
  fi
  REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
}

count_section_items() {
  # Count checkbox lines ("- [") in a markdown section between two headings.
  # IMPORTANT: relies on the exact section headers defined in .claude/commands/review.md.
  # If the review output format changes, update the awk patterns here accordingly.
  local file="$1" start_pattern="$2" end_pattern="$3"
  awk "/$start_pattern/{found=1; next} /$end_pattern/{if(found) exit} found && /^- \[/{count++} END{print count+0}" \
    "$file" 2>/dev/null || echo 0
}

pipeline_summary() {
  local task_id="$1"
  local review_iter="$2"
  local task_file="$FACTORY_DIR/tasks/task-${task_id}.md"
  local review_file="$FACTORY_DIR/tasks/review-${task_id}.md"
  local security_file="$FACTORY_DIR/tasks/security-${task_id}.md"
  local codify_file="$FACTORY_DIR/tasks/codify-${task_id}.md"

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Pipeline Summary – Task ${task_id}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Was wurde implementiert
  echo ""
  echo -e "  ${GREEN}Implementierung${NC}"
  if [ -f "$task_file" ]; then
    local title
    title=$(grep -m1 "^# " "$task_file" 2>/dev/null | sed 's/^# //' || echo "(kein Titel)")
    echo "  → ${title}"
  else
    echo "  → Task-Datei nicht gefunden"
  fi

  # Review-Findings
  echo ""
  echo -e "  ${GREEN}Code Review${NC}"
  if [ -f "$review_file" ]; then
    local verdict critical important
    # Verdict über den geteilten Helper (ADR-019 §4) – dieselbe Erkennung wie der
    # Report-Guard in run_skill(), damit Summary und Guard nicht auseinanderdriften.
    verdict="$(report_verdict review "$task_id")"; verdict="${verdict:-unbekannt}"
    critical=$(count_section_items "$review_file" "## Kritische Findings" "## Wichtige Findings")
    important=$(count_section_items "$review_file" "## Wichtige Findings" "## Nitpicks")
    echo "  → Ergebnis: ${verdict} (nach ${review_iter} Iteration(en))"
    echo "  → Findings: ${critical} kritisch, ${important} wichtig"
  else
    echo "  → Keine Review-Datei gefunden"
  fi

  # Security-Status
  echo ""
  echo -e "  ${GREEN}Security${NC}"
  if [ -f "$security_file" ]; then
    local sec_status
    sec_status="$(report_verdict "security-review" "$task_id")"; sec_status="${sec_status:-unbekannt}"
    echo "  → Status: ${sec_status}"
  else
    echo "  → Kein Security-Report gefunden"
  fi

  # Codify – neue Regeln
  echo ""
  echo -e "  ${GREEN}Codify – neue Regeln${NC}"
  if [ -f "$codify_file" ]; then
    local rule_count
    # grep -c gibt bei 0 Treffern "0" + exit 1. KEIN "|| echo 0" (zweizeilig), aber das
    # non-zero muss geschluckt werden, sonst bricht die Zuweisung unter set -e ab → "|| true".
    rule_count=$(grep -c "^- " "$codify_file" 2>/dev/null || true); rule_count=${rule_count:-0}
    echo "  → ${rule_count} neue Regel(n) hinzugefügt"
    grep "^- " "$codify_file" 2>/dev/null | head -3 | while IFS= read -r line; do
      echo "    ${line}"
    done
    if [ "${rule_count}" -gt 3 ] 2>/dev/null; then
      echo "    … (weitere in tasks/codify-${task_id}.md)"
    fi
  else
    echo "  → tasks/codify-${task_id}.md nicht gefunden"
    echo "    → /codify schreibt Regeln ab sofort in diese Datei"
  fi

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ─── Pipeline ────────────────────────────────────────────────────────────────

echo "Task-Datei: $TASK_FILE"
[ "$DRY_RUN" = true ] && echo -e "${BLUE}Mode: DRY-RUN (no Claude calls will be made)${NC}"
echo ""

preflight_checks

# Phase 1: Implementieren
echo -e "${BLUE}Phase 1: Implementierung${NC}"
run_skill "implement" "$TASK_ID"

# Quality-Gate-Befehle – echte Befehle, konsistent mit scripts/checks/pre-commit.sh
# und pre-push.sh (dieselbe Env-Override-Konvention). Default = pnpm-Skripte aus
# PROJECT-CONTEXT.md; CI-/Kosten-Hebel per FACTORY_*_COMMAND. Frühere echo-Platzhalter
# waren fail-open (echo → immer Exit 0 → Gate meldete grün, ohne je zu prüfen; #101).
LINT_CMD="${FACTORY_LINT_COMMAND:-pnpm lint}"
TEST_CMD="${FACTORY_TEST_COMMAND:-pnpm test}"
COVERAGE_CMD="${FACTORY_COVERAGE_COMMAND:-pnpm test:coverage}"

# Quality Gate: Lint + Tests
quality_gate "Lint" "$LINT_CMD"
quality_gate "Tests" "$TEST_CMD"

# Phase 2: Review-Loop (mit Circuit Breaker)
REVIEW_APPROVED=false
while [ "$REVIEW_APPROVED" = false ]; do
  echo ""
  echo -e "${BLUE}Phase 2: Code-Review (Iteration $((REVIEW_ITERATION + 1)))${NC}"
  run_skill "review" "$TASK_ID"

  # Review-Ergebnis prüfen
  REVIEW_FILE="$FACTORY_DIR/tasks/review-${TASK_ID}.md"
  if [ -f "$REVIEW_FILE" ] && grep -q "APPROVED" "$REVIEW_FILE"; then
    echo -e "${GREEN}✓${NC} Review bestanden"
    REVIEW_APPROVED=true
  else
    circuit_breaker_check
    echo -e "${YELLOW}Review: NEEDS_REWORK – Iteration $REVIEW_ITERATION von $MAX_REVIEW_ITERATIONS${NC}"
    echo ""
    echo -e "${BLUE}Phase 2b: Rework${NC}"
    run_skill "implement" "$TASK_ID"
    quality_gate "Tests nach Rework" "$TEST_CMD"
  fi
done

# Phase 3: Testing
echo ""
echo -e "${BLUE}Phase 3: Test-Vervollständigung${NC}"
run_skill "test" "$TASK_ID"
quality_gate "Coverage" "$COVERAGE_CMD"

# Phase 4: Refactoring
echo ""
echo -e "${BLUE}Phase 4: Refactoring${NC}"
run_skill "refactor" "$TASK_ID"
quality_gate "Tests nach Refactoring" "$TEST_CMD"

# Phase 5: Security Review – letztes Gate vor Merge, prüft den finalen
# (refaktorierten) Code (ADR-005)
echo ""
echo -e "${BLUE}Phase 5: Security Review${NC}"
run_skill "security-review" "$TASK_ID"

SECURITY_FILE="$FACTORY_DIR/tasks/security-${TASK_ID}.md"
if [ -f "$SECURITY_FILE" ] && grep -q "NEEDS_FIXES" "$SECURITY_FILE"; then
  echo -e "${RED}Security Review: NEEDS_FIXES${NC}"
  echo "Kritische Security-Findings müssen manuell behoben werden."
  exit 1
fi

# Phase 6: Codify
echo ""
echo -e "${BLUE}Phase 6: Codify – Learnings extrahieren${NC}"
run_skill "codify" "$TASK_ID"

# Phase 7: PR Shepherd (optional – nur wenn PR_SHEPHERD=true gesetzt)
if [ "${PR_SHEPHERD:-false}" = "true" ]; then
  echo ""
  echo -e "${BLUE}Phase 7: PR Shepherd – PR-Lifecycle bis Auto-Merge${NC}"
  run_skill "pr-shepherd" "$TASK_ID"
fi

# ─── Abschluss ───────────────────────────────────────────────────────────────

pipeline_summary "$TASK_ID" "$REVIEW_ITERATION"

echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Pipeline erfolgreich abgeschlossen ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo "Task ${TASK_ID} ist fertig."
if [ "${PR_SHEPHERD:-false}" = "true" ]; then
  echo "PR Shepherd wurde ausgeführt – PR sollte merge-ready oder bereits gemergt sein."
else
  echo "Nächster Schritt: Pull Request erstellen (oder PR_SHEPHERD=true neu starten)"
fi
echo ""
