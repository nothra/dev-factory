#!/usr/bin/env bash
# run-tests.sh – Tabellen-getriebene Tests für die Check-Skripte
#
# Verwendung: bash scripts/checks/tests/run-tests.sh
# Exit-Code 0 = alle Tests grün, 1 = mindestens ein Test rot.
#
# Deckt ab:
#   - branch-name-check.sh: Erkennung von checkout -b/-B und switch -c/-C
#     sowie Prüfung gegen die erlaubten Präfixe
#   - check.sh (pre-tool): End-to-End über stdin-JSON (Hook-Kontrakt)

set -uo pipefail

CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# yq ist Prerequisite für run-pipeline.sh (ADR-009 A: verbindlich, kein Fallback) –
# ABER die Test-Suite bleibt yq-frei lauffähig: Struktur-Checks (grep) laufen immer,
# yq-abhängige Resolution-/Config-Wert-Checks (und Tests, die run-pipeline.sh starten)
# nur, wenn yq vorhanden ist. Sonst lautes Skip statt rot – so läuft die Suite auch in
# Test-Images adoptierter Projekte ohne yq grün; die echte Resolution wird dort getestet,
# wo yq da ist (Template-CI, Runtime-Image, Devs mit yq).
command -v yq >/dev/null 2>&1 && HAS_YQ=1 || HAS_YQ=0
skip_yq() { echo "  • ${1} – übersprungen (yq fehlt, ADR-009)"; }

# ─── branch-name-check.sh: direkter Aufruf mit Befehls-String ────────────────
echo "branch-name-check.sh (Befehls-String als \$1):"

# Format: "<befehl>|<erwarteter-exit>|<beschreibung>"
branch_cases=(
  "git checkout -b feature/42-login|0|checkout -b mit gültigem feature/"
  "git checkout -b improvement/foo|0|checkout -b mit gültigem improvement/"
  "git checkout -b bogus-name|1|checkout -b mit ungültigem Namen"
  "git checkout -B feature/42-login|0|checkout -B (force) mit gültigem Präfix"
  "git checkout -B bogus-name|1|checkout -B (force) mit ungültigem Namen"
  "git switch -c fix/bug|0|switch -c mit gültigem fix/"
  "git switch -c bogus-name|1|switch -c mit ungültigem Namen"
  "git switch -C bogus-name|1|switch -C (force) mit ungültigem Namen"
  "git checkout main|0|checkout ohne Branch-Erstellung (kein Match)"
  "git status|0|unrelated Befehl (kein Match)"
)

for case in "${branch_cases[@]}"; do
  IFS='|' read -r cmd expected desc <<< "$case"
  bash "$CHECKS_DIR/branch-name-check.sh" "$cmd" >/dev/null 2>&1
  assert_exit "$expected" "$?" "$desc"
done

# ─── check.sh pre-tool: End-to-End über stdin-JSON ───────────────────────────
echo "check.sh pre-tool (stdin-JSON, End-to-End):"

e2e_cases=(
  "git checkout -b feature/ok|0|gültiger checkout -b durch Dispatcher"
  "git checkout -b bogus|1|ungültiger checkout -b blockiert"
  "git switch -c bogus|1|ungültiger switch -c blockiert"
  "git checkout -B bogus|1|ungültiger checkout -B blockiert"
  "ls -la|0|harmloser Befehl unberührt"
)

for case in "${e2e_cases[@]}"; do
  IFS='|' read -r cmd expected desc <<< "$case"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" \
    | bash "$CHECKS_DIR/check.sh" pre-tool >/dev/null 2>&1
  assert_exit "$expected" "$?" "$desc"
done

# ─── Interrupt-Mechanismus (raise-interrupt.sh + interrupt-check.sh) ─────────
echo "Interrupt-Mechanismus (Stage-3, ADR-004):"

SCRIPTS_DIR="$(cd "$CHECKS_DIR/.." && pwd)"
TMP_FACTORY="$(mktemp -d)"
mkdir -p "$TMP_FACTORY/tasks"
# Realistische Task-Datei, damit der Blocker-Eintrag geprüft werden kann
printf '# Task 99: demo\n\n## Beschreibung\nx\n' > "$TMP_FACTORY/tasks/task-99-demo.md"

# 1. Kein Sentinel → interrupt-check exit 0
FACTORY_DIR="$TMP_FACTORY" bash "$CHECKS_DIR/interrupt-check.sh" 99 >/dev/null 2>&1
assert_exit 0 "$?" "interrupt-check ohne Sentinel → exit 0"

# 2. raise-interrupt schreibt das Sentinel
FACTORY_DIR="$TMP_FACTORY" bash "$SCRIPTS_DIR/raise-interrupt.sh" 99 ADR "Kategorie 2: Event-Driven" >/dev/null 2>&1
ri_exit=$?
[[ -f "$TMP_FACTORY/tasks/INTERRUPT-99.md" ]]; assert_true "$?" "raise-interrupt legt Sentinel an"
assert_exit 0 "$ri_exit" "raise-interrupt → exit 0"

# 3. Mit Sentinel → interrupt-check exit 1 (harter Stopp)
FACTORY_DIR="$TMP_FACTORY" bash "$CHECKS_DIR/interrupt-check.sh" 99 >/dev/null 2>&1
assert_exit 1 "$?" "interrupt-check mit Sentinel → exit 1"

# 4. Blocker wird in die Task-Datei eingetragen
grep -q "^Blocker .*ADR: Kategorie 2: Event-Driven" "$TMP_FACTORY/tasks/task-99-demo.md"
assert_true "$?" "interrupt-check trägt Blocker in Task-Datei ein"

# 5. Blocker ist idempotent (zweiter Lauf dupliziert nicht)
FACTORY_DIR="$TMP_FACTORY" bash "$CHECKS_DIR/interrupt-check.sh" 99 >/dev/null 2>&1
blocker_count=$(grep -c "^Blocker .*Event-Driven" "$TMP_FACTORY/tasks/task-99-demo.md")
assert_true "$([[ "$blocker_count" -eq 1 ]]; echo $?)" "Blocker-Eintrag bleibt idempotent (genau 1x)"

# 6. raise-interrupt ohne Nachricht → Aufruf-Fehler exit 1
FACTORY_DIR="$TMP_FACTORY" bash "$SCRIPTS_DIR/raise-interrupt.sh" 99 ADR >/dev/null 2>&1
assert_exit 1 "$?" "raise-interrupt ohne Nachricht → exit 1"

rm -rf "$TMP_FACTORY"

# 7. interrupt-check ohne Task-ID → exit 2 (Aufruf-Fehler, kein Interrupt)
bash "$CHECKS_DIR/interrupt-check.sh" >/dev/null 2>&1
assert_exit 2 "$?" "interrupt-check ohne Task-ID → exit 2"

