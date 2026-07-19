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
  mkdir -p "$TMP_PF/scripts/checks" "$TMP_PF/scripts/lib"
  cp "$SCRIPTS_DIR/run-pipeline.sh" "$TMP_PF/scripts/"
  cp "$SCRIPTS_DIR/checks/config-validation-check.sh" "$TMP_PF/scripts/checks/"  # Gate-Abhängigkeit (ADR-010)
  cp "$SCRIPTS_DIR/lib/report-verdict.sh" "$TMP_PF/scripts/lib/"  # run-pipeline sourct sie (Task 91, ADR-019 §4)
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
CI_FILE="$FACTORY_ROOT/.github/workflows/factory-ci.yml"
SHEPHERD="$FACTORY_ROOT/.claude/commands/pr-shepherd.md"

assert_true "$([[ -f "$FACTORY_ROOT/.claude/commands/bug-fix.md" ]]; echo $?)" \
  "/bug-fix Command-Datei vorhanden"
assert_true "$([[ -f "$SHEPHERD" ]]; echo $?)" \
  "/pr-shepherd Command-Datei vorhanden"
assert_true "$([[ -f "$CI_FILE" ]]; echo $?)" \
  ".github/workflows/factory-ci.yml vorhanden"

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

# pr-shepherd aktualisiert den Branch server-seitig (kein lokaler Force-Push,
# Regel bleibt gewahrt). GitHub-Äquivalent zu 'glab mr rebase': 'gh pr update-branch'.
grep -q 'gh pr update-branch' "$SHEPHERD"
assert_true "$?" "pr-shepherd nutzt server-seitiges 'gh pr update-branch'"

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

# ─── #96: metrics.sh Lead-Time ist locale-unabhängig (printf-%f-Regression) ──
# bash `printf '%.1f'` parst sein Argument lokale-abhängig (strtod). Unter einer
# Locale mit Komma-Dezimaltrenner (z. B. de_DE) schlägt das Parsen eines
# Punkt-Dezimalwerts wie "1.75" fehl ("invalid number") und printf fällt still
# auf "0,0" zurück – beobachtet bei Task 67. Fix: Rundung/Formatierung läuft
# jetzt komplett in jq (immer Punkt-Dezimaltrenner, locale-unabhängig).
echo ""
echo "#96 metrics.sh Lead-Time locale-sicher:"

command -v jq >/dev/null 2>&1 && HAS_JQ=1 || HAS_JQ=0
# Output erst einfangen, dann greppen (bash-gotchas.md #3: sonst SIGPIPE-Falschrot
# unter set -o pipefail, weil grep -q beim ersten Treffer die Pipe schließt).
avail_locales="$(locale -a 2>/dev/null)"
printf '%s' "$avail_locales" | grep -qxF "de_DE.UTF-8" && HAS_DE_LOCALE=1 || HAS_DE_LOCALE=0

if [ "$HAS_JQ" -eq 1 ] && [ "$HAS_DE_LOCALE" -eq 1 ]; then
  TMP_METRICS="$(mktemp -d)"
  mkdir -p "$TMP_METRICS/tasks" "$TMP_METRICS/fakebin"

  # Fake `gh`: zwei gemergte PRs mit einer nicht-ganzzahligen Ø-Lead-Time
  # ((1h + 2.5h) / 2 = 1.75h) – erzwingt einen echten Dezimalwert im jq/printf-Pfad.
  cat > "$TMP_METRICS/fakebin/gh" <<'FAKEGH'
#!/usr/bin/env bash
case "$*" in
  "auth status") exit 0 ;;
  *"pr list --state merged --limit 20 --json createdAt,mergedAt"*)
    echo '[{"createdAt":"2026-01-01T00:00:00Z","mergedAt":"2026-01-01T01:00:00Z"},{"createdAt":"2026-01-01T00:00:00Z","mergedAt":"2026-01-01T02:30:00Z"}]'
    ;;
  *"run list --limit 20 --json conclusion"*)
    echo '[{"conclusion":"success"},{"conclusion":"success"}]'
    ;;
  *) exit 1 ;;
esac
FAKEGH
  chmod +x "$TMP_METRICS/fakebin/gh"

  metrics_err=$(PATH="$TMP_METRICS/fakebin:$PATH" LC_ALL=de_DE.UTF-8 LC_NUMERIC=de_DE.UTF-8 \
    FACTORY_DIR="$TMP_METRICS" bash "$SCRIPTS_DIR/metrics.sh" --quiet 2>&1 >/dev/null)
  assert_true "$([[ -z "$metrics_err" ]]; echo $?)" "#96: keine stderr-Ausgabe (kein printf 'invalid number') unter de_DE-Locale"

  report="$TMP_METRICS/tasks/metrics-$(date +%Y-%m-%d).md"
  grep -qE '\| Lead-Time \(Issue→Merge\) \| 1\.[0-9]+ h' "$report" 2>/dev/null
  assert_true "$?" "#96: Lead-Time wird mit Punkt-Dezimaltrenner korrekt berechnet (nicht '0,0')"

  rm -rf "$TMP_METRICS"
else
  echo "  • #96: metrics.sh Lead-Time locale-sicher – übersprungen (jq oder de_DE.UTF-8-Locale fehlt)"
fi

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
# CI-Job läuft nur auf dem Default-Branch (nach Merge), nicht bei Pull Requests
grep -q 'post-merge-verify:' "$CI_FILE"
assert_true "$?" "post-merge-verify-Job in .github/workflows/factory-ci.yml"

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

# CI-Rule: post-merge-verify nur bei push auf den Default-Branch (nicht Pull Request)
grep -q "github.event_name == 'push'" "$CI_FILE"
assert_true "$?" "post-merge-verify-Job ist auf push (nach Merge) eingegrenzt"

# ─── Stufe-2: Async-Trigger / Scheduled-Poll (#10, ADR-008) ──────────────────
echo ""
echo "Stufe-2 Async-Trigger (#10):"

POLL_YML="$FACTORY_ROOT/.github/workflows/factory-poll.yml"
assert_true "$([[ -f "$FACTORY_ROOT/scripts/factory-poll.sh" ]]; echo $?)" "scripts/factory-poll.sh vorhanden"
assert_true "$([[ -f "$POLL_YML" ]]; echo $?)" ".github/workflows/factory-poll.yml vorhanden"
grep -q 'factory-poll:' "$POLL_YML"; assert_true "$?" "factory-poll-Job in factory-poll.yml"
grep -q 'group: factory-runtime' "$POLL_YML"; assert_true "$?" "factory-poll hat concurrency-group (Concurrency=1, Idempotenz)"
grep -q 'schedule:' "$POLL_YML"; assert_true "$?" "factory-poll nur als Scheduled Workflow"

# Verhalten: Guard-Pfade gegen gemocktes gh (kein echtes GitHub nötig).
# Output erst in Variable fangen (grep -q + pipefail → sonst SIGPIPE-Falschrot).
# Mock-Disambiguierung: 'factory::run"' (mit schließendem Quote) trifft NUR die
# run-queue-Suche, nicht 'factory::running"'. Die updated:<-Suche ist der Stale-Reaper.
TMP_POLL="$(mktemp -d)"; mkdir -p "$TMP_POLL/scripts" "$TMP_POLL/bin"
cp "$SCRIPTS_DIR/factory-poll.sh" "$TMP_POLL/scripts/"
cat > "$TMP_POLL/bin/gh" <<'GHEOF'
#!/bin/sh
case "$*" in
  *"updated:<"*) echo "${FAKE_STALE:-[]}" ;;
  *"factory::done"*) echo "${FAKE_DONE:-[]}" ;;
  *"factory::interrupted"*) echo "${FAKE_INTR:-[]}" ;;
  *"factory::running"*) echo "${FAKE_RUNNING:-[]}" ;;
  *"factory::run"*) echo "${FAKE_RUNQ:-[]}" ;;
  *) echo "[]" ;;
esac
GHEOF
chmod +x "$TMP_POLL/bin/gh"
poll() { PATH="$TMP_POLL/bin:$PATH" FACTORY_DIR="$TMP_POLL" FACTORY_REPO=test/repo \
  FACTORY_MAX_RUNS_PER_DAY="${MAXR:-5}" bash "$TMP_POLL/scripts/factory-poll.sh" --dry-run 2>&1; }

out=$(FAKE_RUNNING='[{"number":7}]' poll); printf '%s' "$out" | grep -q 'Concurrency=1'
assert_true "$?" "Guard: laufender Lauf blockiert (Concurrency=1)"
# K-1: interrupted zählt gegen die Tageskappe (done=1 + interrupted=1 = Kappe 2)
out=$(MAXR=2 FAKE_DONE='[1]' FAKE_INTR='[9]' poll); printf '%s' "$out" | grep -q 'Tageskappe erreicht (2/2'
assert_true "$?" "K-1: interrupted zählt gegen die Tageskappe"
out=$(poll); printf '%s' "$out" | grep -q 'nichts zu tun'
assert_true "$?" "Guard: keine factory::run-Issues → nichts zu tun"
out=$(FAKE_RUNQ='[{"number":42}]' poll); printf '%s' "$out" | grep -q 'Issue #42'
assert_true "$?" "wählt ältestes factory::run-Issue (#42)"
# W-3: nicht ermittelbarer Zustand (API-Fehler) → LAUT (exit 3), nicht stiller Leerlauf
out=$(FAKE_RUNNING='APIERROR' poll); rc=$?
assert_exit 3 "$rc" "W-3: API-Fehler → exit 3 (laut, roter Job)"
printf '%s' "$out" | grep -q 'BLOCKED (fail-closed)'
assert_true "$?" "W-3: API-Fehler meldet BLOCKED statt still durchzuwinken"
# W-1: verwaister running-Lauf wird vom Stale-Reaper zurückgesetzt
out=$(FAKE_STALE='[{"number":5}]' poll); printf '%s' "$out" | grep -q 'verwaisten running-Lauf #5'
assert_true "$?" "W-1: Stale-Reaper setzt verwaisten running-Lauf zurück"
rm -rf "$TMP_POLL"

# W-2: Fehlerpfad unterscheidet Interrupt (Sentinel da) von echtem Fehler (kein Sentinel).
# Non-dry-run mit gefälschtem run-pipeline (exit 1) + gh, das Mutationen mitloggt.
TMP_W2="$(mktemp -d)"; mkdir -p "$TMP_W2/scripts" "$TMP_W2/tasks" "$TMP_W2/bin"
cp "$SCRIPTS_DIR/factory-poll.sh" "$TMP_W2/scripts/"
printf '#!/bin/sh\nexit 1\n' > "$TMP_W2/scripts/run-pipeline.sh"; chmod +x "$TMP_W2/scripts/run-pipeline.sh"
# Task-Datei existiert → ensure_task_file ist hier no-op (W-2 testet die Fehler-Etikettierung).
printf '# Task 50: demo\n' > "$TMP_W2/tasks/task-50-demo.md"
cat > "$TMP_W2/bin/gh" <<'GHEOF'
#!/bin/sh
case "$*" in
  *"issue edit"*) echo "$*" >> "$GH_LOG"; echo '{}' ;;                 # Mutation → mitloggen
  *"issue view"*) echo '{"labels":[{"name":"factory::running"}]}' ;;   # Flip-Verify-GET
  *'factory::run"'*) echo '[{"number":50}]' ;;                          # run-queue (nur run", nicht running")
  *) echo "[]" ;;
esac
GHEOF
chmod +x "$TMP_W2/bin/gh"
w2() { PATH="$TMP_W2/bin:$PATH" FACTORY_DIR="$TMP_W2" FACTORY_REPO=test/repo GH_LOG="$TMP_W2/mut.log" \
  bash "$TMP_W2/scripts/factory-poll.sh" >/dev/null 2>&1; }

# Kein Sentinel → echter Fehler → factory::failed
: > "$TMP_W2/mut.log"; w2
grep -q -- '--add-label factory::failed' "$TMP_W2/mut.log"
assert_true "$?" "W-2: Pipeline-Fehler ohne Sentinel → factory::failed"
# Sentinel da → Interrupt → factory::interrupted (nicht failed)
: > "$TMP_W2/mut.log"; echo "# INTERRUPT" > "$TMP_W2/tasks/INTERRUPT-50.md"; w2
grep -q -- '--add-label factory::interrupted' "$TMP_W2/mut.log"
assert_true "$?" "W-2: Pipeline-Stopp mit Sentinel → factory::interrupted"
grep -q -- '--add-label factory::failed' "$TMP_W2/mut.log"
assert_true "$([ $? -ne 0 ]; echo $?)" "W-2: Interrupt wird NICHT als failed fehletikettiert"
rm -rf "$TMP_W2"

# A (ADR-013, umgekehrte Richtung): factory-poll materialisiert die Task-Datei aus dem
# Issue, wenn sie fehlt – sonst bräche run-pipeline im Async-Pfad ab.
TMP_MAT="$(mktemp -d)"; mkdir -p "$TMP_MAT/scripts" "$TMP_MAT/tasks" "$TMP_MAT/bin"
cp "$SCRIPTS_DIR/factory-poll.sh" "$TMP_MAT/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$TMP_MAT/scripts/run-pipeline.sh"; chmod +x "$TMP_MAT/scripts/run-pipeline.sh"
git -C "$TMP_MAT" init -q
git -C "$TMP_MAT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cat > "$TMP_MAT/bin/gh" <<'GHEOF'
#!/bin/sh
case "$*" in
  *"issue edit"*) echo '{}' ;;
  *"issue view"*"title,body"*) echo '{"title":"Neues Feature","body":"Body-Text"}' ;;
  *"issue view"*) echo '{"labels":[{"name":"factory::running"}]}' ;;
  *'factory::run"'*) echo '[{"number":60}]' ;;
  *) echo "[]" ;;