# 8. raise-interrupt ACTION-Default (kein 4. Argument → Standard-Aktion im Sentinel)
TMP_DEFAULT="$(mktemp -d)"
mkdir -p "$TMP_DEFAULT/tasks"
FACTORY_DIR="$TMP_DEFAULT" bash "$SCRIPTS_DIR/raise-interrupt.sh" 88 ADR "Kategorie 1" >/dev/null 2>&1
assert_exit 0 "$?" "raise-interrupt ohne Aktion (ACTION-Default) → exit 0"
grep -q "^Aktion: /architecture ausführen" "$TMP_DEFAULT/tasks/INTERRUPT-88.md"
assert_true "$?" "raise-interrupt schreibt Standard-Aktion ins Sentinel"
rm -rf "$TMP_DEFAULT"

# 9. Preflight-Stale-Cleanup: run-pipeline.sh --dry-run entfernt Stale-Sentinel.
# Startet run-pipeline.sh → nur mit yq lauffähig (load_config-Prerequisite, ADR-009).
if [ "$HAS_YQ" = 1 ]; then
  TMP_PF="$(mktemp -d)"
  mkdir -p "$TMP_PF/tasks" "$TMP_PF/docs/factory" "$TMP_PF/scripts"
  echo "# Project" > "$TMP_PF/docs/factory/PROJECT-CONTEXT.md"
  echo "# Task 55: cleanup-test" > "$TMP_PF/tasks/task-55-cleanup-test.md"
  echo "# INTERRUPT – Task 55" > "$TMP_PF/tasks/INTERRUPT-55.md"
  git -C "$TMP_PF" init -q
  git -C "$TMP_PF" add .
  git -C "$TMP_PF" -c user.email="test@test.com" -c user.name="test" commit -q -m "init"
  mkdir -p "$TMP_PF/scripts/checks"
  cp "$SCRIPTS_DIR/run-pipeline.sh" "$TMP_PF/scripts/"
  cp "$SCRIPTS_DIR/checks/config-validation-check.sh" "$TMP_PF/scripts/checks/"  # Gate-Abhängigkeit (ADR-010)
  cp "$SCRIPTS_DIR/../factory.defaults.yml" "$TMP_PF/"   # run-pipeline liest sie (Phase 1b, ADR-009)
  bash "$TMP_PF/scripts/run-pipeline.sh" 55 --dry-run >/dev/null 2>&1 || true
  assert_true "$([[ ! -f "$TMP_PF/tasks/INTERRUPT-55.md" ]]; echo $?)" "Preflight entfernt Stale-Sentinel vor Pipeline-Start"
  rm -rf "$TMP_PF"
else
  skip_yq "Preflight entfernt Stale-Sentinel vor Pipeline-Start"
fi

# ─── Stufe-1-Additions: Command-Dateien & Pipeline-Wiring ────────────────────
echo ""
echo "Stufe-1 Quick Wins (bug-fix / pr-shepherd / CI):"

FACTORY_ROOT="$(cd "$CHECKS_DIR/../.." && pwd)"
PIPELINE="$FACTORY_ROOT/scripts/run-pipeline.sh"
CI_FILE="$FACTORY_ROOT/.gitlab-ci.yml"
SHEPHERD="$FACTORY_ROOT/.claude/commands/pr-shepherd.md"

assert_true "$([[ -f "$FACTORY_ROOT/.claude/commands/bug-fix.md" ]]; echo $?)" \
  "/bug-fix Command-Datei vorhanden"
assert_true "$([[ -f "$SHEPHERD" ]]; echo $?)" \
  "/pr-shepherd Command-Datei vorhanden"
assert_true "$([[ -f "$CI_FILE" ]]; echo $?)" \
  ".gitlab-ci.yml vorhanden"

# Tier/Turns kommen seit Phase 1b (ADR-009) aus factory.defaults.yml statt aus
# hartkodierten case-Blöcken → gegen die Config prüfen (yq, nur wo vorhanden).
DEFAULTS_YML="$FACTORY_ROOT/factory.defaults.yml"
if [ "$HAS_YQ" = 1 ]; then
  # bug-fix erbt implement-Tier: heavy / 20
  [ "$(yq '.skills.bug-fix.tier' "$DEFAULTS_YML")" = "heavy" ] && [ "$(yq '.skills.bug-fix.max_turns' "$DEFAULTS_YML")" = "20" ]
  assert_true "$?" "bug-fix ist heavy/20 (Config, Phase 1b)"
  # pr-shepherd: light / 8
  [ "$(yq '.skills.pr-shepherd.tier' "$DEFAULTS_YML")" = "light" ] && [ "$(yq '.skills.pr-shepherd.max_turns' "$DEFAULTS_YML")" = "8" ]
  assert_true "$?" "pr-shepherd ist light/8 (Config, Phase 1b)"
else
  skip_yq "bug-fix heavy/20 + pr-shepherd light/8 (Config, Phase 1b)"
fi

# pr-shepherd nur als optionale Phase 7 (PR_SHEPHERD-Guard)
grep -q 'PR_SHEPHERD:-false' "$PIPELINE"
assert_true "$?" "Phase 7 (pr-shepherd) ist hinter PR_SHEPHERD-Flag"

# kein Blind-Fix: bug-fix verlangt Reproduktionstest + eskaliert per Interrupt
grep -q 'raise-interrupt.sh' "$FACTORY_ROOT/.claude/commands/bug-fix.md"
assert_true "$?" "bug-fix eskaliert nicht-reproduzierbare Bugs via raise-interrupt"

# pr-shepherd rebaset server-seitig (kein lokaler Force-Push, Regel bleibt gewahrt)
grep -q 'glab mr rebase' "$SHEPHERD"
assert_true "$?" "pr-shepherd nutzt server-seitiges 'glab mr rebase'"

# CI-Gates fail-closed: FACTORY_*_COMMAND-Variable, exit 1 wenn unkonfiguriert
{ grep -q 'FACTORY_LINT_COMMAND' "$CI_FILE" && grep -q 'FACTORY_TEST_COMMAND' "$CI_FILE" && grep -q 'exit 1' "$CI_FILE"; }
assert_true "$?" "CI lint/test sind echte Gates (FACTORY_*_COMMAND, fail-closed)"

# ─── Stufe-2: OTEL-ready Bauchladen (#17) ────────────────────────────────────
echo ""
echo "Stufe-2 OTEL-Telemetrie (#17):"

OTEL_FILE="$FACTORY_ROOT/config/otel.env.example"
assert_true "$([[ -f "$OTEL_FILE" ]]; echo $?)" "config/otel.env.example vorhanden"