esac
GHEOF
chmod +x "$TMP_MAT/bin/gh"
PATH="$TMP_MAT/bin:$PATH" FACTORY_DIR="$TMP_MAT" FACTORY_REPO=test/repo \
  bash "$TMP_MAT/scripts/factory-poll.sh" >/dev/null 2>&1
matfile=$(find "$TMP_MAT/tasks" -name 'task-60-*.md' | head -1)
assert_true "$([[ -n "$matfile" ]]; echo $?)" "A: factory-poll materialisiert Task-Datei aus Issue #60 (Issue→Task)"
grep -q 'Neues Feature' "$matfile" 2>/dev/null
assert_true "$?" "A: materialisierte Task-Datei übernimmt den Issue-Titel"
rm -rf "$TMP_MAT"

# ─── Issue-Sync: jeder Task hat ein GitHub-Issue-Pendant (#4, ADR-013) ───────
echo ""
echo "Issue-Sync (#4, ADR-013):"

assert_true "$([[ -f "$FACTORY_ROOT/scripts/sync-issues.sh" ]]; echo $?)" "scripts/sync-issues.sh vorhanden"
assert_true "$([[ -x "$FACTORY_ROOT/scripts/sync-issues.sh" ]]; echo $?)" "sync-issues.sh ist ausführbar"
# CI-Gate: Invariante wird im factory-ci.yml geprüft
grep -q 'issue-sync:' "$CI_FILE"; assert_true "$?" "issue-sync-Job in factory-ci.yml"
grep -q 'sync-issues.sh --check' "$CI_FILE"; assert_true "$?" "CI ruft sync-issues.sh --check (read-only Gate)"

# Verhalten gegen gemocktes gh (kein echtes GitHub nötig).
# gh issue view <id> → exit 1 für IDs in FAKE_MISSING (Issue fehlt), sonst 0.
# gh issue create     → gibt eine Issue-URL mit FAKE_NEWNUM aus.
TMP_SYNC="$(mktemp -d)"; mkdir -p "$TMP_SYNC/scripts/lib" "$TMP_SYNC/tasks" "$TMP_SYNC/bin"
cp "$SCRIPTS_DIR/sync-issues.sh" "$TMP_SYNC/scripts/"
cp "$SCRIPTS_DIR/lib/create-issue.sh" "$TMP_SYNC/scripts/lib/"   # Seam (ADR-018) neben dem Skript
printf '# Task 1: alpha\n' > "$TMP_SYNC/tasks/task-1-alpha.md"
printf '# Task 2: beta\n'  > "$TMP_SYNC/tasks/task-2-beta.md"
cat > "$TMP_SYNC/bin/gh" <<'GHEOF'
#!/bin/sh
if [ "$1 $2" = "issue view" ]; then
  for m in ${FAKE_MISSING:-}; do [ "$3" = "$m" ] && exit 1; done
  echo "{\"number\":$3}"; exit 0
fi
if [ "$1 $2" = "issue create" ]; then
  echo "https://github.com/test/repo/issues/${FAKE_NEWNUM:-999}"; exit 0
fi
exit 0
GHEOF
chmod +x "$TMP_SYNC/bin/gh"
sync() { PATH="$TMP_SYNC/bin:$PATH" FACTORY_DIR="$TMP_SYNC" FACTORY_REPO=test/repo \
  bash "$TMP_SYNC/scripts/sync-issues.sh" "$@" 2>&1; }

# 1. Alle Tasks haben ein Issue → --check exit 0
FAKE_MISSING="" sync --check >/dev/null 2>&1; assert_exit 0 "$?" "--check: alle Tasks synchron → exit 0"
# 2. Task #1 ohne Issue → --check exit 1 + Drift-Meldung
out=$(FAKE_MISSING="1" sync --check); rc=$?
assert_exit 1 "$rc" "--check: Task ohne Issue → exit 1"
printf '%s' "$out" | grep -q 'DRIFT'; assert_true "$?" "--check meldet DRIFT bei fehlendem Issue"
printf '%s' "$out" | grep -q 'Task #1'; assert_true "$?" "--check benennt den betroffenen Task (#1)"
# 3. --create --dry-run → keine Mutation, exit 0
out=$(FAKE_MISSING="1" sync --create --dry-run); rc=$?
assert_exit 0 "$rc" "--create --dry-run → exit 0 (keine Mutation)"
printf '%s' "$out" | grep -q 'dry-run.*Task #1'; assert_true "$?" "--dry-run zeigt geplante Issue-Anlage"
# 4. --create mit passender Nummer → exit 0
FAKE_MISSING="1" FAKE_NEWNUM="1" sync --create >/dev/null 2>&1
assert_exit 0 "$?" "--create: neue Issue-Nummer == Task-ID → exit 0"
# 5. --create mit Nummern-Mismatch (GitHub vergibt andere Nummer) → exit 1 + MISMATCH
out=$(FAKE_MISSING="1" FAKE_NEWNUM="7" sync --create); rc=$?
assert_exit 1 "$rc" "--create: Nummern-Mismatch → exit 1"
printf '%s' "$out" | grep -q 'MISMATCH'; assert_true "$?" "--create meldet MISMATCH bei nicht auflösbarer Nummer"
rm -rf "$TMP_SYNC"

# ─── Zentraler Issue-Seam scripts/lib/create-issue.sh (#82, ADR-018) ─────────
echo ""
echo "Zentraler Issue-Seam (#82, ADR-018):"

SEAM_LIB="$SCRIPTS_DIR/lib/create-issue.sh"
assert_true "$([[ -f "$SEAM_LIB" ]]; echo $?)" "scripts/lib/create-issue.sh vorhanden"

TMP_SEAM="$(mktemp -d)"; mkdir -p "$TMP_SEAM/bin"
# gh-Stub: 'issue create' protokolliert Args nach GH_LOG und schlägt fehl, wenn ein
# --label-Wert FAKE_BAD_LABEL entspricht (simuliert „Label existiert im Repo nicht").
# FAKE_FAIL_ALL=1 lässt jede Anlage scheitern (fail-closed-Test).
cat > "$TMP_SEAM/bin/gh" <<'GHEOF'
#!/bin/sh
if [ "$1 $2" = "issue create" ]; then
  [ -n "${GH_LOG:-}" ] && printf '%s\n' "$*" >> "$GH_LOG"
  [ -n "${FAKE_FAIL_ALL:-}" ] && exit 1
  if [ -n "${FAKE_BAD_LABEL:-}" ]; then
    for w in "$@"; do [ "$w" = "$FAKE_BAD_LABEL" ] && exit 1; done
  fi
  echo "https://github.com/test/repo/issues/${FAKE_NUM:-123}"
  exit 0
fi
exit 0
GHEOF
chmod +x "$TMP_SEAM/bin/gh"

# seam <args…> – ruft create_issue im Subshell mit Stub-gh auf ($0=Lib, $@=create_issue-Args).
# FAKE_*/GH_LOG kommen als Prefix-Env vom Aufrufer und werden an den Subshell durchgereicht.
seam() {
  PATH="$TMP_SEAM/bin:$PATH" FACTORY_REPO="test/repo" \
    bash -c 'source "$0"; create_issue "$@"' "$SEAM_LIB" "$@"
}