# Master-Schalter ist der Kern der Telemetrie-Aktivierung
grep -q 'CLAUDE_CODE_ENABLE_TELEMETRY=1' "$OTEL_FILE"
assert_true "$?" "otel.env.example enthält CLAUDE_CODE_ENABLE_TELEMETRY=1"

# Default AUS heißt: Beispiel-Datei, nicht automatisch gesourct → kein Wiring in run-pipeline.sh
grep -q 'otel.env' "$FACTORY_ROOT/scripts/run-pipeline.sh"
assert_true "$([ $? -ne 0 ]; echo $?)" "OTEL ist opt-in (nicht automatisch in run-pipeline.sh gesourct)"

# ─── Stufe-2: Metrics-Digest + Interrupt-Log (#12) ───────────────────────────
echo ""
echo "Stufe-2 Metrics-Digest (#12):"

assert_true "$([[ -f "$FACTORY_ROOT/scripts/metrics.sh" ]]; echo $?)" "scripts/metrics.sh vorhanden"
assert_true "$([[ -f "$FACTORY_ROOT/.claude/commands/daily-metrics.md" ]]; echo $?)" "/daily-metrics Command-Datei vorhanden"

# Verhalten: raise-interrupt schreibt eine JSON-Zeile ins append-only Log.
# Task 5 hat eine Task-Datei, 99 nicht → testet später die Mengen-Schnittmenge.
TMP_LOG="$(mktemp -d)"
mkdir -p "$TMP_LOG/tasks"
FACTORY_DIR="$TMP_LOG" bash "$SCRIPTS_DIR/raise-interrupt.sh" 5 ADR "Kat 2: Event-Driven" >/dev/null 2>&1
FACTORY_DIR="$TMP_LOG" bash "$SCRIPTS_DIR/raise-interrupt.sh" 99 MERGE_CONFLICT "Konflikt in x.ts" >/dev/null 2>&1
log_lines=$(grep -c '"task_id"' "$TMP_LOG/tasks/interrupt-log.jsonl" 2>/dev/null); log_lines=${log_lines:-0}
assert_true "$([[ "$log_lines" -eq 2 ]]; echo $?)" "raise-interrupt hängt pro Event eine Zeile ans interrupt-log.jsonl"
# Log überlebt den Sentinel-Cleanup (Sentinels löschbar, Log bleibt)
rm -f "$TMP_LOG/tasks/INTERRUPT-"*.md
assert_true "$([[ -f "$TMP_LOG/tasks/interrupt-log.jsonl" ]]; echo $?)" "interrupt-log.jsonl überlebt Sentinel-Cleanup"

# Finding-1-Regression: Sonderzeichen (Quote, Backslash, Tab) → valides JSON pro Zeile
if command -v jq >/dev/null 2>&1; then
  FACTORY_DIR="$TMP_LOG" bash "$SCRIPTS_DIR/raise-interrupt.sh" 5 MERGE "$(printf 'sagt "hi" \\pfad\ttab')" >/dev/null 2>&1
  jq_ok=0; while IFS= read -r line; do printf '%s' "$line" | jq -e . >/dev/null 2>&1 || jq_ok=1; done < "$TMP_LOG/tasks/interrupt-log.jsonl"
  assert_true "$jq_ok" "interrupt-log bleibt valides JSON bei Sonderzeichen (Finding 1)"
fi

# Verhalten: metrics.sh --no-api – Mengen-Schnitt (nur existierende Tasks zählen)
echo "# Task 5: a" > "$TMP_LOG/tasks/task-5-a.md"; printf -- '- [x] Fertig\n' >> "$TMP_LOG/tasks/task-5-a.md"
echo "# Task 2: b" > "$TMP_LOG/tasks/task-2-b.md"; printf -- '- [ ] Fertig\n' >> "$TMP_LOG/tasks/task-2-b.md"
FACTORY_DIR="$TMP_LOG" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet >/dev/null 2>&1
report="$TMP_LOG/tasks/metrics-$(date +%Y-%m-%d).md"
assert_true "$([[ -f "$report" ]]; echo $?)" "metrics.sh schreibt Report-Datei"
grep -q '| Tasks gesamt | 2 |' "$report" 2>/dev/null
assert_true "$?" "metrics.sh zählt Tasks gesamt korrekt (2)"
grep -q '| Abgeschlossen | 1 |' "$report" 2>/dev/null
assert_true "$?" "metrics.sh zählt abgeschlossene Tasks korrekt (1)"
# task_id 5 hat eine Datei (zählt), 99 nicht (zählt NICHT) → Mengen geschnitten (Finding 2)
grep -q '| Tasks mit Interrupt (vorhanden) | 1 |' "$report" 2>/dev/null
assert_true "$?" "metrics.sh zählt nur Interrupts existierender Tasks (Finding 2)"
grep -q '| Autonomie-Rate | 50% |' "$report" 2>/dev/null
assert_true "$?" "metrics.sh berechnet Autonomie-Rate aus geschnittener Menge (50%)"
rm -rf "$TMP_LOG"

# ─── Pre-Commit: portable Regex (Regression) ─────────────────────────────────
echo ""
echo "Pre-Commit portable Regex (#bug-precommit):"
PRE_COMMIT="$SCRIPTS_DIR/checks/pre-commit.sh"
PC_TMP="$(mktemp -d)"
( cd "$PC_TMP" && git init -q && git config user.email t@t && git config user.name t )
# Fixture: geplantetes Secret + TODO ohne Ticket-Referenz (triggert Check 3 & 4)
printf 'api_key = "abcdef123456"\n# TODO ohne ticket\n' > "$PC_TMP/leak.conf"
( cd "$PC_TMP" && git add leak.conf )
pc_out=$( cd "$PC_TMP" && bash "$PRE_COMMIT" 2>&1 || true )
# (a) Kein Regex-Engine-Fehler – portabel über BSD/GNU/ugrep (kein \s, kein PCRE-Lookahead)
printf '%s' "$pc_out" | grep -qiE 'operand invalid|invalid syntax|preceding regular expression'
assert_true "$([ $? -ne 0 ]; echo $?)" "pre-commit läuft ohne Regex-Engine-Fehler (portabel)"
# (b) Credential-Check erkennt das geplantete Secret weiterhin
printf '%s' "$pc_out" | grep -q 'hardkodierte Credentials'
assert_true "$?" "pre-commit Credential-Check erkennt geplantetes Secret"
rm -rf "$PC_TMP"

# ─── Stufe-2: Post-Merge-Verify (#11) ────────────────────────────────────────
echo ""
echo "Stufe-2 Post-Merge-Verify (#11):"

assert_true "$([[ -f "$FACTORY_ROOT/scripts/post-merge-verify.sh" ]]; echo $?)" "scripts/post-merge-verify.sh vorhanden"
assert_true "$([[ -f "$FACTORY_ROOT/.claude/commands/post-merge-verify.md" ]]; echo $?)" "/post-merge-verify Command-Datei vorhanden"
# CI-Job läuft nur auf dem Default-Branch (nach Merge), nicht bei MR-Events
grep -q 'post-merge-verify:' "$FACTORY_ROOT/.gitlab-ci.yml"
assert_true "$?" "post-merge-verify-Job in .gitlab-ci.yml"

TMP_PMV="$(mktemp -d)"
mkdir -p "$TMP_PMV/tasks" "$TMP_PMV/scripts" "$TMP_PMV/bin"
cp "$SCRIPTS_DIR/post-merge-verify.sh" "$SCRIPTS_DIR/raise-interrupt.sh" "$TMP_PMV/scripts/"
# Tests sollen nicht schlafen: keine Retries / kein Backoff (außer im #24-Retry-Test).
export FACTORY_HEALTHCHECK_RETRIES=0 FACTORY_HEALTHCHECK_INTERVAL=0

# Skip-Pfad: ohne FACTORY_HEALTHCHECK_URL → exit 0, kein Interrupt
FACTORY_DIR="$TMP_PMV" bash "$TMP_PMV/scripts/post-merge-verify.sh" 11 >/dev/null 2>&1
assert_exit 0 "$?" "post-merge-verify ohne URL → übersprungen (exit 0)"
assert_true "$([[ ! -f "$TMP_PMV/tasks/interrupt-log.jsonl" ]]; echo $?)" "Skip-Pfad löst keinen Interrupt aus"

# Fail-Pfad: gemocktes curl liefert 503 → exit 1 + POST_MERGE_FAIL im Log
printf '#!/bin/sh\necho 503\n' > "$TMP_PMV/bin/curl"; chmod +x "$TMP_PMV/bin/curl"
PATH="$TMP_PMV/bin:$PATH" FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_URL="http://x.test/health" \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 11 >/dev/null 2>&1
assert_exit 1 "$?" "post-merge-verify bei Fehl-Status → exit 1"
grep -q '"type":"POST_MERGE_FAIL"' "$TMP_PMV/tasks/interrupt-log.jsonl" 2>/dev/null
assert_true "$?" "Fail-Pfad protokolliert POST_MERGE_FAIL im interrupt-log"

# Regression: curl endet NON-ZERO (Verbindungsfehler) → einzeiliger Status "000",
# kein doppeltes "000\n000" (CMs !22-Finding). curl gibt 000 selbst aus + exit 7.
rm -f "$TMP_PMV/tasks/interrupt-log.jsonl"
printf '#!/bin/sh\necho 000\nexit 7\n' > "$TMP_PMV/bin/curl"; chmod +x "$TMP_PMV/bin/curl"
PATH="$TMP_PMV/bin:$PATH" FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_URL="http://x.test/health" \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 11 >/dev/null 2>&1
assert_exit 1 "$?" "post-merge-verify bei curl-Fehler (non-zero) → exit 1"
grep -q 'HTTP 000 (erwartet 200)' "$TMP_PMV/tasks/interrupt-log.jsonl" 2>/dev/null
assert_true "$?" "curl-Fehler meldet einzeiliges '000' (kein 000\\\\n000, !22-Finding)"

# #23: pluggbarer FACTORY_HEALTHCHECK_CMD (Exit-Code = Urteil), Vorrang vor URL
rm -f "$TMP_PMV/tasks/interrupt-log.jsonl"
FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_CMD="true" \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 23 >/dev/null 2>&1
assert_exit 0 "$?" "HEALTHCHECK_CMD mit exit 0 → bestanden, kein Interrupt"
assert_true "$([[ ! -f "$TMP_PMV/tasks/interrupt-log.jsonl" ]]; echo $?)" "CMD-Erfolg löst keinen Interrupt aus"

FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_CMD="sh -c 'exit 3'" \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 23 >/dev/null 2>&1
assert_exit 1 "$?" "HEALTHCHECK_CMD mit non-zero exit → exit 1 (POST_MERGE_FAIL)"
grep -q 'endete mit exit 3' "$TMP_PMV/tasks/interrupt-log.jsonl" 2>/dev/null
assert_true "$?" "CMD-Fehler meldet korrekten Exit-Code (if-ohne-else-Falle vermieden)"

# Vorrang: CMD gesetzt → URL wird ignoriert (CMD ok trotz kaputter URL)
# Output erst in Variable fangen (grep -q + pipefail würde sonst per SIGPIPE rot).
pmv_out=$(FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_CMD="true" FACTORY_HEALTHCHECK_URL="http://x.test" \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 23 2>&1)
printf '%s' "$pmv_out" | grep -q 'Smoke-Command'
assert_true "$?" "CMD hat Vorrang vor URL, wenn beide gesetzt"

# #24: Retry/Poll gegen Deploy-Lag. CMs vorgegebener Testfall – Mock liefert erst
# beim 3. Versuch 200 (Deployment hinkt nach) → grün; Dauerfehler → exit 1.
rm -f "$TMP_PMV/tasks/interrupt-log.jsonl"; echo 0 > "$TMP_PMV/cnt"
cat > "$TMP_PMV/bin/curl" <<CURLEOF
#!/bin/sh
c=\$(cat "$TMP_PMV/cnt" 2>/dev/null || echo 0); c=\$((c+1)); echo \$c > "$TMP_PMV/cnt"
if [ "\$c" -ge 3 ]; then echo 200; else echo 503; fi
CURLEOF
chmod +x "$TMP_PMV/bin/curl"
PATH="$TMP_PMV/bin:$PATH" FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_URL="http://x.test/health" \
  FACTORY_HEALTHCHECK_RETRIES=3 FACTORY_HEALTHCHECK_INTERVAL=0 \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 24 >/dev/null 2>&1
assert_exit 0 "$?" "#24: Erfolg erst nach Retries (Deploy-Lag) → grün, kein POST_MERGE_FAIL"
assert_true "$([[ ! -f "$TMP_PMV/tasks/interrupt-log.jsonl" ]]; echo $?)" "#24: kein Fehlalarm bei verspätetem Deployment"

# Schneller Erfolg bleibt schnell: 1. Versuch OK → genau ein curl-Aufruf (kein Poll)
echo 0 > "$TMP_PMV/cnt"
printf '#!/bin/sh\nc=$(cat "%s/cnt"); c=$((c+1)); echo $c > "%s/cnt"; echo 200\n' "$TMP_PMV" "$TMP_PMV" > "$TMP_PMV/bin/curl"
chmod +x "$TMP_PMV/bin/curl"
PATH="$TMP_PMV/bin:$PATH" FACTORY_DIR="$TMP_PMV" FACTORY_HEALTHCHECK_URL="http://x.test/health" \
  FACTORY_HEALTHCHECK_RETRIES=3 FACTORY_HEALTHCHECK_INTERVAL=99 \
  bash "$TMP_PMV/scripts/post-merge-verify.sh" 24 >/dev/null 2>&1