# 1. Art-Label → reine Issue-Nummer auf stdout (Exit 0)
LOG="$TMP_SEAM/c1.log"; : > "$LOG"
out=$(GH_LOG="$LOG" seam "Titel" "Body" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "Seam: create_issue mit Art-Label → exit 0"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: stdout ist die reine Issue-Nummer (123)"
grep -q -- '--label enhancement' "$LOG"; assert_true "$?" "Seam: Art-Label wird an gh übergeben"

# 2. Aspekt-CSV → Art + beide Aspekt-Labels, stdout bleibt reine Nummer
LOG="$TMP_SEAM/c2.log"; : > "$LOG"
out=$(GH_LOG="$LOG" seam "T" "B" "enhancement" "security,tech-debt" 2>/dev/null)
{ grep -q -- '--label enhancement' "$LOG" && grep -q -- '--label security' "$LOG" \
  && grep -q -- '--label tech-debt' "$LOG"; }
assert_true "$?" "Seam: Aspekt-CSV wird zu Art + beiden Aspekt-Labels"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: stdout bleibt reine Nummer trotz Aspekt-Labels"

# 3. fehlendes Aspekt-Label → Degradation auf Art-Label, Warnung auf stderr, Issue trotzdem
LOG="$TMP_SEAM/c3.log"; : > "$LOG"; ERR="$TMP_SEAM/c3.err"
out=$(FAKE_BAD_LABEL="tech-debt" GH_LOG="$LOG" seam "T" "B" "enhancement" "tech-debt" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "Seam: fehlendes Aspekt-Label → Issue trotzdem angelegt (exit 0)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: fehlendes Aspekt-Label verunreinigt stdout nicht"
grep -q 'tech-debt' "$ERR"; assert_true "$?" "Seam: stderr-Warnung nennt das weggefallene Aspekt-Label"
tail -n1 "$LOG" | grep -q -- '--label enhancement'; assert_true "$?" "Seam: Fallback-Anlage trägt das Art-Label"
assert_true "$(! tail -n1 "$LOG" | grep -q -- 'tech-debt'; echo $?)" "Seam: Fallback-Anlage trägt das fehlende Aspekt-Label NICHT mehr"

# 4. fehlendes Art-Label → Degradation ganz ohne Label, Issue trotzdem
LOG="$TMP_SEAM/c4.log"; : > "$LOG"
out=$(FAKE_BAD_LABEL="enhancement" GH_LOG="$LOG" seam "T" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "Seam: fehlendes Art-Label → Issue ohne Label angelegt (exit 0)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: fehlendes Art-Label → stdout bleibt reine Nummer"
assert_true "$(! tail -n1 "$LOG" | grep -q -- '--label'; echo $?)" "Seam: finale Anlage ganz ohne --label"

# 5. gar keine Issue-Nummer → fail-closed (Exit ≠ 0, kein stdout)
out=$(FAKE_FAIL_ALL=1 seam "T" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 1 "$rc" "Seam: gh liefert keine Nummer → fail-closed (exit 1)"
assert_true "$([[ -z "$out" ]]; echo $?)" "Seam: fail-closed → keine Nummer auf stdout"

# 6. Repo-Bezug: FACTORY_REPO → --repo; ohne Slug kein --repo (gh-Auto-Erkennung).
# Regression F1 (Review #82): der no-repo-Pfad MUSS auch unter `set -euo pipefail` laufen –
# `repo_args` ist dort leer, und nounset gilt auch innerhalb von $(create_issue …).
LOG="$TMP_SEAM/c6.log"; : > "$LOG"
GH_LOG="$LOG" seam "T" "B" "enhancement" >/dev/null 2>&1
grep -q -- '--repo test/repo' "$LOG"; assert_true "$?" "Seam: FACTORY_REPO wird als --repo übergeben"
LOG="$TMP_SEAM/c6b.log"; : > "$LOG"
out=$(PATH="$TMP_SEAM/bin:$PATH" GH_LOG="$LOG" \
  bash -c 'set -euo pipefail; unset FACTORY_REPO REPO GITHUB_REPOSITORY; source "$0"; create_issue "T" "B" "enhancement"' \
  "$SEAM_LIB" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "Seam: no-repo unter set -euo pipefail → exit 0 (F1-Regression, kein unbound var)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: no-repo liefert die Nummer (nicht am leeren repo_args gestorben)"
assert_true "$(! grep -q -- '--repo' "$LOG"; echo $?)" "Seam: ohne FACTORY_REPO/REPO kein --repo (gh-Auto)"

# 7. Regression R3#1: bloßer (nicht via $()' gefangener) Aufruf unter set -euo pipefail –
# die Degradation muss trotz fehlendem Aspekt-Label durchlaufen (errexit darf sie nicht killen).
LOG="$TMP_SEAM/c7.log"; : > "$LOG"
rc=$(PATH="$TMP_SEAM/bin:$PATH" FACTORY_REPO="test/repo" FAKE_BAD_LABEL="tech-debt" GH_LOG="$LOG" \
  bash -c 'set -euo pipefail; source "$0"; create_issue "T" "B" "enhancement" "tech-debt" >/dev/null; echo "$?"' \
  "$SEAM_LIB" 2>/dev/null)
assert_true "$([[ "$rc" = "0" ]]; echo $?)" "Seam: bare-Aufruf unter set -e → Degradation läuft durch (rc=0)"
tail -n1 "$LOG" | grep -q -- '--label enhancement'; assert_true "$?" "Seam: bare-Aufruf legt via Fallback mit Art-Label an"

# 8. Aspekt-CSV mit Leerfeldern → exakt Art + 2 Aspekt-Labels (Leerfeld übersprungen, kein Leer-Label)
LOG="$TMP_SEAM/c8.log"; : > "$LOG"
out=$(GH_LOG="$LOG" seam "T" "B" "enhancement" "security,,tech-debt" 2>/dev/null)
n_labels=$(tail -n1 "$LOG" | grep -oE -- '--label' | wc -l | tr -d ' ')
assert_true "$([[ "$n_labels" = "3" ]]; echo $?)" "Seam: Leerfeld-CSV → genau 3 --label (Art + 2 Aspekte, kein Leer-Label)"
{ grep -q -- '--label security' "$LOG" && grep -q -- '--label tech-debt' "$LOG"; }
assert_true "$?" "Seam: Leerfeld-CSV behält beide echten Aspekt-Labels"

# 9. Mehr-Aspekt-Degradation: eines von zwei Aspekt-Labels fehlt → Fallback auf nur Art-Label
LOG="$TMP_SEAM/c9.log"; : > "$LOG"
out=$(FAKE_BAD_LABEL="tech-debt" GH_LOG="$LOG" seam "T" "B" "enhancement" "security,tech-debt" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "Seam: ein fehlendes von zwei Aspekt-Labels → Issue trotzdem (exit 0)"
tail -n1 "$LOG" | grep -q -- '--label enhancement'; assert_true "$?" "Seam: Mehr-Aspekt-Fallback trägt das Art-Label"
assert_true "$(! tail -n1 "$LOG" | grep -qE -- '--label (security|tech-debt)'; echo $?)" \
  "Seam: Mehr-Aspekt-Fallback lässt BEIDE Aspekt-Labels weg (Stufe 2 = nur Art)"

# 10. leeres Art-Label (FS2 „leeres Art-Label") → fail-open: Issue OHNE Label, Warnung auf
# stderr, stdout bleibt reine Nummer. Eigener Code-Pfad (Warn-Branch + übersprungene Stufe 1/2),
# NICHT identisch zu Test 4 (dort ist das Art-Label nicht-leer, aber von gh abgelehnt).
LOG="$TMP_SEAM/c10.log"; : > "$LOG"; ERR="$TMP_SEAM/c10.err"
out=$(GH_LOG="$LOG" seam "T" "B" "" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "Seam: leeres Art-Label → Issue trotzdem angelegt (exit 0, FS2)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: leeres Art-Label → stdout bleibt reine Nummer"
assert_true "$(! grep -q -- '--label' "$LOG"; echo $?)" "Seam: leeres Art-Label → Anlage ganz ohne --label"
grep -q 'kein Art-Label' "$ERR"; assert_true "$?" "Seam: leeres Art-Label → Warnung auf stderr (kein Art-Label)"

# 11. 'gh' nicht installiert (FS1) → fail-closed: exit ≠ 0, keine Nummer auf stdout, klare
# stderr-Meldung. Isolation: leerer PATH (nur der gh-Check läuft, vor jedem externen Kommando –
# create_issue nutzt bis dorthin ausschließlich Shell-Builtins).
mkdir -p "$TMP_SEAM/empty"
ERR="$TMP_SEAM/c11.err"
# bash absolut aufrufen (via env), damit der leere PATH nur den gh-Lookup trifft, nicht bash selbst.
out=$(env PATH="$TMP_SEAM/empty" "$(command -v bash)" -c 'source "$0"; create_issue "T" "B" "enhancement"' "$SEAM_LIB" 2>"$ERR"); rc=$?
assert_exit 1 "$rc" "Seam: fehlendes gh → fail-closed (exit 1, FS1)"
assert_true "$([[ -z "$out" ]]; echo $?)" "Seam: fehlendes gh → keine Nummer auf stdout"
grep -qi 'gh' "$ERR"; assert_true "$?" "Seam: fehlendes gh → klare stderr-Meldung nennt gh"

# 12. Titel/Body mit Sonderzeichen (Leerzeichen, Anführungszeichen) → landen unversehrt als
# GENAU EIN --title/--body-Argument (kein Word-Splitting). Der Standard-Stub loggt '$*'
# (fusioniert Wörter) → hier ein Stub, der jedes Argument einzeln bracket-loggt, damit
# Argument-Grenzen sichtbar werden.
BR="$TMP_SEAM/brk"; mkdir -p "$BR"
cat > "$BR/gh" <<'GHEOF'
#!/bin/sh
if [ "$1 $2" = "issue create" ]; then
  shift 2
  for a in "$@"; do printf '[%s]\n' "$a" >> "$GH_LOG"; done
  echo "https://github.com/test/repo/issues/123"; exit 0
fi
exit 0
GHEOF
chmod +x "$BR/gh"
BRLOG="$BR/args.log"; : > "$BRLOG"
PATH="$BR:$PATH" FACTORY_REPO="test/repo" GH_LOG="$BRLOG" \
  bash -c 'source "$0"; create_issue "$@"' "$SEAM_LIB" \
  'Titel mit Leerzeichen und "Quotes"' 'Body mit Leer und "Quote"' 'enhancement' >/dev/null 2>&1
grep -qxF -- '[Titel mit Leerzeichen und "Quotes"]' "$BRLOG"
assert_true "$?" "Seam: Titel mit Leerzeichen/Quotes bleibt EIN --title-Argument (kein Word-Splitting)"
grep -qxF -- '[Body mit Leer und "Quote"]' "$BRLOG"
assert_true "$?" "Seam: Body mit Leerzeichen/Quotes bleibt EIN --body-Argument"
# Negativ-Kontrolle (Schärfe): ein wortgesplittetes Titel-Fragment darf NICHT als eigene Zeile stehen.
assert_true "$(! grep -qxF -- '[Titel]' "$BRLOG"; echo $?)" \
  "Seam: kein wortgesplittetes Titel-Fragment ([Titel] allein) im Arg-Log"

# 13. Security-Guard (Review #82 H-1): reservierter 'factory::'-Präfix wird als Art- UND
# Aspekt-Label verworfen (nur die Pipeline setzt diese; verhindert Selbst-Trigger).
LOG="$TMP_SEAM/c13.log"; : > "$LOG"; ERR="$TMP_SEAM/c13.err"
out=$(FACTORY_REPO="test/repo" GH_LOG="$LOG" seam "T" "B" "factory::run" "security,factory::running" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "Seam: factory::-Labels → Issue trotzdem angelegt (exit 0)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: factory::-Guard → stdout bleibt reine Nummer"
assert_true "$(! grep -q -- 'factory::' "$LOG"; echo $?)" "Seam: KEIN factory::-Label wird an gh übergeben (Art + Aspekt verworfen)"
grep -q -- '--label security' "$LOG"; assert_true "$?" "Seam: legitimes Aspekt-Label (security) bleibt trotz factory::-Nachbar erhalten"
grep -q 'reserviert' "$ERR"; assert_true "$?" "Seam: factory::-Guard warnt auf stderr (reserviert)"

rm -rf "$TMP_SEAM"

# ── Aufrufer nutzen den Seam (kein eigenes 'gh issue create' mehr) ───────────
assert_true "$(! grep -qE 'gh issue create' "$SCRIPTS_DIR/start-work.sh"; echo $?)" \
  "#82: start-work.sh enthält kein eigenes 'gh issue create' mehr (nutzt Seam)"
assert_true "$(! grep -qE 'gh issue create' "$SCRIPTS_DIR/sync-issues.sh"; echo $?)" \
  "#82: sync-issues.sh enthält kein eigenes 'gh issue create' mehr (nutzt Seam)"

# ── sync-issues legt über den Seam mit Art-Label 'enhancement' an ────────────
TMP_SYNC2="$(mktemp -d)"; mkdir -p "$TMP_SYNC2/scripts/lib" "$TMP_SYNC2/tasks" "$TMP_SYNC2/bin"
cp "$SCRIPTS_DIR/sync-issues.sh" "$TMP_SYNC2/scripts/"
cp "$SCRIPTS_DIR/lib/create-issue.sh" "$TMP_SYNC2/scripts/lib/"
printf '# Task 1: alpha\n' > "$TMP_SYNC2/tasks/task-1-alpha.md"
cat > "$TMP_SYNC2/bin/gh" <<'GHEOF'
#!/bin/sh
[ "$1 $2" = "issue view" ] && exit 1                      # Issue fehlt → Drift
if [ "$1 $2" = "issue create" ]; then
  [ -n "${GH_LOG:-}" ] && printf '%s\n' "$*" >> "$GH_LOG"
  echo "https://github.com/test/repo/issues/1"; exit 0
fi
exit 0
GHEOF
chmod +x "$TMP_SYNC2/bin/gh"
: > "$TMP_SYNC2/create.log"
PATH="$TMP_SYNC2/bin:$PATH" FACTORY_DIR="$TMP_SYNC2" FACTORY_REPO=test/repo GH_LOG="$TMP_SYNC2/create.log" \
  bash "$TMP_SYNC2/scripts/sync-issues.sh" --create >/dev/null 2>&1
grep -q -- '--label enhancement' "$TMP_SYNC2/create.log"
assert_true "$?" "#82: sync-issues --create legt Issue mit Art-Label enhancement an (kein label-loses Issue)"
# FACTORY_ISSUE_LABEL übersteuert den enhancement-Default auch in sync-issues.
: > "$TMP_SYNC2/create.log"
PATH="$TMP_SYNC2/bin:$PATH" FACTORY_DIR="$TMP_SYNC2" FACTORY_REPO=test/repo \
  FACTORY_ISSUE_LABEL=bug GH_LOG="$TMP_SYNC2/create.log" \
  bash "$TMP_SYNC2/scripts/sync-issues.sh" --create >/dev/null 2>&1
grep -q -- '--label bug' "$TMP_SYNC2/create.log"
assert_true "$?" "#82: sync-issues respektiert FACTORY_ISSUE_LABEL-Override (bug statt enhancement)"
rm -rf "$TMP_SYNC2"

# ── FS1 (Aufrufer): ohne 'gh' verhält sich sync-issues wie heute → Exit 2 (Umgebungsfehler) ──
# Der gh-Check greift vor dem Sourcen des Seams; leerer PATH isoliert den Fall (FACTORY_DIR
# gesetzt → keine dirname/pwd-Auflösung nötig, kein externes Kommando vor dem Check).
TMP_NOGH="$(mktemp -d)"; mkdir -p "$TMP_NOGH/empty" "$TMP_NOGH/tasks"
# bash absolut (via env): der leere PATH soll nur den gh-Lookup treffen, nicht bash selbst.
env PATH="$TMP_NOGH/empty" FACTORY_DIR="$TMP_NOGH" FACTORY_REPO="test/repo" \
  "$(command -v bash)" "$SCRIPTS_DIR/sync-issues.sh" --check >/dev/null 2>&1
assert_exit 2 "$?" "#82/FS1: sync-issues ohne gh → exit 2 (Umgebungsfehler, wie heute)"
rm -rf "$TMP_NOGH"

# ── Skill-Doku weist den autonomen create_issue-Aufruf an (ADR-018 §5) ───────
for sk in codify review security-review; do
  grep -q 'create_issue' "$FACTORY_ROOT/.claude/commands/$sk.md"
  assert_true "$?" "#82: /$sk-Skill-Doku weist den create_issue-Aufruf an"
done

# ── git-workflow.md nennt den Seam als kanonischen Anlage-Weg ────────────────
grep -q 'create-issue.sh' "$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md"
assert_true "$?" "#82: git-workflow.md verweist auf den zentralen Seam (create-issue.sh)"

# ── #155: git-workflow.md verweist auf ADR-029 (server-seitiger main-Schutz) ──
# AC3 bündelt Direktive + Rationale auf getrennt editierbaren Zeilen → je eigene
# Assertion (codifizierte #117-Regel), sonst bleibt das Framing ungetestet.
GITWF="$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md"
# (0) Verweis-Ziel existiert: sonst zeigen die ADR-029-Verweise ins Leere, ohne dass
# die grep-Guards (die nur git-workflow.md prüfen) das bemerken (dangling reference).
assert_true "$([[ -f "$FACTORY_ROOT/docs/adr/029-branch-protection-main-ruleset.md" ]]; echo $?)" \
  "#155: ADR-029-Datei vorhanden (Verweis-Ziel nicht dangling)"
# (a) Direktive: der Verweis auf ADR-029 ist vorhanden.
grep -q 'ADR-029' "$GITWF"
assert_true "$?" "#155: git-workflow.md verweist auf ADR-029 (main-Ruleset)"
# (b) Rationale (separierbar): der pre-push-Hook ist als lokales, *umgehbares* Feedback
# eingeordnet – die Begründung, warum server-seitige Durchsetzung nötig ist. Token
# 'umgehbar' steht nur im Framing-Satz, unabhängig vom Verweis-Satz (ADR-029).
grep -q 'umgehbar' "$GITWF"
assert_true "$?" "#155: git-workflow.md ordnet den pre-push-Hook als umgehbares lokales Feedback ein (AC3-Rationale)"

# ─── Bug #8: Check-Skripte robust gegen Leerzeichen im Pfad ──────────────────
echo ""
echo "Bug #8 (Leerzeichen im Pfad):"

# completion-check.sh berechnet FACTORY_DIR aus dem eigenen Ort → Skript in einen
# Pfad MIT Leerzeichen kopieren und dort ausführen (reproduziert den Original-Bug).
TMP_CC="$(mktemp -d)"; CC_SP="$TMP_CC/has space"
mkdir -p "$CC_SP/scripts/checks" "$CC_SP/tasks"
cp "$CHECKS_DIR/completion-check.sh" "$CC_SP/scripts/checks/"
printf '# Task 1: demo\n- [ ] offen\n' > "$CC_SP/tasks/task-1-demo.md"
cc_out=$(bash "$CC_SP/scripts/checks/completion-check.sh" 2>&1); cc_rc=$?
assert_exit 0 "$cc_rc" "completion-check: exit 0 bei Leerzeichen im Pfad"
printf '%s' "$cc_out" | grep -q 'No such file or directory'
assert_true "$([ $? -ne 0 ]; echo $?)" "completion-check: kein grep-Fehler bei Leerzeichen (Bug #8)"
printf '%s' "$cc_out" | grep -qF 'task-1-demo.md'
assert_true "$?" "completion-check: nennt Task-Datei trotz Leerzeichen im Pfad"
rm -rf "$TMP_CC"

# sync-issues.sh liest FACTORY_DIR aus der Env → Leerzeichen-Pfad + fehlendes Issue.
# gemocktes gh: `issue view` → exit 1 (Issue fehlt) → Task driftet → --create liest Titel aus Datei.
TMP_SS2="$(mktemp -d)"; SS_SP="$TMP_SS2/has space"
mkdir -p "$SS_SP/tasks" "$SS_SP/bin"
printf '# Task 1: alpha\n' > "$SS_SP/tasks/task-1-alpha.md"
printf '#!/bin/sh\n[ "$1 $2" = "issue view" ] && exit 1\nexit 0\n' > "$SS_SP/bin/gh"
chmod +x "$SS_SP/bin/gh"
ss_out=$(PATH="$SS_SP/bin:$PATH" FACTORY_DIR="$SS_SP" FACTORY_REPO=test/repo \
  bash "$SCRIPTS_DIR/sync-issues.sh" --create --dry-run 2>&1); ss_rc=$?
assert_exit 0 "$ss_rc" "sync-issues --create --dry-run: exit 0 bei Leerzeichen im Pfad"
printf '%s' "$ss_out" | grep -q 'No such file or directory'
assert_true "$([ $? -ne 0 ]; echo $?)" "sync-issues: kein Datei-Fehler bei Leerzeichen (Bug #8)"
printf '%s' "$ss_out" | grep -qF 'Task #1'
assert_true "$?" "sync-issues: liest Titel aus Datei trotz Leerzeichen im Pfad"
rm -rf "$TMP_SS2"

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
  TMP_CFG="$(mktemp -d)"; mkdir -p "$TMP_CFG/scripts/checks" "$TMP_CFG/scripts/lib" "$TMP_CFG/tasks" "$TMP_CFG/docs/factory"
  cp "$PIPELINE" "$TMP_CFG/scripts/"; cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_CFG/scripts/checks/"; cp "$DEFAULTS" "$TMP_CFG/"
  cp "$SCRIPTS_DIR/lib/report-verdict.sh" "$TMP_CFG/scripts/lib/"  # run-pipeline sourct sie (Task 91, ADR-019 §4)
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

  # #91 Turn-Budget-Dry-Run: review + security-review zeigen max 14 turns im Output (AC Lücke 2).
  # Bestehender mock review-2.md (APPROVED) sorgt dafür, dass Review-Loop sofort endet und
  # die Pipeline bis Phase 5 (security-review) läuft – beide "Starte:"-Zeilen erscheinen.
  TMP_DRY91="$(mktemp -d)"; mkdir -p "$TMP_DRY91/scripts/checks" "$TMP_DRY91/scripts/lib" "$TMP_DRY91/tasks" "$TMP_DRY91/docs/factory"
  cp "$PIPELINE" "$TMP_DRY91/scripts/"; cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_DRY91/scripts/checks/"; cp "$DEFAULTS" "$TMP_DRY91/"
  cp "$SCRIPTS_DIR/lib/report-verdict.sh" "$TMP_DRY91/scripts/lib/"
  echo "# ctx" > "$TMP_DRY91/docs/factory/PROJECT-CONTEXT.md"
  echo "# Task 2: budget-dry" > "$TMP_DRY91/tasks/task-2-budget-dry.md"
  printf 'VERDICT: APPROVED\n' > "$TMP_DRY91/tasks/review-2.md"
  git -C "$TMP_DRY91" init -q; git -C "$TMP_DRY91" add .
  git -C "$TMP_DRY91" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  dry91_out=$(bash "$TMP_DRY91/scripts/run-pipeline.sh" 2 --dry-run 2>&1 || true)
  printf '%s' "$dry91_out" | grep -q '/review 2 (model: claude-opus-4-8, max 14 turns)'
  assert_true "$?" "#91: dry-run zeigt /review mit max 14 turns (Turn-Budget, Lücke 2)"
  printf '%s' "$dry91_out" | grep -q '/security-review 2 (model: claude-opus-4-8, max 14 turns)'
  assert_true "$?" "#91: dry-run zeigt /security-review mit max 14 turns (Turn-Budget, Lücke 2)"
  rm -rf "$TMP_DRY91"
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

# ─── start-work.sh: Worktree-Isolation (Kern-Vorkehrung gegen Session-Kollisionen, #74) ──
echo "start-work.sh (Worktree-Isolation, #74):"

SW="$CHECKS_DIR/../start-work.sh"   # scripts/start-work.sh
TMP_SW="$(mktemp -d)"

# gh-Stub auf PATH: ID-Modus-Issue-Check bestätigen, ohne Netzwerk/echtes Repo
# (etabliertes Muster aus den factory-poll-Tests). Determinismus in jeder Umgebung.
mkdir -p "$TMP_SW/bin"
cat > "$TMP_SW/bin/gh" << 'GHSTUB'
#!/usr/bin/env bash
# issue create: Argumente (v. a. --label) protokollieren + Fake-URL liefern, damit
# die Task-ID extrahierbar ist. ID-Modus ruft "issue create" nie auf → bestehende
# Worktree-Isolationstests bleiben unberührt.
case "$1 $2" in
  "issue create")
    [ -n "${GH_LOG:-}" ] && printf '%s\n' "$*" >> "$GH_LOG"
    echo "https://github.com/acme/demo/issues/901" ;;
  "issue view") exit 0 ;;
  "pr create")  exit 0 ;;
  *)            exit 0 ;;
esac
GHSTUB
chmod +x "$TMP_SW/bin/gh"

# Wegwerf-Repo als "geteilter Haupt-Arbeitsbaum".
REPO_SW="$TMP_SW/repo"
mkdir -p "$REPO_SW"
git -C "$REPO_SW" init -q -b main >/dev/null 2>&1
git -C "$REPO_SW" config user.email t@t
git -C "$REPO_SW" config user.name t
git -C "$REPO_SW" commit -q --allow-empty -m init
MAIN_HEAD_BEFORE=$(git -C "$REPO_SW" rev-parse HEAD)

# start-work im Worktree-Default (offline: kein Remote → fetch best-effort, Basis lokaler main).
( cd "$REPO_SW" && PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
    FACTORY_WORKTREE_BASE="$TMP_SW/wt" FACTORY_WT_SKIP_INSTALL=1 \
    bash "$SW" 777 demo-x ) >/dev/null 2>&1
assert_exit 0 "$?" "start-work (Worktree-Default) → exit 0"

WORKDIR_SW="$TMP_SW/wt/feature-777-demo-x"

# Kern-Invariante: der geteilte Haupt-Baum-HEAD bleibt unverändert (kein checkout/Hijack).
{ [ "$(git -C "$REPO_SW" rev-parse --abbrev-ref HEAD)" = "main" ] \
  && [ "$(git -C "$REPO_SW" rev-parse HEAD)" = "$MAIN_HEAD_BEFORE" ]; }
assert_true "$?" "Worktree-Modus lässt den Haupt-Baum-HEAD unverändert (main)"

[ -f "$WORKDIR_SW/tasks/task-777-demo-x.md" ]
assert_true "$?" "Task-Datei liegt im isolierten Worktree"

[ ! -f "$REPO_SW/tasks/task-777-demo-x.md" ]
assert_true "$?" "Task-Datei NICHT im Haupt-Baum (echte Isolation)"

[ "$(git -C "$WORKDIR_SW" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "feature/777-demo-x" ]
assert_true "$?" "Worktree ist auf dem Feature-Branch ausgecheckt"

# In-Place-Fallback (FACTORY_NO_WORKTREE=1) branchet im Haupt-Baum selbst. Braucht einen
# Remote (pull --rebase) → Bare-Remote spendieren.
BARE_IP="$TMP_SW/bare.git"
git init -q --bare -b main "$BARE_IP" >/dev/null 2>&1
REPO_IP="$TMP_SW/repo-ip"
git clone -q "$BARE_IP" "$REPO_IP" >/dev/null 2>&1
git -C "$REPO_IP" config user.email t@t
git -C "$REPO_IP" config user.name t
git -C "$REPO_IP" commit -q --allow-empty -m init
git -C "$REPO_IP" push -q -u origin main >/dev/null 2>&1
( cd "$REPO_IP" && PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_IP" FACTORY_REPO="acme/demo" FACTORY_NO_WORKTREE=1 \
    bash "$SW" 778 demo-y ) >/dev/null 2>&1
[ "$(git -C "$REPO_IP" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "feature/778-demo-y" ]
assert_true "$?" "In-Place-Modus (FACTORY_NO_WORKTREE=1) branchet im Haupt-Baum"

# ─── Art-Label bei der Issue-Anlage aus dem Branch-Typ ableiten (#80) ─────────
# Beschreibungs-Modus (Issue-first): der gh-Stub protokolliert die 'issue create'-Args;
# geprüft wird, dass genau das erwartete Art-Label übergeben wird.
run_create_label() {  # $1 = branch-typ, $2 = desc, $3 = extra-env ("VAR=val" oder "")
  local log="$TMP_SW/gh-$2.log"; : > "$log"
  ( cd "$REPO_SW" && env $3 GH_LOG="$log" PATH="$TMP_SW/bin:$PATH" \
      FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
      FACTORY_WORKTREE_BASE="$TMP_SW/wt-lbl" FACTORY_WT_SKIP_INSTALL=1 \
      bash "$SW" "$2" "$1" ) >/dev/null 2>&1
  cat "$log"
}

run_create_label fix aaa "" | grep -q -- "--label bug"
assert_true "$?" "Issue-Anlage: Branch-Typ fix → --label bug"

run_create_label feature bbb "" | grep -q -- "--label enhancement"
assert_true "$?" "Issue-Anlage: Branch-Typ feature → --label enhancement"

run_create_label docs ccc "" | grep -q -- "--label documentation"
assert_true "$?" "Issue-Anlage: Branch-Typ docs → --label documentation"

run_create_label feature ddd "FACTORY_ISSUE_LABEL=security" | grep -q -- "--label security"
assert_true "$?" "Issue-Anlage: FACTORY_ISSUE_LABEL übersteuert die Ableitung"

# #82: --labels reicht Aspekt-Labels (zusätzlich zum Art-Label) an den Seam durch.
LOG_ASP="$TMP_SW/gh-asp.log"; : > "$LOG_ASP"
( cd "$REPO_SW" && env GH_LOG="$LOG_ASP" PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
    FACTORY_WORKTREE_BASE="$TMP_SW/wt-asp" FACTORY_WT_SKIP_INSTALL=1 \
    bash "$SW" eee feature --labels security,test ) >/dev/null 2>&1
{ grep -q -- '--label enhancement' "$LOG_ASP" && grep -q -- '--label security' "$LOG_ASP" \
  && grep -q -- '--label test' "$LOG_ASP"; }
assert_true "$?" "#82: start-work --labels reicht Aspekt-Labels an den Seam durch (Art + Aspekte)"

# #82: FACTORY_ASPECT_LABELS wirkt wie --labels (Env-Variante).
LOG_ENV="$TMP_SW/gh-env.log"; : > "$LOG_ENV"
( cd "$REPO_SW" && env GH_LOG="$LOG_ENV" PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" FACTORY_ASPECT_LABELS="security" \
    FACTORY_WORKTREE_BASE="$TMP_SW/wt-env" FACTORY_WT_SKIP_INSTALL=1 \
    bash "$SW" fff feature ) >/dev/null 2>&1
grep -q -- '--label security' "$LOG_ENV"
assert_true "$?" "#82: FACTORY_ASPECT_LABELS reicht Aspekt-Labels an den Seam durch"

# #82 (F2-Regression): --labels als letztes Argument ohne Wert → klare usage()-Meldung + exit 1,
# kein wortloser Abbruch durch 'shift 2' unter set -e.
asp_err=$( cd "$REPO_SW" && PATH="$TMP_SW/bin:$PATH" FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
  bash "$SW" "meine beschreibung" --labels 2>&1 ); asp_rc=$?
assert_exit 1 "$asp_rc" "#82: start-work --labels ohne Wert → exit 1 (kein wortloser set-e-Abbruch)"
printf '%s' "$asp_err" | grep -q -- '--labels erwartet einen Wert'
assert_true "$?" "#82: start-work --labels ohne Wert nennt die usage()-Ursache"

rm -rf "$TMP_SW"

# ─── #66: Deploy-Gate liest Secrets über env:, nicht inline im run: ──────────
echo ""
echo "#66 Härtung – Secret-Prüfung im Deploy-Gate (env: statt inline \${{ secrets.* }}):"

DEPLOY_GATE="$FACTORY_ROOT/.github/workflows/deploy-gate.yml"

# secrets_in_run <yaml-datei>
# exit 1 (+ stdout-Fund), wenn irgendeine `${{ secrets.* }}`-Referenz INNERHALB eines
# `run:`-Shell-Ausdrucks steht (Script-Injection-Muster). `${{ secrets.* }}` in `env:`-
# Blöcken ist erlaubt (das Zielmuster). Verfolgt den Block-Scalar per Einrückung:
# ein `run:`-Key öffnet den Block; Zeilen tiefer eingerückt als der Key gehören dazu,
# ein Dedent auf/unter die Key-Einrückung schließt ihn (POSIX-awk, portabel).
secrets_in_run() {
  awk '
    function firstnonspace(s) { if (match(s, /[^ ]/)) return RSTART - 1; return -1 }
    /^[ ]*$/ { next }
    {
      ind = firstnonspace($0)
      if (in_run && ind <= run_ind) in_run = 0
      if (!in_run && $0 ~ /^[ ]*run:/) {
        run_ind = ind
        rest = $0; sub(/^[ ]*run:/, "", rest)
        if (rest ~ /\$\{\{[ ]*secrets\./) { print FILENAME ":" NR ": " $0; found = 1 }
        in_run = 1
        next
      }
      if (in_run && $0 ~ /\$\{\{[ ]*secrets\./) { print FILENAME ":" NR ": " $0; found = 1 }
    }
    END { exit(found ? 1 : 0) }
  ' "$1"
}

# Positiv-Kontrolle: der Detektor findet eine inline-Referenz in einem run:-Block,
# damit der Guard nicht versehentlich vacuously grün ist (clean-code.md, Gate-Regex-Test).
TMP_YAML_INLINE="$(mktemp)"
printf 'jobs:\n  x:\n    steps:\n      - name: bad\n        run: |\n          [ -n "${{ secrets.FOO }}" ] || exit 1\n' > "$TMP_YAML_INLINE"
secrets_in_run "$TMP_YAML_INLINE" >/dev/null 2>&1
assert_exit 1 "$?" "#66: Detektor erkennt inline \${{ secrets.* }} in einem run:-Block (Positiv-Kontrolle)"
rm -f "$TMP_YAML_INLINE"

# Negativ-Kontrolle: dieselbe Referenz in einem env:-Block ist erlaubt → kein Fund.
TMP_YAML_ENV="$(mktemp)"
printf 'jobs:\n  x:\n    steps:\n      - name: ok\n        env:\n          FOO: ${{ secrets.FOO }}\n        run: |\n          [ -n "$FOO" ] || exit 1\n' > "$TMP_YAML_ENV"
secrets_in_run "$TMP_YAML_ENV" >/dev/null 2>&1
assert_exit 0 "$?" "#66: Detektor akzeptiert \${{ secrets.* }} im env:-Block (Negativ-Kontrolle)"
rm -f "$TMP_YAML_ENV"

# Akzeptanzkriterium: das echte Deploy-Gate hat keine inline-Secret-Referenz in run:.
secrets_in_run "$DEPLOY_GATE" >/dev/null 2>&1
assert_exit 0 "$?" "#66: deploy-gate.yml testet in run:-Blöcken nur \$VAR, kein inline \${{ secrets.* }}"

# Verhalten unverändert: die fail-closed-/Skip-Meldungen bleiben wortgleich erhalten.
grep -q '::error::E2E_ADMIN_EMAIL fehlt' "$DEPLOY_GATE"
assert_true "$?" "#66: fail-closed \`::error::\`-Meldungen unverändert vorhanden"
grep -q '::warning::INT-Refresh übersprungen' "$DEPLOY_GATE"
assert_true "$?" "#66: INT-Refresh Skip-\`::warning::\` unverändert vorhanden"

# deploy-gate.yml bleibt valides YAML (nur wo yq vorhanden, ADR-009).
if [ "$HAS_YQ" = 1 ]; then
  yq '.' "$DEPLOY_GATE" >/dev/null 2>&1
  assert_true "$?" "#66: deploy-gate.yml bleibt valides YAML (yq-Parse)"
else
  skip_yq "#66: deploy-gate.yml bleibt valides YAML"
fi

# ─── #91: factory-commit.sh (Commit/Push-Seam, ADR-019) ──────────────────────
echo ""
echo "#91 factory-commit.sh (Commit/Push-Seam, ADR-019):"

FCOMMIT="$SCRIPTS_DIR/factory-commit.sh"
assert_true "$([[ -f "$FCOMMIT" ]]; echo $?)" "scripts/factory-commit.sh vorhanden"

# Wegwerf-Repo mit Bare-Remote als Push-Ziel (reales git, Muster start-work-Test #74).
# fc_repo <name> → legt Bare-Remote + Klon an, gibt den Arbeitsbaum-Pfad auf stdout.
TMP_FC="$(mktemp -d)"
fc_repo() {
  local name="$1" bare="$TMP_FC/$1.git" wt="$TMP_FC/$1"
  git init -q --bare -b main "$bare" >/dev/null 2>&1
  git clone -q "$bare" "$wt" >/dev/null 2>&1
  git -C "$wt" config user.email t@t
  git -C "$wt" config user.name t
  git -C "$wt" commit -q --allow-empty -m init >/dev/null 2>&1
  git -C "$wt" push -q -u origin main >/dev/null 2>&1
  printf '%s\n' "$wt"
}

# 1. Happy-Path: Feature-Branch + uncommittete Änderung → commit + push (exit 0),
#    das Remote-Tracking-Ref zeigt danach auf den frisch committeten Stand.
WT=$(fc_repo happy)
git -C "$WT" checkout -q -b feature/91-demo
echo "neu" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "feat: demo change" ) >/dev/null 2>&1
assert_exit 0 "$?" "factory-commit: Feature-Branch + Änderung → exit 0"
git -C "$WT" rev-parse origin/feature/91-demo >/dev/null 2>&1
assert_true "$?" "factory-commit: pusht den Feature-Branch auf sein Remote"
git -C "$WT" diff --quiet HEAD origin/feature/91-demo
assert_true "$?" "factory-commit: Remote-Ref zeigt auf den frisch committeten Stand"

# 2. main → fail-closed (exit ≠ 0), nichts committet.
WT=$(fc_repo mainguard)
HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
echo "x" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "feat: darf nicht" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: auf main → exit ≠ 0 (fail-closed)"
[ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
assert_true "$?" "factory-commit: auf main wird nichts committet"

# 3. master → fail-closed.
WT=$(fc_repo masterguard)
git -C "$WT" branch -m master
echo "x" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "feat: nope" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: auf master → exit ≠ 0 (fail-closed)"

# 4. Nichts zu committen → exit 0 + klare Meldung (kein Pipeline-Abbruch).
WT=$(fc_repo empty)
git -C "$WT" checkout -q -b feature/91-empty
fc_out=$( cd "$WT" && bash "$FCOMMIT" "feat: leer" 2>&1 ); fc_rc=$?
assert_exit 0 "$fc_rc" "factory-commit: nichts zu committen → exit 0 (kein Pipeline-Abbruch)"
printf '%s' "$fc_out" | grep -qi 'nichts zu committen'
assert_true "$?" "factory-commit: nichts zu committen nennt den Grund"

# 5. Fehlende Message → Aufruf-Fehler exit ≠ 0 (kein --force-Einfallstor via Zusatz-Args).
WT=$(fc_repo nomsg)
git -C "$WT" checkout -q -b feature/91-nomsg
echo "y" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: ohne Commit-Message → exit ≠ 0"
( cd "$WT" && bash "$FCOMMIT" "feat: x" "--force" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: Zusatz-Argument (z. B. --force) → exit ≠ 0"

# 6. Kein git-Repo → fail-closed.
NOGIT="$TMP_FC/plain"; mkdir -p "$NOGIT"
( cd "$NOGIT" && bash "$FCOMMIT" "feat: x" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: kein git-Repo → exit ≠ 0 (fail-closed)"

# 7. Detached HEAD → fail-closed.
WT=$(fc_repo detached)
git -C "$WT" checkout -q --detach HEAD
echo "z" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "feat: detached" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: detached HEAD → exit ≠ 0 (fail-closed)"

# 8. Push scheitert (kaputtes Remote) → exit ≠ 0 (kein stiller 'committed, nicht gepusht').
WT=$(fc_repo pushfail)
git -C "$WT" checkout -q -b feature/91-pushfail
git -C "$WT" remote set-url origin "$TMP_FC/does-not-exist.git"
echo "w" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "feat: push fail" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: push scheitert → exit ≠ 0 (Ursache weitergereicht)"

rm -rf "$TMP_FC"

# ─── #91: Report-Verdict-Helper / run_skill-Report-Guard (ADR-019 §4) ────────
echo ""
echo "#91 Report-Verdict-Helper (run_skill-Guard, ADR-019 §4):"

RV_LIB="$SCRIPTS_DIR/lib/report-verdict.sh"
assert_true "$([[ -f "$RV_LIB" ]]; echo $?)" "scripts/lib/report-verdict.sh vorhanden"

TMP_RV="$(mktemp -d)"; mkdir -p "$TMP_RV/tasks"
# rv <skill> <task_id> → ruft report_verdict aus der gesourcten Lib (tasks_dir = 3. Arg).
rv() { bash -c 'source "$1"; report_verdict "$2" "$3" "$4"' _ "$RV_LIB" "$1" "$2" "$TMP_RV/tasks"; }

# Report mit gültigem Verdict → erkannt → Guard wertet als ERFOLG (trotz non-zero Exit).
printf '## Ergebnis\nAPPROVED\n' > "$TMP_RV/tasks/review-1.md"
assert_true "$([ "$(rv review 1)" = "APPROVED" ]; echo $?)" "Report-Guard: review APPROVED → Verdict erkannt (Erfolg)"
printf 'NEEDS_REWORK\n' > "$TMP_RV/tasks/review-2.md"
assert_true "$([ "$(rv review 2)" = "NEEDS_REWORK" ]; echo $?)" "Report-Guard: review NEEDS_REWORK → Verdict erkannt (Erfolg)"
printf 'PASSED\n' > "$TMP_RV/tasks/security-3.md"
assert_true "$([ "$(rv security-review 3)" = "PASSED" ]; echo $?)" "Report-Guard: security-review PASSED → Verdict erkannt (Erfolg)"
printf 'NEEDS_FIXES\n' > "$TMP_RV/tasks/security-4.md"
assert_true "$([ "$(rv security-review 4)" = "NEEDS_FIXES" ]; echo $?)" "Report-Guard: security-review NEEDS_FIXES → Verdict erkannt (Erfolg)"

# Report ohne gültigen Verdict → leer → Guard greift NICHT (Fehlschlag, fail-closed).
printf '## Ergebnis\n(noch offen)\n' > "$TMP_RV/tasks/review-5.md"
assert_true "$([ -z "$(rv review 5)" ]; echo $?)" "Report-Guard: review ohne Verdict → nichts erkannt (Fehlschlag, fail-closed)"

# Fehlende Report-Datei → leer (Fehlschlag).
assert_true "$([ -z "$(rv security-review 6)" ]; echo $?)" "Report-Guard: fehlender Report → nichts erkannt (Fehlschlag)"

# Nicht-Report-Skill → immer leer (Verhalten unverändert, auch bei vorhandener Datei).
printf 'APPROVED\n' > "$TMP_RV/tasks/review-7.md"
assert_true "$([ -z "$(rv implement 7)" ]; echo $?)" "Report-Guard: Nicht-Report-Skill → kein Verdict (Verhalten unverändert)"

# Mehrere Vorkommen → letzter gewinnt (wie pipeline_summary() schon las).
printf 'NEEDS_REWORK\n... später ...\nAPPROVED\n' > "$TMP_RV/tasks/review-8.md"
assert_true "$([ "$(rv review 8)" = "APPROVED" ]; echo $?)" "Report-Guard: mehrere Verdicts → letzter gewinnt"

rm -rf "$TMP_RV"

# Wiring: run-pipeline.sh nutzt den geteilten Helper (kein Drift Guard ↔ Summary).
grep -q 'report-verdict.sh' "$PIPELINE"
assert_true "$?" "#91: run-pipeline.sh sourct den geteilten Verdict-Helper"
grep -q 'report_verdict' "$PIPELINE"
assert_true "$?" "#91: run_skill/pipeline_summary nutzen report_verdict (ein Ort)"

# Budget-Puffer: review + security-review auf max_turns 14 (ADR-019 §5).
if [ "$HAS_YQ" = 1 ]; then
  [ "$(yq '.skills.review.max_turns' "$DEFAULTS_YML")" = "14" ] \
    && [ "$(yq '.skills.security-review.max_turns' "$DEFAULTS_YML")" = "14" ]
  assert_true "$?" "#91: review + security-review max_turns=14 (Budget-Puffer)"
else
  skip_yq "#91: review + security-review max_turns=14"
fi

# ─── #91: Permissions-Konsistenz (.claude/settings.json, ADR-019 §2/§3) ──────
echo ""
echo "#91 Permissions-Konsistenz (.claude/settings.json):"

SETTINGS="$FACTORY_ROOT/.claude/settings.json"
assert_true "$([[ -f "$SETTINGS" ]]; echo $?)" ".claude/settings.json vorhanden"

# Read-only-git freigegeben (Diagnose ohne Prompt/Interrupt).
{ grep -qF 'Bash(git status:*)' "$SETTINGS" && grep -qF 'Bash(git diff:*)' "$SETTINGS" \
  && grep -qF 'Bash(git log:*)' "$SETTINGS" && grep -qF 'Bash(git branch:*)' "$SETTINGS" \
  && grep -qF 'Bash(git rev-parse:*)' "$SETTINGS"; }
assert_true "$?" "#91: read-only-git (status/diff/log/branch/rev-parse) in allow"

# Granulare gh-Verben (pr-shepherd), kein Wildcard.
{ grep -qF 'Bash(gh pr view:*)' "$SETTINGS" && grep -qF 'Bash(gh pr checks:*)' "$SETTINGS" \
  && grep -qF 'Bash(gh pr update-branch:*)' "$SETTINGS" && grep -qF 'Bash(gh pr merge:*)' "$SETTINGS" \
  && grep -qF 'Bash(gh pr ready:*)' "$SETTINGS" \
  && grep -qF 'Bash(gh run list:*)' "$SETTINGS" && grep -qF 'Bash(gh run rerun:*)' "$SETTINGS"; }
assert_true "$?" "#91: granulare gh-Verben (pr-shepherd) in allow"

# #94: pr-shepherd.md dokumentiert 'gh pr ready' (Draft-Status auflösen, Schritt 5b) –
# konsistent zur allow-Liste, damit der freigegebene Verb auch im Skill sichtbar genutzt wird.
grep -qF 'gh pr ready' "$SHEPHERD"
assert_true "$?" "#94: pr-shepherd.md dokumentiert 'gh pr ready' (Draft-Auflösung)"

# #94 (AC2): 'gh pr ready' ist hinter einem isDraft-Guard dokumentiert – nicht unbedingt
# aufgerufen. Schützt die "nur bei Draft"-Semantik gegen ein späteres Entfernen des Guards.
grep -qF 'isDraft' "$SHEPHERD"
assert_true "$?" "#94: pr-shepherd.md guardet 'gh pr ready' hinter isDraft-Check (AC2)"

# #114: pr-shepherd Schritt 6 committet+pusht die Abschlussnotiz VOR dem Auto-Merge.
# Bei Squash-Merge landet eine nur lokal geschriebene Notiz sonst nie auf main (#112).
# factory-commit.sh ist der mandatierte Commit/Push-Seam (ADR-019) → deckt commit UND push ab.
grep -qF 'factory-commit.sh' "$SHEPHERD"
assert_true "$?" "#114: pr-shepherd.md committet Abschlussnotiz via factory-commit.sh"

# #114 (Reihenfolge): der commit+push-Schritt steht VOR dem Freigabe-Kommando
# 'gh pr merge --auto --squash' – sonst greift die Härtung nicht (Notiz muss auf dem
# Feature-Branch liegen, bevor Auto-Merge feuert). Bewusst gegen die volle '--squash'-
# Form geprüft: die kürzere 'gh pr merge --auto'-Erwähnung in Schritt 4 ist nur ein
# Prosa-Verweis, kein Kommando.
# Zeilennummer des ersten Fixed-String-Treffers; 0 bei kein/ungültigem Treffer
# (integer-sicher für den arithmetischen Vergleich).
first_match_line() {
  local n
  n="$(grep -nF "$1" "$2" | head -1 | cut -d: -f1)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# 0 (wahr), wenn der Fixed-String $needle im Abschnitt zwischen den Header-Zeilen
# $start_hdr und $end_hdr (beide Fixed Strings) von $file vorkommt; sonst 1.
# Fail-closed: fehlt ein Header oder steht das Ende nicht hinter dem Anfang ⇒ 1.
section_contains() {
  local start_hdr="$1" end_hdr="$2" file="$3" needle="$4" s e
  s="$(first_match_line "$start_hdr" "$file")"
  e="$(first_match_line "$end_hdr" "$file")"
  [ "$s" -gt 0 ] && [ "$e" -gt "$s" ] || return 1
  sed -n "${s},${e}p" "$file" | grep -qF -- "$needle"
}

# 0 (wahr), wenn der erste Fixed-String-Treffer von $a in $file VOR dem ersten Treffer von
# $b liegt (beide müssen > 0 sein); sonst 1. Fail-closed: fehlt einer der Treffer ⇒ 1
# (integer-sicher über first_match_line). Für Reihenfolge-Guards „Kommando A steht vor B".
line_before() {
  local a b file="$3"
  a="$(first_match_line "$1" "$file")"
  b="$(first_match_line "$2" "$file")"
  [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]
}
assert_true "$(line_before 'factory-commit.sh' 'gh pr merge --auto --squash' "$SHEPHERD"; echo $?)" \
  "#114: Abschlussnotiz wird vor 'gh pr merge --auto --squash' committet (Reihenfolge)"

# #117: pr-shepherd Schritt 2 (Review-Kommentare auflösen) committet Review-Fixes über den
# Commit/Push-Seam factory-commit.sh (ADR-019) – analog Schritt 6 (#114) und implement/test/
# refactor. Bewusst gegen den Schritt-2-ABSCHNITT geprüft (Zeilenbereich zwischen den Headern
# '### Schritt 2' und '### Schritt 3'), NICHT global: der bereits vorhandene Schritt-6-Treffer
# darf den Guard nicht fälschlich grün färben (Lehre #114: ein Treffer im falschen Abschnitt ist
# so wenig ein Nachweis wie ein Prosa-Treffer).
assert_true "$(section_contains '### Schritt 2' '### Schritt 3' "$SHEPHERD" 'factory-commit.sh'; echo $?)" \
  "#117: pr-shepherd.md Schritt 2 committet Review-Fixes via factory-commit.sh (Seam)"

# #117 (AC2): das Seam-Kommando trägt im selben Abschnitt die fail-closed-Begründung mit
# ADR-019-Verweis – separat vom Kommando prüfbar, damit ein späteres Entfernen der Begründung
# (bei erhaltenem Kommando) auffällt. Wieder auf den Schritt-2-Abschnitt eingegrenzt.
assert_true "$(section_contains '### Schritt 2' '### Schritt 3' "$SHEPHERD" 'ADR-019'; echo $?)" \
  "#117: pr-shepherd.md Schritt 2 nennt die fail-closed-Begründung (ADR-019)"

# #158 (ADR-030): pr-shepherd Schritt 6 wählt den Merge-Modus nach PR-Zustand.
# GitHub lehnt 'gh pr merge --auto' bei bereits mergebarem PR (mergeStateStatus: CLEAN)
# ab – Schritt 6 muss den Zustand lesen und bei CLEAN direkt squash-mergen (fail-closed:
# alles außer CLEAN → --auto). Schritt 6 ist der letzte '### Schritt' → Abschnittsende ist
# '## Regeln'. AC1, AC2 und AC4 sind separat prüfbare Kriterien (je eine Assertion, #117-Regel):
# entfällt die Zustandsprüfung, bleibt AC2 grün und umgekehrt, und die AC4-Reihenfolge ist von
# beiden unabhängig (Unabhängigkeit belegt in der #94-Temp-Verifikation: unpatched → alle rot,
# patched → alle grün).

# AC1: Zustandsprüfung 'mergeStateStatus' im Schritt-6-Abschnitt.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'mergeStateStatus'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 liest den PR-Merge-Zustand (mergeStateStatus)"

# AC2: Direct-Merge-Fallback 'gh pr merge --squash' (ohne --auto) im Schritt-6-Abschnitt.
# Bewusst gegen die volle 'gh pr merge --squash'-Zeile geprüft: sie ist KEIN Teilstring von
# 'gh pr merge --auto --squash' (Lehre #114: Kommando ≠ Teil-Match), der Grep matcht also
# nicht fälschlich die --auto-Zeile.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'gh pr merge --squash'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 hat Direct-Merge-Fallback (gh pr merge --squash)"

# AC3: der --auto-Fallback bleibt im Schritt-6-Abschnitt für laufende Checks (≠ CLEAN) erhalten.
# Separierbar von AC2 (#117): würde der else-Zweig ebenfalls auf direkten Merge umgestellt,
# bliebe AC2 grün, aber dieser Guard rot. Section-begrenzt (nicht global wie der #114-Order-
# Guard), damit AC3 als eigenes Kriterium diagnostizierbar ist – nicht nur transitiv über #114.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'gh pr merge --auto --squash'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 behält --auto-Fallback für laufende Checks (gh pr merge --auto --squash)"

# AC4: die Abschlussnotiz (factory-commit.sh) steht AUCH VOR dem Direct-Merge-Zweig – nicht
# nur vor der --auto-Zeile (bereits durch #114 oben geprüft). Sonst könnte der direkte Merge
# vor dem Notiz-Push feuern (Notiz landet nie auf main, #112/#114). Zweiter Marker
# 'gh pr merge --squash' ist die Direct-Zeile, nicht die --auto-Zeile (kein Teilstring, s. o.).
assert_true "$(line_before 'factory-commit.sh' 'gh pr merge --squash' "$SHEPHERD"; echo $?)" \
  "#158: Abschlussnotiz wird vor 'gh pr merge --squash' (Direct-Merge) committet (Reihenfolge)"

# Fail-closed: kein pauschales Bash(git *) / Bash(gh *).
assert_true "$(! grep -qE 'Bash\(git \*\)|Bash\(gh \*\)' "$SETTINGS"; echo $?)" \
  "#91: kein pauschales Bash(git *)/Bash(gh *)"

# deny unverändert: .claude/** und .env* bleiben gesperrt.
{ grep -qF 'Write(.claude/**)' "$SETTINGS" && grep -qF 'Edit(.claude/**)' "$SETTINGS" \
  && grep -qF 'Write(.env*)' "$SETTINGS" && grep -qF 'Read(.env*)' "$SETTINGS"; }
assert_true "$?" "#91: deny behält .claude/** und .env* (fail-closed)"

# Skill-Doku: Code-erzeugende Skills committen/pushen über den Seam, nicht rohes git.
for sk in implement test refactor bug-fix; do
  grep -q 'factory-commit.sh' "$FACTORY_ROOT/.claude/commands/$sk.md"
  assert_true "$?" "#91: /$sk committet/pusht über scripts/factory-commit.sh"
done

# ─── Task 101: Pipeline-Quality-Gates rufen echte Befehle (kein Platzhalter) ──
echo ""
echo "Task 101: Pipeline-Quality-Gates (echte Befehle statt Platzhalter):"

# (Struktur, yq-frei) Kein *_PLACEHOLDER-Gate-Befehl mehr in run-pipeline.sh.
# Der alte echo-Platzhalter lief immer auf Exit 0 → Gate fail-open. Regressions-Guard.
assert_true "$(! grep -q '_PLACEHOLDER' "$PIPELINE"; echo $?)" \
  "#101: run-pipeline.sh enthält keinen *_PLACEHOLDER-Gate-Befehl mehr (Regressions-Guard)"

# (Struktur) Echte Befehle mit Env-Override – konsistent mit pre-commit/pre-push.
{ grep -q 'FACTORY_LINT_COMMAND' "$PIPELINE" && grep -q 'FACTORY_TEST_COMMAND' "$PIPELINE" \
  && grep -q 'FACTORY_COVERAGE_COMMAND' "$PIPELINE"; }
assert_true "$?" "#101: run-pipeline.sh nutzt FACTORY_{LINT,TEST,COVERAGE}_COMMAND (Env-Override wie Hook-Gates)"

# (Struktur) pnpm-Defaults aus PROJECT-CONTEXT.md, wenn kein Override gesetzt ist.
{ grep -q 'pnpm lint' "$PIPELINE" && grep -q 'pnpm test' "$PIPELINE" \
  && grep -q 'pnpm test:coverage' "$PIPELINE"; }
assert_true "$?" "#101: run-pipeline.sh hat pnpm-Defaults (pnpm lint / pnpm test / pnpm test:coverage)"

# (Verhalten, yq-gated) Non-dry-run: ein rotes Lint-Gate stoppt die Pipeline fail-closed.
# Mock `claude` (exit 0) lässt Phase 1 (implement) durchlaufen; FACTORY_LINT_COMMAND schreibt
# einen Marker und exit 1 → beweist, dass das Gate den ECHTEN Befehl ausführt (der alte
# echo-Platzhalter wäre exit 0 → Gate fälschlich grün, Pipeline liefe weiter).
if [ "$HAS_YQ" = 1 ]; then
  TMP_G101="$(mktemp -d)"
  mkdir -p "$TMP_G101/scripts/checks" "$TMP_G101/scripts/lib" "$TMP_G101/tasks" \
           "$TMP_G101/docs/factory" "$TMP_G101/.claude/commands" "$TMP_G101/bin"
  cp "$PIPELINE" "$TMP_G101/scripts/"
  cp "$CHECKS_DIR/config-validation-check.sh" "$CHECKS_DIR/interrupt-check.sh" "$TMP_G101/scripts/checks/"
  cp "$SCRIPTS_DIR/lib/report-verdict.sh" "$TMP_G101/scripts/lib/"
  cp "$DEFAULTS_YML" "$TMP_G101/"
  echo "# ctx" > "$TMP_G101/docs/factory/PROJECT-CONTEXT.md"
  echo "# implement mock" > "$TMP_G101/.claude/commands/implement.md"
  echo "# Task 101: gate" > "$TMP_G101/tasks/task-101-gate.md"
  printf '#!/bin/sh\nexit 0\n' > "$TMP_G101/bin/claude"; chmod +x "$TMP_G101/bin/claude"
  git -C "$TMP_G101" init -q; git -C "$TMP_G101" add .
  git -C "$TMP_G101" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  MARKER_G101="$TMP_G101/lint-ran.marker"
  g101_out=$(cd "$TMP_G101" && PATH="$TMP_G101/bin:$PATH" \
    FACTORY_LINT_COMMAND="touch '$MARKER_G101'; false" \
    bash "$TMP_G101/scripts/run-pipeline.sh" 101 2>&1 || true)
  printf '%s' "$g101_out" | grep -q 'Gate fehlgeschlagen: Lint'
  assert_true "$?" "#101: non-dry-run stoppt fail-closed am Lint-Gate (rotes Lint → Pipeline-Abbruch)"
  assert_true "$([ -f "$MARKER_G101" ]; echo $?)" \
    "#101: Lint-Gate führt den ECHTEN Befehl aus (Marker geschrieben, kein echo-Platzhalter)"
  rm -rf "$TMP_G101"
else
  skip_yq "#101: Verhaltens-Test rotes Lint-Gate (non-dry-run)"
fi

# ─── #112: pr-closes-keyword-check.sh (CI-Gate für Closing-Keyword) ──────────
# Verhalten: PR-Body mit Closing-Keyword+#<nr> → exit 0, sonst fail-closed exit 1.
# Positiv- UND Negativfälle, damit ein stilles Nicht-Greifen des Musters auffällt
# (clean-code.md: Gate-Regex gehört durch beide Richtungen abgesichert).
echo ""
echo "#112 pr-closes-keyword-check.sh (Closing-Keyword im PR-Body):"

# Format: "<body>|<erwarteter-exit>|<beschreibung>"  (\n via printf %b für Mehrzeiligkeit)
closes_cases=(
  "Closes #78|0|Closes #<nr>"
  "closes #78|0|klein geschrieben"
  "Fixes #12|0|Fixes"
  "Fixed #12|0|Fixed"
  "Resolves #12|0|Resolves"
  "Resolved #12|0|Resolved"
  "Closes: #78|0|Doppelpunkt-Variante"
  "Zeile eins\nCloses #99\nZeile drei|0|Keyword in mehrzeiligem Body"
  "(#78)|1|nur Erwähnung in Klammern (der #79-Bug)"
  "Task #78: foo|1|Task-Referenz ohne Keyword"
  "Behebt #78|1|deutsches Behebt ist kein GitHub-Keyword"
  "forecloses #5|1|Teilwort foreclose ist kein Keyword"
  "Closes #|1|Keyword ohne Nummer"
  "Closes#78|1|kein Whitespace vor #"
  "|1|leerer Body (fail-closed)"
)

for case in "${closes_cases[@]}"; do
  IFS='|' read -r body expected desc <<< "$case"
  PR_BODY="$(printf '%b' "$body")" \
    bash "$CHECKS_DIR/pr-closes-keyword-check.sh" >/dev/null 2>&1
  assert_exit "$expected" "$?" "$desc"
done

# Struktur: das Gate ist als eigener pull_request-Job in der CI verdrahtet.
{ grep -q 'pr-closes-keyword-check.sh' "$CI_FILE" \
  && grep -q 'github.event.pull_request.body' "$CI_FILE"; }
assert_true "$?" "#112: CI verdrahtet das Closing-Keyword-Gate (Script + PR-Body-Env)"

# ─── #149: Format-Gate in pre-push.sh (Prettier-Konformität) ─────────────────
# Ursache des Drifts (Task 149): format:check war an keinem Gate verdrahtet.
# Struktur UND Verhalten absichern – analog zum #101-Lint-Gate-Test.
echo ""
echo "#149 pre-push.sh Format-Gate (prettier --check):"

# (Struktur) Distinktive CODE-Zeile prüfen, nicht die Bezeichner allein: `FACTORY_FORMAT_COMMAND`
# und `format:check` kommen im Gate auch in Kommentar-Prosa vor – ein Grep darauf bliebe grün,
# wenn nur ein Kommentar stehen bliebe (#114 „Kommando ≠ Prosa-Erwähnung"). Der `${…-…}`-Ausdruck
# taucht ausschließlich in der Zuweisung auf und belegt zugleich den fail-closed-Default
# (`pnpm format:check` bei unset) und die Single-Dash-Semantik (leerer Wert = echter Opt-out).
grep -qF '${FACTORY_FORMAT_COMMAND-pnpm format:check}' "$CHECKS_DIR/pre-push.sh"
assert_true "$?" "#149: pre-push.sh verdrahtet das Format-Gate mit fail-closed-Default (\${FACTORY_FORMAT_COMMAND-pnpm format:check})"

# (Verhalten) In einem Temp-Repo auf einem Feature-Branch die teuren Gates via Override
# neutralisieren (true), sodass allein das Format-Gate das Ergebnis bestimmt. Beweist,
# dass das Gate den ECHTEN Befehl ausführt (rot → blockiert) und der Env-Override greift.
TMP_G149="$(mktemp -d)"
git -C "$TMP_G149" init -q
git -C "$TMP_G149" checkout -q -b feature/149-format-gate-test
git -C "$TMP_G149" -c user.email="t@t.com" -c user.name="t" commit -q --allow-empty -m init
run_prepush_149() { # $1 = FACTORY_FORMAT_COMMAND-Wert
  ( cd "$TMP_G149" && FACTORY_TEST_COMMAND=true FACTORY_TYPECHECK_COMMAND=true \
      FACTORY_FORMAT_COMMAND="$1" bash "$CHECKS_DIR/pre-push.sh" >/dev/null 2>&1 )
}
run_prepush_149 "false"
assert_exit 1 "$?" "#149: Drift (Format-Befehl exit 1) blockiert den Push fail-closed"
run_prepush_149 "true"
assert_exit 0 "$?" "#149: konform (Format-Befehl exit 0) lässt den Push zu"
run_prepush_149 ""
assert_exit 0 "$?" "#149: leerer FACTORY_FORMAT_COMMAND deaktiviert das Gate (nicht blockierend)"
rm -rf "$TMP_G149"

# ─── #145: routes-doc-check.sh (Drift zwischen app/-Baum und docs/routes.md) ──
# Positiv- UND Negativfälle (beide Drift-Richtungen), damit ein stilles Nicht-Greifen
# des Musters auffällt (clean-code.md: Gate-Regex in beide Richtungen abgesichert).
echo ""
echo "#145 routes-doc-check.sh (Routen-Doku-Drift, fail-closed):"

ROUTES_CHECK="$CHECKS_DIR/routes-doc-check.sh"
assert_true "$([[ -f "$ROUTES_CHECK" ]]; echo $?)" "routes-doc-check.sh vorhanden"

# Fixture: app/-Baum + docs/routes.md; FACTORY_DIR steuert die Projektwurzel des Checks.
TMP_RT="$(mktemp -d)"
mkdir -p "$TMP_RT/app/login" "$TMP_RT/app/veranstaltung/[id]" \
         "$TMP_RT/app/api/health" "$TMP_RT/app/_private" \
         "$TMP_RT/app/(werbung)/info" "$TMP_RT/app/foo_bar" "$TMP_RT/docs"
: > "$TMP_RT/app/page.tsx"
: > "$TMP_RT/app/login/page.tsx"
: > "$TMP_RT/app/veranstaltung/[id]/page.tsx"   # dynamisches Segment
: > "$TMP_RT/app/api/health/route.ts"
: > "$TMP_RT/app/_private/page.tsx"              # privater Ordner → KEINE Route (ignorieren)
: > "$TMP_RT/app/(werbung)/info/page.tsx"        # Route Group (name) → /info (kein Segment)
: > "$TMP_RT/app/foo_bar/page.tsx"               # Unterstrich MITTEN im Segment → KEIN privater Ordner

write_routes_doc() {
  cat > "$TMP_RT/docs/routes.md" <<'DOCEOF'
# Routen-Übersicht
| Pfad | Typ | Funktion | Zugriff |
|------|-----|----------|---------|
| `/` | Seite | Home | angemeldet |
| `/login` | Seite | Login | öffentlich |
| `/foo_bar` | Seite | Foo | angemeldet |
| `/veranstaltung/[id]` | Seite | Detail | veranstalter |
| `/info` | Seite | Info | öffentlich |
| `/api/health` | API | Health | öffentlich |
DOCEOF
}
rc_routes() { FACTORY_DIR="$TMP_RT" bash "$ROUTES_CHECK" 2>&1; }

# 1. Doku deckt alle Routen exakt ab: dynamisches [id] + Route Group (werbung)→/info gemappt,
#    _private ignoriert → grün. (Fällt der Route-Group-Strip weg, mappt /info falsch → rot.)
write_routes_doc
rc_routes >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "in sync ([id] + (werbung)-Group + foo_bar gemappt, _private ignoriert) → exit 0"

# 2. Neue Route-Datei ohne Doku-Eintrag → fail-closed exit 1 + benennt die Route
mkdir -p "$TMP_RT/app/neu"; : > "$TMP_RT/app/neu/page.tsx"
out=$(rc_routes); rc=$?
assert_exit 1 "$rc" "Route ohne Doku-Eintrag → exit 1 (fail-closed)"
printf '%s' "$out" | grep -qF '/neu'
assert_true "$?" "benennt die undokumentierte Route (/neu)"
rm -rf "$TMP_RT/app/neu"

# 3. Doku-Eintrag ohne zugehörige Route-Datei → fail-closed exit 1 + benennt den Eintrag
write_routes_doc
printf '| `/geist` | Seite | tot | angemeldet |\n' >> "$TMP_RT/docs/routes.md"
out=$(rc_routes); rc=$?
assert_exit 1 "$rc" "Doku-Eintrag ohne Route-Datei → exit 1 (fail-closed)"
printf '%s' "$out" | grep -qF '/geist'
assert_true "$?" "benennt den verwaisten Doku-Eintrag (/geist)"

# 4. Fehlende docs/routes.md → fail-closed exit 1
rm -f "$TMP_RT/docs/routes.md"
rc_routes >/dev/null 2>&1
assert_exit 1 "$?" "fehlende docs/routes.md → exit 1 (fail-closed)"

rm -rf "$TMP_RT"

# Struktur: der Drift-Check ist im Push-Gate (pre-push.sh) verdrahtet.
grep -q 'routes-doc-check.sh' "$CHECKS_DIR/pre-push.sh"
assert_true "$?" "#145: pre-push.sh verdrahtet den Routen-Doku-Drift-Check"

# ─── #173: Deploy-Freeze bei rotem Gate (ADR-032) ────────────────────────────
echo ""
echo "#173 Deploy-Freeze (ADR-032):"

DEPLOY_FREEZE="$SCRIPTS_DIR/deploy-freeze.sh"
NOTIFY="$SCRIPTS_DIR/deploy-freeze-notify.sh"
GATE_YML="$FACTORY_ROOT/.github/workflows/deploy-gate.yml"
RELEASE_YML="$FACTORY_ROOT/.github/workflows/deploy-freeze-release.yml"

assert_true "$([[ -f "$DEPLOY_FREEZE" ]]; echo $?)" "scripts/deploy-freeze.sh vorhanden"

# Bare-Repo-Simulation der Vorfall-Sequenz (AC6) – ohne echten Deploy, ohne GitHub-API.
TMP_DF="$(mktemp -d)"
git init -q --bare "$TMP_DF/origin.git"
git init -q "$TMP_DF/work"
git -C "$TMP_DF/work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "commit A (#134)"
SHA_A="$(git -C "$TMP_DF/work" rev-parse HEAD)"
git -C "$TMP_DF/work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "commit B (#167)"
SHA_B="$(git -C "$TMP_DF/work" rev-parse HEAD)"

# df <args…> – ruft deploy-freeze.sh aus dem Work-Repo gegen das Bare-Repo als Remote auf.
df() {
  ( cd "$TMP_DF/work" && FREEZE_REMOTE="$TMP_DF/origin.git" FREEZE_REF="refs/factory/deploy-freeze" \
      bash "$DEPLOY_FREEZE" "$@" )
}

# 1. Frischer Zustand: nicht eingefroren → check exit 10
df check >/dev/null 2>&1
assert_exit 10 "$?" "AC: frischer Zustand → check exit 10 (nicht eingefroren)"

# 2. #134 wird rot → Freeze auf SHA_A setzen (exit 0)
df set "$SHA_A" "E2E gegen INT rot (#134)" >/dev/null 2>&1
assert_exit 0 "$?" "AC1: rotes Gate setzt Freeze (set exit 0)"

# 3. check → eingefroren (exit 0)
df check >/dev/null 2>&1
assert_exit 0 "$?" "AC1: nach set → check exit 0 (eingefroren)"

# 4. status nennt den blockierenden SHA
out=$(df status 2>/dev/null)
assert_true "$([[ "$out" = "$SHA_A" ]]; echo $?)" "AC1: status gibt den blockierenden SHA (SHA_A) aus"

# 5. Simulierter grüner Folgelauf (#167): der Freeze bleibt stehen → check weiterhin 0.
#    Das ist die maschinelle Fassung von #134-rot → #167-grün: der grüne Lauf promotet NICHT.
df check >/dev/null 2>&1
assert_exit 0 "$?" "AC6: grüner Folgelauf sieht weiterhin Freeze (check exit 0 → kein Promote)"

# 6. Doppel-Freeze: zweiter roter Lauf überschreibt den ursprünglichen SHA NICHT
df set "$SHA_B" "andere Ursache" >/dev/null 2>&1
df_dbl_exit=$?
out=$(df status 2>/dev/null)
assert_exit 0 "$df_dbl_exit" "Doppel-Freeze: zweites set → exit 0"
assert_true "$([[ "$out" = "$SHA_A" ]]; echo $?)" "Doppel-Freeze: ursprünglicher SHA_A bleibt (nicht überschrieben)"

# 7. Freigabe (release) → Ref weg, check wieder 10
df release >/dev/null 2>&1
assert_exit 0 "$?" "AC7: release → exit 0"
df check >/dev/null 2>&1
assert_exit 10 "$?" "AC7: nach release → check exit 10 (nicht eingefroren)"

# 8. release ist idempotent (kein aktiver Freeze → trotzdem exit 0)
df release >/dev/null 2>&1
assert_exit 0 "$?" "AC7: release ohne aktiven Freeze → idempotent exit 0"

# 9. Fail-closed: Remote nicht lesbar → check WEDER 0 NOCH 10 (unklar), NIE 10
( cd "$TMP_DF/work" && FREEZE_REMOTE="$TMP_DF/does-not-exist.git" bash "$DEPLOY_FREEZE" check ) >/dev/null 2>&1
df_unreadable=$?
assert_true "$([[ "$df_unreadable" -ne 10 && "$df_unreadable" -ne 0 ]]; echo $?)" \
  "AC3: unlesbarer Marker → check weder 0 noch 10 (fail-closed, kein Promote)"

# 10. Aufruf-Fehler: unbekanntes Subkommando → exit 2
df bogus >/dev/null 2>&1
assert_exit 2 "$?" "unbekanntes Subkommando → exit 2 (Aufruf-Fehler)"

# 11. set ohne Argumente → exit 1
df set >/dev/null 2>&1
assert_exit 1 "$?" "set ohne <sha>/<grund> → exit 1"

# 12. Fail-closed set (K1): Remote unlesbar → set endet non-zero (kein stilles fail-open).
#     Deckt den freeze_set-*)-Zweig ab: bei unklarer Lage wird der Push VERSUCHT (nicht
#     still ohne Marker abgebrochen); scheitert er am unerreichbaren Remote, ist der
#     Fehlschlag sichtbar (non-zero) statt fälschlich exit 0.
( cd "$TMP_DF/work" && FREEZE_REMOTE="$TMP_DF/does-not-exist.git" bash "$DEPLOY_FREEZE" set "$SHA_A" "E2E rot" ) >/dev/null 2>&1
assert_true "$([[ "$?" -ne 0 ]]; echo $?)" "AC1/K1: set gegen unlesbaren Remote → non-zero (fail-closed, kein stilles fail-open)"

# 13. freeze_status-*)-Zweig: Remote unlesbar → status exit 2 (unklar, nicht 0).
( cd "$TMP_DF/work" && FREEZE_REMOTE="$TMP_DF/does-not-exist.git" bash "$DEPLOY_FREEZE" status ) >/dev/null 2>&1
assert_exit 2 "$?" "status gegen unlesbaren Remote → exit 2 (Marker-Status unklar)"

# 14. freeze_release-*)-Zweig: Remote unlesbar → release bleibt permissiv (exit 0, idempotent).
#     Freigabe ist die Entblock-Richtung; ein nicht durchführbarer Delete darf keinen roten
#     Lauf erzeugen (der Freeze bliebe ohnehin bestehen und der Promote-Guard verweigert).
( cd "$TMP_DF/work" && FREEZE_REMOTE="$TMP_DF/does-not-exist.git" bash "$DEPLOY_FREEZE" release ) >/dev/null 2>&1
assert_exit 0 "$?" "release gegen unlesbaren Remote → exit 0 (permissiv/idempotent, unklar-Zweig)"

rm -rf "$TMP_DF"

# ─── Benachrichtigung (fail-open, ADR-032 §5) ────────────────────────────────
assert_true "$([[ -f "$NOTIFY" ]]; echo $?)" "scripts/deploy-freeze-notify.sh vorhanden"

# Fail-open: kein gh im PATH → Skript endet trotzdem grün (Marker bleibt maßgeblich).
# PATH auf ein leeres Verzeichnis setzen (gh nicht auffindbar); bash über absoluten Pfad
# aufrufen, damit die Shell selbst trotz leerem PATH startet.
TMP_NOTIFY="$(mktemp -d)"; mkdir -p "$TMP_NOTIFY/emptybin"
BASH_BIN="$(command -v bash)"
PATH="$TMP_NOTIFY/emptybin" "$BASH_BIN" "$NOTIFY" frozen abc123 "E2E rot" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify ohne gh → fail-open exit 0 (Schutz bleibt unberührt)"

# Happy Path: gh-Mock ohne bestehendes Issue → 'frozen' legt Tracking-Issue an.
mkdir -p "$TMP_NOTIFY/bin"
cat > "$TMP_NOTIFY/bin/gh" <<'GHEOF'
#!/bin/sh
case "$1 $2" in
  "issue list") echo "" ;;                       # kein bestehendes Tracking-Issue
  "issue create") echo "$*" >> "$GH_LOG"; echo "https://github.com/x/y/issues/1" ;;
  "issue comment") echo "$*" >> "$GH_LOG" ;;
  "issue reopen"|"issue close") echo "$*" >> "$GH_LOG" ;;
  *) : ;;
esac
GHEOF
chmod +x "$TMP_NOTIFY/bin/gh"
: > "$TMP_NOTIFY/gh.log"
PATH="$TMP_NOTIFY/bin:$PATH" GH_LOG="$TMP_NOTIFY/gh.log" \
  bash "$NOTIFY" frozen abc123 "E2E rot" "http://run" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify 'frozen' (gh-Mock) → exit 0"
grep -q 'issue create' "$TMP_NOTIFY/gh.log"
assert_true "$?" "AC8: ohne bestehendes Issue legt 'frozen' ein Tracking-Issue an"

# 'released' ohne bestehendes Issue → keine Neuanlage, trotzdem exit 0
: > "$TMP_NOTIFY/gh.log"
PATH="$TMP_NOTIFY/bin:$PATH" GH_LOG="$TMP_NOTIFY/gh.log" \
  bash "$NOTIFY" released abc123 "" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify 'released' ohne Issue → exit 0 (keine Neuanlage)"
assert_true "$(! grep -q 'issue create' "$TMP_NOTIFY/gh.log"; echo $?)" "AC8: 'released' legt kein neues Issue an"

# Existing-Issue-Pfad: gh-Mock mit einem bestehenden Tracking-Issue (issue list → Nummer).
# Deckt den Kommentar-+reopen/close-Zweig ab (die eigentliche Signalisierung), der beim
# Neuanlage-Mock (issue list → "") nie durchlaufen wird.
cat > "$TMP_NOTIFY/bin/gh" <<'GHEOF'
#!/bin/sh
case "$1 $2" in
  "issue list") echo "42" ;;                     # bestehendes Tracking-Issue #42
  "issue create") echo "$*" >> "$GH_LOG"; echo "https://github.com/x/y/issues/42" ;;
  "issue comment") echo "$*" >> "$GH_LOG" ;;
  "issue reopen"|"issue close") echo "$*" >> "$GH_LOG" ;;
  *) : ;;
esac
GHEOF
chmod +x "$TMP_NOTIFY/bin/gh"

# 'frozen' mit bestehendem Issue → kommentieren + wieder öffnen, KEINE Neuanlage.
: > "$TMP_NOTIFY/gh.log"
PATH="$TMP_NOTIFY/bin:$PATH" GH_LOG="$TMP_NOTIFY/gh.log" \
  bash "$NOTIFY" frozen abc123 "E2E rot" "http://run" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify 'frozen' mit bestehendem Issue → exit 0"
assert_true "$(! grep -q 'issue create' "$TMP_NOTIFY/gh.log"; echo $?)" "AC8: 'frozen' legt bei bestehendem Issue KEIN neues an"
grep -q 'issue comment' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'frozen' kommentiert das bestehende Tracking-Issue"
grep -q 'issue reopen' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'frozen' öffnet das Tracking-Issue wieder"

# 'blocked' mit bestehendem Issue → kommentieren + wieder öffnen.
: > "$TMP_NOTIFY/gh.log"
PATH="$TMP_NOTIFY/bin:$PATH" GH_LOG="$TMP_NOTIFY/gh.log" \
  bash "$NOTIFY" blocked abc123 "Freeze aktiv" "http://run" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify 'blocked' mit bestehendem Issue → exit 0"
grep -q 'issue comment' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'blocked' kommentiert das Tracking-Issue"
grep -q 'issue reopen' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'blocked' öffnet das Tracking-Issue wieder"

# 'released' mit bestehendem Issue → kommentieren + schließen.
: > "$TMP_NOTIFY/gh.log"
PATH="$TMP_NOTIFY/bin:$PATH" GH_LOG="$TMP_NOTIFY/gh.log" \
  bash "$NOTIFY" released abc123 "" "http://run" >/dev/null 2>&1
assert_exit 0 "$?" "AC8: notify 'released' mit bestehendem Issue → exit 0"
grep -q 'issue comment' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'released' kommentiert das Tracking-Issue"
grep -q 'issue close' "$TMP_NOTIFY/gh.log"; assert_true "$?" "AC8: 'released' schließt das Tracking-Issue"

rm -rf "$TMP_NOTIFY"

# ─── Deploy-Gate-Verdrahtung (deploy-gate.yml) ───────────────────────────────
assert_true "$([[ -f "$GATE_YML" ]]; echo $?)" "deploy-gate.yml vorhanden"

# Step-IDs für die scharfe Trigger-Abgrenzung (nur E2E/Migration frieren, ADR-032 §4)
grep -q 'id: e2e' "$GATE_YML";         assert_true "$?" "deploy-gate: E2E-Step hat id: e2e"
grep -q 'id: migrate_int' "$GATE_YML"; assert_true "$?" "deploy-gate: db:migrate:int hat eigene id: migrate_int"
grep -q 'id: migrate_prd' "$GATE_YML"; assert_true "$?" "deploy-gate: PRD-Migration hat id: migrate_prd"
grep -q 'id: check_freeze' "$GATE_YML"; assert_true "$?" "deploy-gate: Freeze-Check-Step (id: check_freeze) vorhanden"

# AC4: check_freeze steht VOR der PRD-Migration (kein Prod-DB-Seiteneffekt).
line_check=$(grep -n 'id: check_freeze' "$GATE_YML" | head -1 | cut -d: -f1)
line_migprd=$(grep -n 'id: migrate_prd' "$GATE_YML" | head -1 | cut -d: -f1)
assert_true "$([[ -n "$line_check" && -n "$line_migprd" && "$line_check" -lt "$line_migprd" ]]; echo $?)" \
  "AC4: check_freeze steht VOR der PRD-Migration (id: migrate_prd)"

# AC3/AC5: Promote-Pfad nur wenn NICHT frozen; Freeze-Check selbst ohne exit 1 (Lauf grün).
grep -q "steps.check_freeze.outputs.frozen != 'true'" "$GATE_YML"
assert_true "$?" "AC3: Prod-Schritte hinter if: check_freeze.frozen != 'true'"

# AC1/AC2: set_freeze nur bei Fehlschlag der verifikationsrelevanten Steps (nicht bei Infra).
grep -q 'id: set_freeze' "$GATE_YML"; assert_true "$?" "AC1: set_freeze-Step vorhanden"
grep -q 'steps.e2e.outcome' "$GATE_YML"
assert_true "$?" "AC1: set_freeze-Bedingung referenziert steps.e2e.outcome"
grep -q 'steps.migrate_int.outcome' "$GATE_YML"
assert_true "$?" "AC1: set_freeze-Bedingung referenziert steps.migrate_int.outcome"
grep -q 'steps.migrate_prd.outcome' "$GATE_YML"
assert_true "$?" "AC1: set_freeze-Bedingung referenziert steps.migrate_prd.outcome"

# AC8: Gate braucht issues: write für die Benachrichtigung
grep -q 'issues: write' "$GATE_YML"
assert_true "$?" "AC8: deploy-gate hat permissions issues: write"

# AC7: dokumentierter Freigabe-Weg = workflow_dispatch-Workflow
assert_true "$([[ -f "$RELEASE_YML" ]]; echo $?)" "AC7: deploy-freeze-release.yml vorhanden"
grep -q 'workflow_dispatch' "$RELEASE_YML"
assert_true "$?" "AC7: Freigabe läuft über workflow_dispatch"
grep -q 'deploy-freeze.sh release' "$RELEASE_YML"
assert_true "$?" "AC7: Freigabe-Workflow ruft deploy-freeze.sh release"

# ─── #173/#66: Freigabe-Workflow liest workflow_dispatch-Input/actor über env: ───
# Der Freigabe-Workflow ist der Notfall-Entblock-Pfad. `${{ inputs.grund }}` ist frei
# getippter Text und `${{ github.actor }}` nutzerbeeinflusst – beide dürfen NICHT inline
# in eine `run:`-Shell interpoliert werden (Actions-Script-Injection + funktionaler Bruch
# an Sonderzeichen), sondern nur über `env:` gequotet. Gleicher Maßstab wie #66 im
# Schwester-Workflow deploy-gate.yml. Detektor spiegelt secrets_in_run (Block-Scalar per
# Einrückung), Zielmuster = nutzerkontrollierte inputs.*/github.actor.
echo ""
echo "#173 Härtung – Freigabe-Workflow: inputs.*/github.actor über env: statt inline im run::"

userinput_in_run() {
  awk '
    function firstnonspace(s) { if (match(s, /[^ ]/)) return RSTART - 1; return -1 }
    /^[ ]*$/ { next }
    {
      ind = firstnonspace($0)
      if (in_run && ind <= run_ind) in_run = 0
      if (!in_run && $0 ~ /^[ ]*run:/) {
        run_ind = ind
        rest = $0; sub(/^[ ]*run:/, "", rest)
        if (rest ~ /\$\{\{[ ]*(inputs\.|github\.actor)/) { print FILENAME ":" NR ": " $0; found = 1 }
        in_run = 1
        next
      }
      if (in_run && $0 ~ /\$\{\{[ ]*(inputs\.|github\.actor)/) { print FILENAME ":" NR ": " $0; found = 1 }
    }
    END { exit(found ? 1 : 0) }
  ' "$1"
}

# Positiv-Kontrolle: inline inputs.* im run:-Block wird erkannt (Guard nicht vacuously grün).
TMP_YAML_INJ="$(mktemp)"
printf 'jobs:\n  x:\n    steps:\n      - name: bad\n        run: |\n          echo "Grund: ${{ inputs.grund }}"\n' > "$TMP_YAML_INJ"
userinput_in_run "$TMP_YAML_INJ" >/dev/null 2>&1
assert_exit 1 "$?" "#173: Detektor erkennt inline \${{ inputs.* }} in einem run:-Block (Positiv-Kontrolle)"
rm -f "$TMP_YAML_INJ"

# Negativ-Kontrolle: dieselbe Referenz im env:-Block ist erlaubt → kein Fund.
TMP_YAML_INJ_OK="$(mktemp)"
printf 'jobs:\n  x:\n    steps:\n      - name: ok\n        env:\n          GRUND: ${{ inputs.grund }}\n        run: |\n          echo "Grund: $GRUND"\n' > "$TMP_YAML_INJ_OK"
userinput_in_run "$TMP_YAML_INJ_OK" >/dev/null 2>&1
assert_exit 0 "$?" "#173: Detektor akzeptiert \${{ inputs.* }} im env:-Block (Negativ-Kontrolle)"
rm -f "$TMP_YAML_INJ_OK"

# Akzeptanzkriterium: der echte Freigabe-Workflow interpoliert inputs/actor nicht inline im run:.
userinput_in_run "$RELEASE_YML" >/dev/null 2>&1
assert_exit 0 "$?" "#173: deploy-freeze-release.yml nutzt \$GRUND/\$ACTOR (env:), kein inline \${{ inputs.* }}/\${{ github.actor }}"

# Beleg, dass die Werte tatsächlich über env: bereitgestellt werden (Fix-Muster, wie deploy-gate.yml).
grep -q 'GRUND: ${{ inputs.grund }}' "$RELEASE_YML"
assert_true "$?" "#173: inputs.grund wird über env: GRUND bereitgestellt"
grep -q 'ACTOR: ${{ github.actor }}' "$RELEASE_YML"
assert_true "$?" "#173: github.actor wird über env: ACTOR bereitgestellt"

# deploy-freeze-release.yml bleibt valides YAML (nur wo yq vorhanden, ADR-009).
if [ "$HAS_YQ" = 1 ]; then
  yq '.' "$RELEASE_YML" >/dev/null 2>&1
  assert_true "$?" "#173: deploy-freeze-release.yml bleibt valides YAML (yq-Parse)"
else
  skip_yq "#173: deploy-freeze-release.yml bleibt valides YAML"
fi

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo ""
echo -e "Ergebnis: ${GREEN}${PASS} grün${NC}, ${RED}${FAIL} rot${NC}"
[[ "$FAIL" -eq 0 ]]