assert_true "$([[ "$(cat "$TMP_PMV/cnt")" -eq 1 ]]; echo $?)" "#24: Erfolg beim 1. Versuch → kein künstliches Warten (genau 1 Check)"
rm -rf "$TMP_PMV"

# CI-Rule: post-merge-verify nur bei push auf den Default-Branch (nicht Scheduled)
grep -q 'CI_PIPELINE_SOURCE == "push"' "$FACTORY_ROOT/.gitlab-ci.yml"
assert_true "$?" "post-merge-verify-Job ist auf push (nach Merge) eingegrenzt"

# ─── Stufe-2: Async-Trigger / Scheduled-Poll (#10, ADR-008) ──────────────────
echo ""
echo "Stufe-2 Async-Trigger (#10):"

CI_YML="$FACTORY_ROOT/.gitlab-ci.yml"
assert_true "$([[ -f "$FACTORY_ROOT/scripts/factory-poll.sh" ]]; echo $?)" "scripts/factory-poll.sh vorhanden"
assert_true "$([[ -f "$FACTORY_ROOT/ci/factory-runtime.Dockerfile" ]]; echo $?)" "ci/factory-runtime.Dockerfile vorhanden"
grep -q 'factory-poll:' "$CI_YML"; assert_true "$?" "factory-poll-Job in .gitlab-ci.yml"
grep -q 'resource_group: factory-runtime' "$CI_YML"; assert_true "$?" "factory-poll hat resource_group (Concurrency=1, Idempotenz)"
grep -q 'CI_PIPELINE_SOURCE == "schedule"' "$CI_YML"; assert_true "$?" "factory-poll nur in Scheduled Pipeline"

# Verhalten: Guard-Pfade gegen gemocktes glab (kein echtes GitLab nötig).
# Output erst in Variable fangen (grep -q + pipefail → sonst SIGPIPE-Falschrot).
TMP_POLL="$(mktemp -d)"; mkdir -p "$TMP_POLL/scripts" "$TMP_POLL/bin"
cp "$SCRIPTS_DIR/factory-poll.sh" "$TMP_POLL/scripts/"
cat > "$TMP_POLL/bin/glab" <<'GLABEOF'
#!/bin/sh
case "$*" in
  *updated_before*) echo "${FAKE_STALE:-[]}" ;;
  *"labels=factory::running&state=opened&per_page"*) echo "${FAKE_RUNNING:-[]}" ;;
  *"labels=factory::done"*) echo "${FAKE_DONE:-[]}" ;;
  *"labels=factory::interrupted"*) echo "${FAKE_INTR:-[]}" ;;
  *"labels=factory::run&state=opened&order_by"*) echo "${FAKE_RUNQ:-[]}" ;;
  *) echo "[]" ;;
esac
GLABEOF
chmod +x "$TMP_POLL/bin/glab"
poll() { PATH="$TMP_POLL/bin:$PATH" FACTORY_DIR="$TMP_POLL" FACTORY_PROJECT=1 \
  FACTORY_MAX_RUNS_PER_DAY="${MAXR:-5}" bash "$TMP_POLL/scripts/factory-poll.sh" --dry-run 2>&1; }

out=$(FAKE_RUNNING='[{"iid":7}]' poll); printf '%s' "$out" | grep -q 'Concurrency=1'
assert_true "$?" "Guard: laufender Lauf blockiert (Concurrency=1)"
# K-1: interrupted zählt gegen die Tageskappe (done=1 + interrupted=1 = Kappe 2)
out=$(MAXR=2 FAKE_DONE='[1]' FAKE_INTR='[9]' poll); printf '%s' "$out" | grep -q 'Tageskappe erreicht (2/2'
assert_true "$?" "K-1: interrupted zählt gegen die Tageskappe"
out=$(poll); printf '%s' "$out" | grep -q 'nichts zu tun'
assert_true "$?" "Guard: keine factory::run-Issues → nichts zu tun"
out=$(FAKE_RUNQ='[{"iid":42}]' poll); printf '%s' "$out" | grep -q 'Issue #42'
assert_true "$?" "wählt ältestes factory::run-Issue (#42)"
# W-3: nicht ermittelbarer Zustand (API-Fehler) → LAUT (exit 3), nicht stiller Leerlauf
out=$(FAKE_RUNNING='APIERROR' poll); rc=$?
assert_exit 3 "$rc" "W-3: API-Fehler → exit 3 (laut, roter Job)"
printf '%s' "$out" | grep -q 'BLOCKED (fail-closed)'
assert_true "$?" "W-3: API-Fehler meldet BLOCKED statt still durchzuwinken"
# W-1: verwaister running-Lauf wird vom Stale-Reaper zurückgesetzt
out=$(FAKE_STALE='[{"iid":5}]' poll); printf '%s' "$out" | grep -q 'verwaisten running-Lauf #5'
assert_true "$?" "W-1: Stale-Reaper setzt verwaisten running-Lauf zurück"
rm -rf "$TMP_POLL"

# W-2: Fehlerpfad unterscheidet Interrupt (Sentinel da) von echtem Fehler (kein Sentinel).
# Non-dry-run mit gefälschtem run-pipeline (exit 1) + glab, das Mutationen mitloggt.
TMP_W2="$(mktemp -d)"; mkdir -p "$TMP_W2/scripts" "$TMP_W2/tasks" "$TMP_W2/bin"
cp "$SCRIPTS_DIR/factory-poll.sh" "$TMP_W2/scripts/"
printf '#!/bin/sh\nexit 1\n' > "$TMP_W2/scripts/run-pipeline.sh"; chmod +x "$TMP_W2/scripts/run-pipeline.sh"
cat > "$TMP_W2/bin/glab" <<'GLABEOF'
#!/bin/sh
case "$*" in
  *"?add_labels"*) echo "$*" >> "$GLAB_LOG"; echo '{}' ;;          # Mutation → mitloggen
  *"issues/50") echo '{"labels":["factory::running"]}' ;;          # Flip-Verify-GET
  *"labels=factory::run&state=opened&order_by"*) echo '[{"iid":50}]' ;;
  *) echo "[]" ;;
esac
GLABEOF
chmod +x "$TMP_W2/bin/glab"
w2() { PATH="$TMP_W2/bin:$PATH" FACTORY_DIR="$TMP_W2" FACTORY_PROJECT=1 GLAB_LOG="$TMP_W2/mut.log" \
  bash "$TMP_W2/scripts/factory-poll.sh" >/dev/null 2>&1; }

# Kein Sentinel → echter Fehler → factory::failed
: > "$TMP_W2/mut.log"; w2
grep -q 'add_labels=factory::failed' "$TMP_W2/mut.log"
assert_true "$?" "W-2: Pipeline-Fehler ohne Sentinel → factory::failed"
# Sentinel da → Interrupt → factory::interrupted (nicht failed)
: > "$TMP_W2/mut.log"; echo "# INTERRUPT" > "$TMP_W2/tasks/INTERRUPT-50.md"; w2
grep -q 'add_labels=factory::interrupted' "$TMP_W2/mut.log"
assert_true "$?" "W-2: Pipeline-Stopp mit Sentinel → factory::interrupted"
grep -q 'add_labels=factory::failed' "$TMP_W2/mut.log"
assert_true "$([ $? -ne 0 ]; echo $?)" "W-2: Interrupt wird NICHT als failed fehletikettiert"
rm -rf "$TMP_W2"

# ─── Codify: Bash-Gotchas-Guideline ──────────────────────────────────────────
echo ""
echo "Codify (Bash-Gotchas-Guideline):"

GOTCHAS="$FACTORY_ROOT/docs/factory/guidelines/bash-gotchas.md"
assert_true "$([[ -f "$GOTCHAS" ]]; echo $?)" "bash-gotchas.md vorhanden"
grep -q 'bash-gotchas.md' "$FACTORY_ROOT/CLAUDE.md"
assert_true "$?" "bash-gotchas.md ist in CLAUDE.md referenziert"

# Anti-Regression: die codifizierten Gotchas selbst nicht in den Skripten verwenden.
# (Kommentarzeilen ausgenommen – die dürfen das Muster zu Doku-Zwecken nennen.)
# (1) kein 'grep -c … || echo' (Gotcha 2, Falle 1)
! grep -rnE 'grep -c[^|]*\|\| *echo' "$SCRIPTS_DIR" 2>/dev/null \
  | grep -v '/tests/' | grep -vE ':[0-9]+:[[:space:]]*#'
assert_true "$?" "kein 'grep -c … || echo'-Muster in scripts/ (Gotcha 2, Falle 1)"

# N-1 (CMs Finding): Laufzeit-Beweis der set-e-Sicherheit (nicht nur Textmuster).
# Mirror von pipeline_summary's rule_count gegen ein 0-Treffer-File unter set -e.
ZERO=$(mktemp); printf '# nur ein Header, keine Regel-Zeilen\n' > "$ZERO"
# Korrektes Idiom (|| true) → kein Abbruch, rc=0:
( set -euo pipefail; rc=$(grep -c '^- ' "$ZERO" 2>/dev/null || true); rc=${rc:-0}; [ "$rc" = "0" ] ) 2>/dev/null
assert_exit 0 "$?" "Gotcha 2 RICHTIG-Idiom (|| true) ist set-e-sicher bei 0 Treffern"
# Gegenprobe: ohne || true bricht es unter set -e ab (beweist, dass der Test scharf ist):
( set -euo pipefail; rc=$(grep -c '^- ' "$ZERO" 2>/dev/null); rc=${rc:-0} ) 2>/dev/null
assert_true "$([ $? -ne 0 ]; echo $?)" "Gegenprobe: ohne || true bricht es unter set -e ab"
rm -f "$ZERO"

# (2) run-pipeline.sh rule_count nutzt das set-e-sichere Idiom (|| true) – K-1-Regression
grep -qE 'grep -c "\^- " "\$codify_file" 2>/dev/null \|\| true' "$PIPELINE"
assert_true "$?" "run-pipeline.sh rule_count ist set-e-sicher (|| true, K-1)"

# ─── Stufe-2.5: Factory-Config Phase 1b – run-pipeline liest die Config (#25) ─
echo ""
echo "Factory-Config Phase 1b (#25, ADR-009):"

DEFAULTS="$FACTORY_ROOT/factory.defaults.yml"
assert_true "$([[ -f "$DEFAULTS" ]]; echo $?)" "factory.defaults.yml vorhanden"
grep -q '^schemaVersion:' "$DEFAULTS"; assert_true "$?" "factory.defaults.yml hat schemaVersion"

# Struktur-Checks (yq-frei): run-pipeline.sh liest die Config statt Hardcode-case.
grep -q 'load_config' "$PIPELINE"; assert_true "$?" "run-pipeline.sh ruft load_config (Phase 1b)"
grep -q 'cfg_skill_field' "$PIPELINE"; assert_true "$?" "run-pipeline.sh löst Tier/Turns aus der Config auf"
# Hardcode-case ist WEG (Config ist die einzige Quelle – kein Drift mehr)
! grep -qE 'implement\|refactor\|test\|bug-fix\) +echo 20' "$PIPELINE"
assert_true "$?" "alter Hardcode-case ist entfernt (Config = Single Source of Truth)"

# yq-abhängige Checks: nur wo yq vorhanden ist (siehe HAS_YQ oben, ADR-009). Die echte
# Resolution wird dort getestet, wo yq da ist; run-pipeline.sh selbst bricht ohne yq
# laut ab (Prerequisite, kein Fallback) – das wird hier bewusst nicht erzwungen.
if [ "$HAS_YQ" = 1 ]; then
  yq eval '.' "$DEFAULTS" >/dev/null 2>&1; assert_true "$?" "factory.defaults.yml parst als valides YAML (yq)"

  # Kanonische Werte (= heutiges Verhalten, via Config)
  [ "$(yq '.skills.implement.tier' "$DEFAULTS")" = "heavy" ] && [ "$(yq '.skills.implement.max_turns' "$DEFAULTS")" = "20" ]
  assert_true "$?" "Config: implement = heavy/20"
  [ "$(yq '.skills.codify.tier' "$DEFAULTS")" = "light" ] && [ "$(yq '.skills.codify.max_turns' "$DEFAULTS")" = "8" ]
  assert_true "$?" "Config: codify = light/8"
  [ "$(yq '.default.max_turns' "$DEFAULTS")" = "10" ]
  assert_true "$?" "Config: default max_turns = 10 (unbekannte Skills)"

  # Behavioral end-to-end: run-pipeline --dry-run löst implement aus der Config zu opus/20 auf
  TMP_CFG="$(mktemp -d)"; mkdir -p "$TMP_CFG/scripts/checks" "$TMP_CFG/tasks" "$TMP_CFG/docs/factory"
  cp "$PIPELINE" "$TMP_CFG/scripts/"; cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_CFG/scripts/checks/"; cp "$DEFAULTS" "$TMP_CFG/"
  echo "# ctx" > "$TMP_CFG/docs/factory/PROJECT-CONTEXT.md"; echo "# Task 1: x" > "$TMP_CFG/tasks/task-1-x.md"
  git -C "$TMP_CFG" init -q; git -C "$TMP_CFG" add .
  git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  cfg_out=$(bash "$TMP_CFG/scripts/run-pipeline.sh" 1 --dry-run 2>&1 || true)
  printf '%s' "$cfg_out" | grep -q 'Starte: /implement 1 (model: claude-opus-4-8, max 20 turns)'
  assert_true "$?" "Phase 1b: run-pipeline löst implement aus der Config zu opus/20 auf (end-to-end)"
  # Team-Override greift: factory.config.yml setzt implement auf 5 Turns → 5 statt 20
  printf 'skills:\n  implement: { max_turns: 5 }\n' > "$TMP_CFG/factory.config.yml"
  git -C "$TMP_CFG" add .; git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m override
  ovr_out=$(bash "$TMP_CFG/scripts/run-pipeline.sh" 1 --dry-run 2>&1 || true)
  printf '%s' "$ovr_out" | grep -q 'Starte: /implement 1 (model: claude-opus-4-8, max 5 turns)'
  assert_true "$?" "Phase 1b: Team-Override (factory.config.yml) übersteuert Defaults (Turns 20→5)"
  rm -rf "$TMP_CFG"
else
  skip_yq "YAML-Parse, Config-Werte (implement/codify/default) und End-to-End-Resolution"
fi

# ─── Stufe-2.6: Config-Validierungs-Gate (#36, ADR-010) ──────────────────────
echo ""
echo "Config-Validierungs-Gate (#36, ADR-010):"

GATE="$CHECKS_DIR/config-validation-check.sh"
assert_true "$([[ -f "$GATE" ]]; echo $?)" "config-validation-check.sh vorhanden"
assert_true "$([[ -x "$GATE" ]]; echo $?)" "config-validation-check.sh ist ausführbar"
# Integration: run-pipeline.sh ruft das Gate fail-closed (vor erster Agenten-Aktion)
grep -q 'config-validation-check' "$PIPELINE"
assert_true "$?" "run-pipeline.sh ruft das Validierungs-Gate auf"

# yq-abhängige Verhaltens-Checks (Positiv + Negativ); sonst lautes Skip (yq-frei grün)
if [ "$HAS_YQ" = 1 ] && [ -f "$GATE" ]; then
  GTMP="$(mktemp -d)"

  # Positiv: nur Defaults (kein Override)
  bash "$GATE" "$DEFAULTS" >/dev/null 2>&1
  assert_true "$?" "Gate: valide Config (nur Defaults) → exit 0"

  # Positiv: sauberer Override
  printf 'skills:\n  implement: { max_turns: 5 }\n' > "$GTMP/ok.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/ok.yml" >/dev/null 2>&1
  assert_true "$?" "Gate: sauberer Override (implement.max_turns=5) → exit 0"

  # Negativ: unbekannter Key (Tippfehler max_turn statt max_turns)
  printf 'skills:\n  implement: { max_turn: 5 }\n' > "$GTMP/typo.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/typo.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: unbekannter Key (max_turn-Tippfehler) → fail-closed"

  # Negativ: unbekannter Top-Level-Key
  printf 'bogus: 1\n' > "$GTMP/top.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/top.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: unbekannter Top-Level-Key → fail-closed"

  # Negativ: schemaVersion-Mismatch
  printf 'schemaVersion: 2\n' > "$GTMP/sv.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/sv.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: schemaVersion-Mismatch → fail-closed"

  # Negativ: max_turns über Ceiling
  printf 'skills:\n  implement: { max_turns: 9999 }\n' > "$GTMP/ceil.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/ceil.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: max_turns über Ceiling → fail-closed"

  # Negativ: max_turns nicht-integer
  printf 'skills:\n  implement: { max_turns: viele }\n' > "$GTMP/nonint.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/nonint.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: max_turns nicht-integer → fail-closed"

  # Negativ: tier außerhalb model_tiers
  printf 'skills:\n  implement: { tier: medium }\n' > "$GTMP/tier.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/tier.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: tier außerhalb model_tiers → fail-closed"

  # Negativ: kaputtes YAML
  printf 'skills: [unclosed\n' > "$GTMP/broken.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/broken.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: kaputtes YAML → fail-closed"

  # Positiv (Grenzfall): leerer Override ist gültig (Team hat noch nichts gesetzt)
  : > "$GTMP/empty.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/empty.yml" >/dev/null 2>&1
  assert_true "$?" "Gate: leerer Override → exit 0"

  # Negativ (Grenzfall): max_turns = 0 (unter Minimum 1)
  printf 'skills:\n  implement: { max_turns: 0 }\n' > "$GTMP/zero.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/zero.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate: max_turns = 0 (unter Minimum) → fail-closed"

  rm -rf "$GTMP"
else
  skip_yq "Gate-Validierung (Positiv/Negativ-Fixtures)"
fi

# ─── Stufe-3: Config-Wizards / Single-Source-Begründung (#35, ADR-011) ───────
echo ""
echo "Config-Wizards / Single-Source-Begründung (#35, ADR-011):"

SETUP="$FACTORY_ROOT/.claude/commands/setup-project.md"
CONFIGURE="$FACTORY_ROOT/.claude/commands/configure-factory.md"
EXAMPLE="$FACTORY_ROOT/factory.config.yml.example"
# DEFAULTS_YML ist bereits oben (Stufe-1) definiert → hier nicht erneut zuweisen.
# Un-verankerte Textkörper-Regex (ADR-011): Tag-Doppelpunkt + nicht-leerer Body, an
# beliebiger Position (eigenständig ODER trailing). Bewusst KEIN ^-Anker, POSIX (kein \s).
TEXTBODY_RE='#[[:space:]]*@(reason|tradeoff):[[:space:]]*[^[:space:]]'

# D / B: neuer Skill + Beispiel-Datei existieren
assert_true "$([[ -f "$CONFIGURE" ]]; echo $?)" "/configure-factory Command-Datei vorhanden"
assert_true "$([[ -f "$EXAMPLE" ]]; echo $?)" "factory.config.yml.example vorhanden"

# A: /setup-project-Bootstrap schlägt Config vor UND ruft das Gate fail-closed auf
grep -q 'factory.config.yml' "$SETUP"
assert_true "$?" "A: setup-project schlägt factory.config.yml vor (Bootstrap)"
grep -q 'config-validation-check' "$SETUP"
assert_true "$?" "A: setup-project ruft das Validierungs-Gate (sonst keine Datei hinterlassen)"

# B: /configure-factory validiert die geänderte Config über das Gate vor „fertig"
grep -q 'config-validation-check' "$CONFIGURE"
assert_true "$?" "B: configure-factory validiert über das Gate vor 'fertig'"

# C(a): jeder Skill-Knopf in den Defaults trägt einen @reason-Textkörper (Single Source).
# Schreibweise-UNABHÄNGIG (CM-Review !39): nicht an die Inline-Flow-Map ("name: { … }")
# koppeln — ADR-011 erlaubt auch Block-Style, bei dem das @reason auf einer Kind-Zeile sitzt.
# yq-frei: den skills-Block isolieren (von 'skills:' bis zum nächsten Top-Level-Key), darin
# direkte Kind-Einträge (2-Space-Indent, beide Schreibweisen) gegen @reason-Textkörper IM Block
# zählen. Inline → @reason auf der Eintragszeile; Block → auf einer Kind-Zeile, beide im Block →
# reasons==entries in beiden Fällen (kein false-green, kein false-red).
skills_block=$(awk '/^skills:/{f=1;next} f&&/^[^[:space:]]/{f=0} f' "$DEFAULTS_YML" 2>/dev/null || true)
skill_entries=$(printf '%s\n' "$skills_block" | grep -cE '^  [a-z-]+:' || true); skill_entries=${skill_entries:-0}
skill_reasons=$(printf '%s\n' "$skills_block" | grep -cE '@reason:[[:space:]]*[^[:space:]]' || true); skill_reasons=${skill_reasons:-0}
assert_true "$([[ "$skill_entries" -gt 0 && "$skill_reasons" -ge "$skill_entries" ]]; echo $?)" \
  "C(a): jeder skills-Knopf trägt einen @reason-Textkörper, schreibweise-unabhängig (${skill_reasons}≥${skill_entries})"

# C(a/yq): präziser, schreibweise-unabhängiger Vollständigkeitstest — je Skill-Pfad ein @reason,
# entweder als line_comment am Schlüssel (Inline) ODER an einer skalaren Kind-Zeile (Block-Style).
if [ "$HAS_YQ" = 1 ]; then
  ca_missing=""
  while IFS= read -r sk; do
    [ -z "$sk" ] && continue
    has_reason=0
    key_lc=$(yq eval ".skills.\"$sk\" | line_comment" "$DEFAULTS_YML" 2>/dev/null)
    printf '%s' "$key_lc" | grep -qE '@reason:[[:space:]]*[^[:space:]]' && has_reason=1
    if [ "$has_reason" -eq 0 ]; then
      while IFS= read -r ch; do
        [ -z "$ch" ] && continue
        ch_lc=$(yq eval ".skills.\"$sk\".\"$ch\" | line_comment" "$DEFAULTS_YML" 2>/dev/null)
        if printf '%s' "$ch_lc" | grep -qE '@reason:[[:space:]]*[^[:space:]]'; then has_reason=1; break; fi
      done < <(yq eval ".skills.\"$sk\" | keys | .[]" "$DEFAULTS_YML" 2>/dev/null)
    fi
    [ "$has_reason" -eq 1 ] || ca_missing="$ca_missing $sk"
  done < <(yq eval '.skills | keys | .[]' "$DEFAULTS_YML" 2>/dev/null)
  assert_true "$([[ -z "$ca_missing" ]]; echo $?)" \
    "C(a/yq): jeder Skill-Pfad hat eine @reason-Annotation (Inline oder Block-Style):${ca_missing:- alle}"
else
  skip_yq "C(a/yq): per-Pfad-@reason-Vollständigkeit (Schreibweise-unabhängig)"
fi

# C(a): die ZWEI Hebel-Dimensionen (model_tiers, skills) tragen @reason UND je einen @tradeoff.
# Geschärft (CM-Review !39): nicht „irgendwo ≥1", sondern ≥2 @tradeoff-Textkörper — einer je
# Hebel-Dimension (model_tiers + skills); die nicht-justierbaren Defaults brauchen keinen.
tradeoff_count=$(grep -cE '@tradeoff:[[:space:]]*[^[:space:]]' "$DEFAULTS_YML" 2>/dev/null || true); tradeoff_count=${tradeoff_count:-0}
{ grep -qE "$TEXTBODY_RE" "$DEFAULTS_YML" && [ "$tradeoff_count" -ge 2 ]; }
assert_true "$?" "C(a): Defaults tragen @reason + je Hebel-Dimension einen @tradeoff (≥2: ${tradeoff_count})"

# C(b): KEIN Begründungs-Textkörper außerhalb factory.defaults.yml. Scope-Grenze bewusst:
#       geprüft werden die PRODUKTIVEN Artefakte (Anti-Drift-Ziele der Konvention) — die feste
#       Liste factory.config.yml.example + .claude/commands/*.md, NICHT repo-weit. docs/ (ADR/Spec
#       lehren die Konvention und tragen legitime Beispiel-Tags) ist bewusst ausgenommen (ADR-011).
drift_files=""
for f in "$EXAMPLE" "$FACTORY_ROOT"/.claude/commands/*.md; do
  [ -f "$f" ] || continue
  grep -ElH "$TEXTBODY_RE" "$f" >/dev/null 2>&1 && drift_files="$drift_files $f"
done
assert_true "$([[ -z "$drift_files" ]]; echo $?)" \
  "C(b): kein @reason/@tradeoff-Textkörper außerhalb factory.defaults.yml (Anti-Drift)"

# C: Test ist scharf — Positiv-Kontrolle (Textkörper matcht) + Negativ-Kontrolle (Verweis matcht NICHT)
grep -qE "$TEXTBODY_RE" "$DEFAULTS_YML"
assert_true "$?" "C: Textkörper-Regex matcht in den Defaults (Positiv-Kontrolle)"
printf '# Begruendung: siehe factory.defaults.yml -> skills.implement (Tag @reason)\n' | grep -qE "$TEXTBODY_RE"
assert_true "$([ $? -ne 0 ]; echo $?)" "C: Verweis-Form (Tag-Wort ohne :-Body) matcht den Textkörper-Regex NICHT"

# D: Example verweist auf die Single Source und enthält keinen aktiven Override
grep -q 'factory.defaults.yml' "$EXAMPLE"
assert_true "$?" "D: factory.config.yml.example verweist auf die Defaults als Begründungs-Quelle"
if [ "$HAS_YQ" = 1 ]; then
  # yq behält beim Round-Trip die Kommentare bei → Wert ist nicht literal "null".
  # Robust: der Daten-Tag des Dokuments ist !!null (kein aktiver Override-Inhalt).
  [ "$(yq eval 'tag' "$EXAMPLE" 2>/dev/null)" = "!!null" ]
  assert_true "$?" "D: factory.config.yml.example hat keinen aktiven Override (yq-Tag → !!null)"
else
  skip_yq "D: factory.config.yml.example hat keinen aktiven Override (yq-Tag → !!null)"
fi

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
echo -e "Ergebnis: ${GREEN}${PASS} grün${NC}, ${RED}${FAIL} rot${NC}"
[[ "$FAIL" -eq 0 ]]
