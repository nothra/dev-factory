#!/usr/bin/env bash
# run-tests.sh – Tabellen-getriebene Tests für die Check-Skripte
#
# Verwendung: bash scripts/checks/tests/run-tests.sh
# Exit-Code 0 = alle Tests grün, 1 = mindestens ein Test rot.
#
# Deckt ab (nicht abschließend – der Umfang wächst mit den Check-/Seam-Skripten):
#   - branch-name-check.sh: Erkennung von checkout -b/-B und switch -c/-C
#     sowie Prüfung gegen die erlaubten Präfixe
#   - check.sh (pre-tool): End-to-End über stdin-JSON (Hook-Kontrakt)
#   - factory-commit.sh: Commit/Push-Seam inkl. Guards (ADR-019)
#   - commit-msg-check.sh / install-hooks.sh / init-factory.sh: Flag-Guard für
#     Commit-Messages und Hook-Installation (ADR-042)
#   - weitere Pipeline-/Doku-Invarianten je Issue-Block (Abschnittstitel nennen die Nummer)
#
# Konvention: Ein `#<nr>` in Testnamen und Meldungen bezeichnet das Issue des Ursprungs-Repos
# `nothra/tch-gastro-services` (Herkunft des jeweiligen Tests); in Kommentaren steht der Verweis qualifiziert.

set -uo pipefail

CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Gemeinsame Prüf-Helfer (Zähler, assert_*, Fixtures) – geteilt mit der Projekt-Suite (nothra/tch-gastro-services#432, Q10)
source "$CHECKS_DIR/tests/lib/assert-helpers.sh" || {
  echo "run-tests: geteilte Helfer-Lib nicht ladbar: $CHECKS_DIR/tests/lib/assert-helpers.sh (fail-closed, Factory-Issue #22 F-22.5)" >&2
  exit 2
}

# Markierung für den Projekt-Hook scripts/project/checks/pre-push.d/10-project-tests.sh: Diese Suite ruft pre-push.sh echt gegen das
# Repo auf (#149, #265 …); dort soll der Hook die Projekt-Suite nicht verschachtelt noch einmal starten (Factory-Issue #22).
export FACTORY_SELF_TEST_RUN=1

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

# Gate-Kommandos für die Pipeline-Läufe in Wegwerf-Repos (nothra/tch-gastro-services#431): run-pipeline.sh hat keinen pnpm-
# Default mehr und bricht vor dem ersten Agenten-Schritt ab, wenn lint/test/coverage weder in der
# Config noch per Env stehen. Die Wegwerf-Repos tragen keine factory.config.yml mit commands.* –
# ein Test, der ein Gate prüft, setzt sein Kommando explizit (das schlägt diese Vorgabe). Vor den
# nothra/tch-gastro-services#431-Gruppen G/H wird sie wieder entfernt, damit deren Fehlend-Tests nichts erben.
export FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true


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
  cp_pipeline_libs "$TMP_PF"
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


# ─── Stufe-2: OTEL-ready Bauchladen (nothra/tch-gastro-services#17) ────────────────────────────────────
echo ""
echo "Stufe-2 OTEL-Telemetrie (#17):"

OTEL_FILE="$FACTORY_ROOT/config/otel.env.example"
assert_true "$([[ -f "$OTEL_FILE" ]]; echo $?)" "config/otel.env.example vorhanden"

# Master-Schalter ist der Kern der Telemetrie-Aktivierung
grep -q 'CLAUDE_CODE_ENABLE_TELEMETRY=1' "$OTEL_FILE"
assert_true "$?" "otel.env.example enthält CLAUDE_CODE_ENABLE_TELEMETRY=1"

# config/otel.env.example bleibt die Beispiel-Datei für den manuellen/Gateway-Weg und wird
# von run-pipeline.sh weiterhin NICHT gesourct – die Pipeline setzt ihre zwei Variablen seit
# nothra/tch-gastro-services#334 selbst (ADR-049 §E3). Die frühere Zusicherung „OTEL ist opt-in" ist damit ungültig;
# ihr Ersatz (Default an + wirksamer Abschalt-Parameter) steht im nothra/tch-gastro-services#334-Block unten. Was hier
# bleibt, ist die schwächere, aber weiter gültige Aussage: kein Wiring auf die Beispiel-Datei.
grep -q 'otel.env' "$FACTORY_ROOT/scripts/run-pipeline.sh"
assert_true "$([ $? -ne 0 ]; echo $?)" "config/otel.env.example wird nicht von run-pipeline.sh gesourct (ADR-049 §E3)"

# ─── Stufe-2: Metrics-Digest + Interrupt-Log (nothra/tch-gastro-services#12) ───────────────────────────
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

# ─── nothra/tch-gastro-services#96: metrics.sh Lead-Time ist locale-unabhängig (printf-%f-Regression) ──
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

# ─── Stufe-2: Post-Merge-Verify (nothra/tch-gastro-services#11) ────────────────────────────────────────
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
# Tests sollen nicht schlafen: keine Retries / kein Backoff (außer im nothra/tch-gastro-services#24-Retry-Test).
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

# nothra/tch-gastro-services#23: pluggbarer FACTORY_HEALTHCHECK_CMD (Exit-Code = Urteil), Vorrang vor URL
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

# nothra/tch-gastro-services#24: Retry/Poll gegen Deploy-Lag. CMs vorgegebener Testfall – Mock liefert erst
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

# ─── Stufe-2: Async-Trigger / Scheduled-Poll (nothra/tch-gastro-services#10, ADR-008) ──────────────────
echo ""
echo "Stufe-2 Async-Trigger (#10):"

POLL_YML="$FACTORY_ROOT/.github/workflows/factory-poll.yml"
assert_true "$([[ -f "$FACTORY_ROOT/scripts/factory-poll.sh" ]]; echo $?)" "scripts/factory-poll.sh vorhanden"
assert_true "$([[ -f "$POLL_YML" ]]; echo $?)" ".github/workflows/factory-poll.yml vorhanden"

# ─── nothra/tch-gastro-services#284: der Schedule ist stillgelegt, workflow_dispatch bleibt ────────────
# Der Auto-Trigger ist nicht scharfgeschaltet (kein ANTHROPIC_API_KEY, nie ein
# factory::run-Issue) – ein halbstündlicher Lauf installierte nur ungepinnte
# Software mit Repo-Schreibrechten, um festzustellen, dass nichts zu tun ist.
# Guards deshalb in der Gegenrichtung zum Vorzustand (früher: "schedule: muss da sein").

# poll_yaml_block <workflow-datei> <top-level-key> – gibt den Block unter dem Top-Level-Key
# ohne Kommentare aus; Inline-Inhalt der Key-Zeile selbst bleibt erhalten (Flow-Notation
# wie `on: {schedule: [...]}` ist damit sichtbar).
# Kommentare fallen IN derselben awk-Passage weg, damit eine Prosa-Erwähnung von
# `schedule` oder `contents: write` in einem Kommentar keinen Guard beeinflusst
# (Lesson nothra/tch-gastro-services#114: Anker ist die YAML-Struktur, nie eine Erwähnung). Bewusst ein Prozess
# statt `sed | awk`: awk beendet am nächsten Top-Level-Key, das SIGPIPE eines Vorgängers
# würde unter `set -o pipefail` als Fehlschlag durchschlagen. Nicht lesbare Datei → exit 1
# (fail-closed, Lesson nothra/tch-gastro-services#214), nicht stiller leerer Block.
poll_yaml_block() {
  [ -r "$1" ] || return 1
  awk -v key="^$2:" '
    { sub(/#.*/, "") }
    $0 ~ key { f=1; sub(/^[A-Za-z0-9_-]+:/, ""); if ($0 ~ /[^[:space:]]/) print; next }
    f && /^[A-Za-z0-9_-]+:/ { exit }
    f' "$1"
}

# Block-Anker statt dateiweiter Fragment-Greps (Review-Runde-2-Nitpick nothra/tch-gastro-services#284): derselbe
# Kommentar-Nachzug, der die AK3-Assertion in Runde 1 prosa-erfüllbar gemacht hätte
# (Lesson nothra/tch-gastro-services#114), könnte sonst auch hier greifen – jetzt, wo poll_yaml_block existiert,
# kostet das Ankern eine Zeile.
poll_yaml_block "$POLL_YML" jobs | grep -qxF -- '  factory-poll:'
assert_true "$?" "factory-poll-Job in factory-poll.yml"
poll_yaml_block "$POLL_YML" concurrency | grep -qxF -- '  group: factory-runtime'
assert_true "$?" "factory-poll hat concurrency-group (Concurrency=1, Idempotenz)"

# poll_trigger_guard <workflow-datei> – 0, wenn der on:-Block KEINEN schedule-/cron-
# Trigger enthält; non-zero bei Fund, leerem on:-Block oder unlesbarer Datei.
# Gesucht wird das Wort, nicht `schedule:` – so greift der Guard auch bei Flow-Notation
# (`on: {schedule: [...]}`) und gequotetem Key (`"schedule":`); Prosa kann nicht treffen,
# weil poll_yaml_block die Kommentare vorher entfernt hat.
# grep liest per Here-String statt aus einer Pipe: bei einem Treffer beendet `grep -q`
# sofort, ein schreibender Vorgänger liefe unter `pipefail` in ein SIGPIPE – und die
# vorangestellte Negation machte daraus ausgerechnet im Fund-Fall ein grünes Ergebnis.
poll_trigger_guard() {
  local on_block
  on_block="$(poll_yaml_block "$1" on)" || return 1
  [ -n "$on_block" ] || return 1
  ! grep -qE '(^|[^[:alnum:]_-])(schedule|cron)([^[:alnum:]_-]|$)' <<<"$on_block"
}

# poll_dispatch_guard <workflow-datei> – 0, wenn der on:-Block workflow_dispatch trägt.
# Kein expliziter [ -n "$on_block" ]-Guard wie bei poll_trigger_guard nötig: `grep` auf
# einen leeren Block scheitert ohnehin non-zero, das Verhalten ist identisch.
poll_dispatch_guard() {
  local on_block
  on_block="$(poll_yaml_block "$1" on)" || return 1
  grep -q 'workflow_dispatch' <<<"$on_block"
}

# poll_permission_guard <workflow-datei> <permissions-zeile-OHNE-Einrückung> – 0, wenn die
# Zeile (mit der zweispaltigen Einrückung des Blocks ergänzt) wörtlich im permissions:-Block
# steht. Dateiweites Suchen wäre hier wertlos: der WHY-Kommentar am Runtime-Step nennt
# „contents: write + issues: write" als Prosa und erfüllte einen `grep -q` auch dann, wenn
# der echte Block fehlt oder auf `contents: read` abgeschwächt ist (Lesson nothra/tch-gastro-services#114: Kommando ≠
# Prosa-Erwähnung). Wert als Daten behandeln (`-qxF --`).
poll_permission_guard() {
  local permissions_block
  permissions_block="$(poll_yaml_block "$1" permissions)" || return 1
  grep -qxF -- "  $2" <<<"$permissions_block"
}

poll_trigger_guard "$POLL_YML"
assert_true "$?" "#284 AK1: on:-Block von factory-poll.yml trägt keinen schedule:/cron-Trigger (Schedule stillgelegt)"

poll_dispatch_guard "$POLL_YML"
assert_true "$?" "#284 AK2: workflow_dispatch bleibt im on:-Block (manuell auslösbar)"

# AK3: die Bausteine, die beim Scharfschalten unverändert wiederverwendet werden.
# (factory-poll-Job und concurrency-group prüfen die zwei Assertions oben.)
poll_permission_guard "$POLL_YML" 'contents: write'
assert_true "$?" "#284 AK3: permissions-Block trägt contents: write unverändert"
poll_permission_guard "$POLL_YML" 'issues: write'
assert_true "$?" "#284 AK3: permissions-Block trägt issues: write unverändert"
grep -qF 'bash scripts/factory-poll.sh' "$POLL_YML"; assert_true "$?" "#284 AK3: Poll-Step ruft weiterhin scripts/factory-poll.sh auf"

# AK5/AK6 – Mutationsbelege: derselbe Guard-Ausdruck gegen mutierte Kopien, damit
# belegt ist, dass er zwischen echtem Trigger und Prosa unterscheidet und nicht nur
# zufällig grün ist (Lesson nothra/tch-gastro-services#286: Beleg muss denselben Assert-Ausdruck ausführen).
# Mutation per awk-Einfügung IN den bestehenden on:-Block – ein angehängtes zweites
# `on:` wäre ein Duplicate-Key-Dokument und würde nur zufällig treffen (Lesson nothra/tch-gastro-services#255).
TMP_POLL_GUARD="$(mktemp -d)"

# Je Mutant unten steht neben dem rot-erwarteten Beleg eine grüne Positivkontrolle auf ein
# ANDERES Signal derselben Datei (Review-Runde-2-Nitpick nothra/tch-gastro-services#284, Lesson nothra/tch-gastro-services#214): sonst teilen sich
# alle `! poll_*_guard "<mutant>"`-Belege ihren Fail-Pfad mit AK6 ("Datei nicht lesbar") – bliebe
# eine Mutanten-Datei aus (mktemp/Redirect schlägt fehl), wäre der Beleg grün, ohne dass die
# Mutation je geprüft wurde. Die Positivkontrolle belegt: Datei existiert, ist parsbar, und nur
# das mutierte Feld weicht ab.

awk '/^on:/{print; print "  schedule:"; print "    - cron: \"*/30 * * * *\""; next} 1' \
  "$POLL_YML" > "$TMP_POLL_GUARD/mit-schedule.yml"
! poll_trigger_guard "$TMP_POLL_GUARD/mit-schedule.yml"
assert_true "$?" "#284 AK5: wiedereingetragener schedule:+cron-Trigger macht den Guard rot (Mutationsbeleg)"
poll_dispatch_guard "$TMP_POLL_GUARD/mit-schedule.yml"
assert_true "$?" "#284 AK5: Positivkontrolle mit-schedule.yml – workflow_dispatch bleibt unberührt"

awk '/^on:/{print; print "  # schedule: erst wieder eintragen, wenn cron: gewollt ist"; next} 1' \
  "$POLL_YML" > "$TMP_POLL_GUARD/nur-kommentar.yml"
poll_trigger_guard "$TMP_POLL_GUARD/nur-kommentar.yml"
assert_true "$?" "#284 AK5: Kommentarzeile mit schedule/cron lässt den Guard grün (Struktur-, kein Prosa-Anker)"

# Wiedereintrag in Flow-Notation: dokumentiert ist Block-Notation, treffen muss der Guard
# trotzdem – sonst bewacht er nur die Schreibweise, die er erwartet.
awk '/^on:/{print "on: {schedule: [{cron: \"*/30 * * * *\"}]}"; next} /^  workflow_dispatch/{next} 1' \
  "$POLL_YML" > "$TMP_POLL_GUARD/flow-notation.yml"
! poll_trigger_guard "$TMP_POLL_GUARD/flow-notation.yml"
assert_true "$?" "#284 AK5: schedule-Wiedereintrag in Flow-Notation macht den Guard rot (Mutationsbeleg)"
poll_permission_guard "$TMP_POLL_GUARD/flow-notation.yml" 'contents: write'
assert_true "$?" "#284 AK5: Positivkontrolle flow-notation.yml – permissions-Block bleibt unberührt"

! poll_trigger_guard "$TMP_POLL_GUARD/gibt-es-nicht.yml"
assert_true "$?" "#284 AK6: nicht lesbare factory-poll.yml lässt den Guard fehlschlagen (fail-closed)"

# F2: der on:-Block darf beim Stilllegen nicht leer werden – ohne workflow_dispatch
# wäre der Workflow gar nicht mehr auslösbar.
awk '!/^  workflow_dispatch/' "$POLL_YML" > "$TMP_POLL_GUARD/ohne-dispatch.yml"
! poll_dispatch_guard "$TMP_POLL_GUARD/ohne-dispatch.yml"
assert_true "$?" "#284 F2: entferntes workflow_dispatch macht den Dispatch-Guard rot (Mutationsbeleg)"
poll_permission_guard "$TMP_POLL_GUARD/ohne-dispatch.yml" 'contents: write'
assert_true "$?" "#284 F2: Positivkontrolle ohne-dispatch.yml – permissions-Block bleibt unberührt"

# AK3-Mutanten: der WHY-Kommentar am Runtime-Step bleibt in beiden Kopien stehen und nennt
# „contents: write + issues: write" – ein dateiweiter grep wäre hier grün geblieben.
awk '!/^  (contents|issues): write$/' "$POLL_YML" > "$TMP_POLL_GUARD/ohne-permissions.yml"
! poll_permission_guard "$TMP_POLL_GUARD/ohne-permissions.yml" 'contents: write'
assert_true "$?" "#284 AK3: gelöschter permissions-Block macht den Guard rot (Mutationsbeleg)"
! poll_permission_guard "$TMP_POLL_GUARD/ohne-permissions.yml" 'issues: write'
assert_true "$?" "#284 AK3: gelöschtes issues: write macht den Guard rot (Mutationsbeleg)"
poll_dispatch_guard "$TMP_POLL_GUARD/ohne-permissions.yml"
assert_true "$?" "#284 AK3: Positivkontrolle ohne-permissions.yml – workflow_dispatch bleibt unberührt"

awk '{ sub(/^  contents: write$/, "  contents: read"); print }' \
  "$POLL_YML" > "$TMP_POLL_GUARD/contents-read.yml"
! poll_permission_guard "$TMP_POLL_GUARD/contents-read.yml" 'contents: write'
assert_true "$?" "#284 AK3: auf contents: read abgeschwächte permission macht den Guard rot (Mutationsbeleg)"
poll_permission_guard "$TMP_POLL_GUARD/contents-read.yml" 'issues: write'
assert_true "$?" "#284 AK3: Positivkontrolle contents-read.yml – issues: write bleibt unberührt"

! poll_permission_guard "$TMP_POLL_GUARD/gibt-es-nicht.yml" 'contents: write'
assert_true "$?" "#284 AK6: nicht lesbare Datei lässt auch den permissions-Guard fehlschlagen (fail-closed)"

rm -rf "$TMP_POLL_GUARD"

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

# ─── Issue-Sync: jeder Task hat ein GitHub-Issue-Pendant (nothra/tch-gastro-services#4, ADR-013) ───────
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

# ─── Zentraler Issue-Seam scripts/lib/create-issue.sh (nothra/tch-gastro-services#82, ADR-018) ─────────
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
# Regression F1 (Review nothra/tch-gastro-services#82): der no-repo-Pfad MUSS auch unter `set -euo pipefail` laufen –
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

# 13. Security-Guard (Review nothra/tch-gastro-services#82 H-1): reservierter 'factory::'-Präfix wird als Art- UND
# Aspekt-Label verworfen (nur die Pipeline setzt diese; verhindert Selbst-Trigger).
LOG="$TMP_SEAM/c13.log"; : > "$LOG"; ERR="$TMP_SEAM/c13.err"
out=$(FACTORY_REPO="test/repo" GH_LOG="$LOG" seam "T" "B" "factory::run" "security,factory::running" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "Seam: factory::-Labels → Issue trotzdem angelegt (exit 0)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Seam: factory::-Guard → stdout bleibt reine Nummer"
assert_true "$(! grep -q -- 'factory::' "$LOG"; echo $?)" "Seam: KEIN factory::-Label wird an gh übergeben (Art + Aspekt verworfen)"
grep -q -- '--label security' "$LOG"; assert_true "$?" "Seam: legitimes Aspekt-Label (security) bleibt trotz factory::-Nachbar erhalten"
grep -q 'reserviert' "$ERR"; assert_true "$?" "Seam: factory::-Guard warnt auf stderr (reserviert)"

rm -rf "$TMP_SEAM"

# ─── Idempotenz-Wrapper create_issue_idempotent (nothra/tch-gastro-services#207, ADR-040) ──────────────
echo ""
echo "Idempotenter Issue-Seam (#207, ADR-040):"

TMP_IDEM="$(mktemp -d)"; mkdir -p "$TMP_IDEM/bin"
# gh-Stub: 'issue list' liefert die in FAKE_OPEN vorkonfigurierten OFFENEN Kandidaten
# (Format exakt wie `-q '.[] | .number, .title'`: je Issue eine Nummer-Zeile, dann eine
# Titel-Zeile) und protokolliert seine Argumente nach LIST_LOG. FAKE_LIST_FAIL=1 simuliert
# einen Lookup-Fehler (gh-Exit ≠ 0). 'issue create' verhält sich wie im Seam-Stub: loggt nach
# GH_LOG, liefert FAKE_NUM; FAKE_BAD_LABEL lässt eine Anlage mit diesem --label-Wert scheitern
# (simuliert „Label existiert im Repo nicht" → prüft die Label-Degradation hinter dem Wrapper).
cat > "$TMP_IDEM/bin/gh" <<'GHEOF'
#!/bin/sh
if [ "$1 $2" = "issue list" ]; then
  [ -n "${LIST_LOG:-}" ] && printf '%s\n' "$*" >> "$LIST_LOG"
  [ -n "${FAKE_LIST_FAIL:-}" ] && exit 1
  printf '%s' "${FAKE_OPEN:-}"
  exit 0
fi
if [ "$1 $2" = "issue create" ]; then
  [ -n "${GH_LOG:-}" ] && printf '%s\n' "$*" >> "$GH_LOG"
  if [ -n "${FAKE_BAD_LABEL:-}" ]; then
    for w in "$@"; do [ "$w" = "$FAKE_BAD_LABEL" ] && exit 1; done
  fi
  echo "https://github.com/test/repo/issues/${FAKE_NUM:-123}"
  exit 0
fi
exit 0
GHEOF
chmod +x "$TMP_IDEM/bin/gh"

# idem <args…> – ruft create_issue_idempotent im Subshell mit Stub-gh auf (analog seam()).
idem() {
  PATH="$TMP_IDEM/bin:$PATH" FACTORY_REPO="test/repo" \
    bash -c 'source "$0"; create_issue_idempotent "$@"' "$SEAM_LIB" "$@"
}

open_204=$(printf '204\nRefactor foo bar\n')

# AC1 – offener Treffer mit exakt gleichem Titel → bestehende Nummer, KEINE Anlage
CLOG="$TMP_IDEM/ac1.create"; : > "$CLOG"
out=$(FAKE_OPEN="$open_204" GH_LOG="$CLOG" idem "Refactor foo bar" "Body" "enhancement" "tech-debt" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "AC1: offener Titel-Treffer → exit 0"
assert_true "$([[ "$out" = "204" ]]; echo $?)" "AC1: gibt bestehende Issue-Nummer (204) zurück"
assert_true "$([[ ! -s "$CLOG" ]]; echo $?)" "AC1: kein 'gh issue create' aufgerufen (kein Duplikat)"

# AC2 – kein offener Treffer → regulär anlegen (inkl. Art- + Aspekt-Label), neue Nummer
CLOG="$TMP_IDEM/ac2.create"; : > "$CLOG"
out=$(FAKE_OPEN="" GH_LOG="$CLOG" idem "Ganz neuer Titel" "Body" "enhancement" "tech-debt" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "AC2: kein Treffer → exit 0"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "AC2: neue Issue-Nummer (123) zurückgegeben"
grep -q -- '--label enhancement' "$CLOG"; assert_true "$?" "AC2: delegiert an create_issue MIT Art-Label"
grep -q -- '--label tech-debt' "$CLOG"; assert_true "$?" "AC2: delegiert MIT Aspekt-Label (Labels wie bisher)"

# AC3 – geschlossenes Issue blockiert nicht: der Lookup fragt --state open ab; ein
# geschlossenes Issue erscheint dort nicht (FAKE_OPEN leer) → neues Issue.
LLOG="$TMP_IDEM/ac3.list"; : > "$LLOG"; CLOG="$TMP_IDEM/ac3.create"; : > "$CLOG"
out=$(FAKE_OPEN="" LIST_LOG="$LLOG" GH_LOG="$CLOG" idem "Erledigter Titel" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "AC3: geschlossenes (nicht offenes) Issue → exit 0"
grep -q -- '--state open' "$LLOG"; assert_true "$?" "AC3: Lookup fragt ausschließlich offene Issues ab (--state open)"
grep -q -- 'issue create' "$CLOG"; assert_true "$?" "AC3: geschlossenes Issue blockiert nicht → neues Issue angelegt"

# AC5 – exakter Titelvergleich: Teilstring ist KEIN Treffer (clientseitig, nicht über die Suche)
CLOG="$TMP_IDEM/ac5.create"; : > "$CLOG"
open_sub=$(printf '50\nFix the whole thing\n')
out=$(FAKE_OPEN="$open_sub" GH_LOG="$CLOG" idem "Fix the" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "AC5: Teilstring-Kandidat → exit 0"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "AC5: Teilstring wird NICHT als Duplikat gewertet → neue Nummer"
grep -q -- 'issue create' "$CLOG"; assert_true "$?" "AC5: Teilstring → reguläre Anlage (kein False-Positive der Suche)"
# Umkehrung: Zieltitel enthält den Kandidaten als Teilstring – ebenfalls kein Treffer
CLOG="$TMP_IDEM/ac5b.create"; : > "$CLOG"
open_short=$(printf '51\nFix the\n')
out=$(FAKE_OPEN="$open_short" GH_LOG="$CLOG" idem "Fix the whole thing" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "AC5: Umkehr-Teilstring → exit 0"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "AC5: Umkehr-Teilstring (Kandidat ⊂ Ziel) → neue Nummer (kein Treffer)"
grep -q -- 'issue create' "$CLOG"; assert_true "$?" "AC5: Umkehr-Teilstring (Kandidat ⊂ Ziel) → ebenfalls Neuanlage"

# AC5 (Schärfe) – mehrere exakte Treffer: niedrigste (älteste) Nummer gewinnt
CLOG="$TMP_IDEM/ac5c.create"; : > "$CLOG"
open_multi=$(printf '308\nDoppelter Titel\n204\nDoppelter Titel\n')
out=$(FAKE_OPEN="$open_multi" GH_LOG="$CLOG" idem "Doppelter Titel" "B" "enhancement" 2>/dev/null)
assert_true "$([[ "$out" = "204" ]]; echo $?)" "AC5: mehrere exakte Treffer → niedrigste Nummer (204, nicht 308)"

# AC5 (Schärfe) – Tiebreak reihenfolge-unabhängig: niedrigste gewinnt auch bei umgekehrter
# Kandidaten-Reihenfolge. Deckt den `-lt`-false-Zweig ab (ein späterer HÖHERER Treffer ersetzt
# den bestehenden `best` NICHT).
CLOG="$TMP_IDEM/ac5d.create"; : > "$CLOG"
open_multi2=$(printf '204\nDoppelter Titel\n308\nDoppelter Titel\n')
out=$(FAKE_OPEN="$open_multi2" GH_LOG="$CLOG" idem "Doppelter Titel" "B" "enhancement" 2>/dev/null)
assert_true "$([[ "$out" = "204" ]]; echo $?)" "AC5: niedrigste Nummer gewinnt auch bei umgekehrter Reihenfolge (204 vor 308)"

# Defensiv-Guard (create-issue.sh: `''|*[!0-9]*)`): eine nicht-numerische „Nummer"-Zeile bei
# titelgleichem Kandidaten wird übersprungen (schützt das `-lt` vor nicht-numerischem Input),
# der echte numerische Treffer wird trotzdem gefunden. Erzwingt den sonst nie erreichten
# Guard-Zweig (lessons/testing.md: Exhaustiveness-Guards brauchen einen eigenen Test; bis nothra/tch-gastro-services#319
# stand die Regel in testing-standards.md).
CLOG="$TMP_IDEM/guard.create"; : > "$CLOG"
open_bad_num=$(printf 'x\nRefactor foo bar\n204\nRefactor foo bar\n')
out=$(FAKE_OPEN="$open_bad_num" GH_LOG="$CLOG" idem "Refactor foo bar" "B" "enhancement" 2>/dev/null); rc=$?
assert_exit 0 "$rc" "Guard: nicht-numerische Nummer-Zeile → exit 0 (kein -lt-Absturz)"
assert_true "$([[ "$out" = "204" ]]; echo $?)" "Guard: nicht-numerische Nummer übersprungen, echter Treffer (204) gefunden"
assert_true "$([[ ! -s "$CLOG" ]]; echo $?)" "Guard: Treffer trotz Müll-Zeile → keine Anlage"

# F1 – Lookup nicht durchführbar (gh-Fehler) → fail-open: regulär anlegen + stderr-Warnung
CLOG="$TMP_IDEM/f1.create"; : > "$CLOG"; ERR="$TMP_IDEM/f1.err"
out=$(FAKE_LIST_FAIL=1 GH_LOG="$CLOG" idem "Irgendein Titel" "B" "enhancement" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "F1: Lookup-Fehler → fail-open, Issue trotzdem angelegt (exit 0)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "F1: fail-open → neue Nummer auf stdout"
grep -q -- 'issue create' "$CLOG"; assert_true "$?" "F1: fail-open delegiert an reguläre Anlage"
assert_true "$([[ -s "$ERR" ]]; echo $?)" "F1: fail-open warnt auf stderr"

# F3 – stdout-Hygiene bei Treffer: stdout ist AUSSCHLIESSLICH die Nummer, Hinweis auf stderr
ERR="$TMP_IDEM/f3.err"
out=$(FAKE_OPEN="$open_204" idem "Refactor foo bar" "B" "enhancement" 2>"$ERR")
assert_true "$([[ "$out" = "204" ]]; echo $?)" "F3: Treffer → stdout ist reine Nummer (kein Hinweistext)"
assert_true "$([[ -s "$ERR" ]]; echo $?)" "F3: Treffer-Hinweis geht auf stderr, nicht stdout"

# F1/FS1-Kaskade – gar kein gh: Lookup unmöglich (fail-open) → Delegation an create_issue,
# das ohne gh fail-closed abbricht (exit ≠ 0). Netto entsteht kein Issue (korrekt).
mkdir -p "$TMP_IDEM/empty"; ERR="$TMP_IDEM/nogh.err"
out=$(env PATH="$TMP_IDEM/empty" "$(command -v bash)" -c 'source "$0"; create_issue_idempotent "T" "B" "enhancement"' "$SEAM_LIB" 2>"$ERR"); rc=$?
assert_exit 1 "$rc" "F1/FS1: kein gh → fail-open-Lookup kaskadiert in fail-closed-Anlage (exit 1)"
assert_true "$([[ -z "$out" ]]; echo $?)" "F1/FS1: kein gh → keine Nummer auf stdout"

# AC4 – Retry-Idempotenz (Regressionsschutz): zwei Läufe mit identischem Titel.
# Lauf 1: kein offenes Issue → legt an (nothra/tch-gastro-services#123). Lauf 2: das offene nothra/tch-gastro-services#123 existiert nun mit
# demselben Titel → Treffer, KEINE zweite Anlage. Netto: genau eine Anlage.
CLOG="$TMP_IDEM/ac4.create"; : > "$CLOG"
run1=$(FAKE_OPEN="" GH_LOG="$CLOG" idem "Wiederkehrender Fund" "B" "enhancement" 2>/dev/null)
open_123=$(printf '123\nWiederkehrender Fund\n')
run2=$(FAKE_OPEN="$open_123" GH_LOG="$CLOG" idem "Wiederkehrender Fund" "B" "enhancement" 2>/dev/null)
n_creates=$(grep -c -- 'issue create' "$CLOG")
assert_true "$([[ "$run1" = "123" && "$run2" = "123" ]]; echo $?)" "AC4: beide Läufe liefern dieselbe Nummer (123)"
assert_true "$([[ "$n_creates" -eq 1 ]]; echo $?)" "AC4: zwei Läufe, identischer Titel → genau EINE Anlage"

# Bestandspfad unberührt: create_issue bleibt direkt nutzbar (Delegation ändert ihn nicht)
CLOG="$TMP_IDEM/plain.create"; : > "$CLOG"
out=$(PATH="$TMP_IDEM/bin:$PATH" FACTORY_REPO="test/repo" GH_LOG="$CLOG" \
  bash -c 'source "$0"; create_issue "$@"' "$SEAM_LIB" "T" "B" "enhancement" 2>/dev/null)
assert_true "$([[ "$out" = "123" ]]; echo $?)" "Bestandspfad: create_issue weiterhin direkt nutzbar (unverändert)"

# Lookup ohne FACTORY_REPO/REPO: der no-repo-Zweig der repo_args-Ableitung → kein --repo an
# `gh issue list` (gh-Auto-Erkennung), der Treffer wird trotzdem gefunden.
LLOG="$TMP_IDEM/norepo.list"; : > "$LLOG"
out=$(PATH="$TMP_IDEM/bin:$PATH" FAKE_OPEN="$open_204" LIST_LOG="$LLOG" \
  bash -c 'unset FACTORY_REPO REPO GITHUB_REPOSITORY; source "$0"; create_issue_idempotent "Refactor foo bar" "B" "enhancement"' \
  "$SEAM_LIB" 2>/dev/null)
assert_true "$([[ "$out" = "204" ]]; echo $?)" "Lookup: ohne FACTORY_REPO/REPO findet Treffer (gh-Auto, no-repo-Zweig)"
assert_true "$(! grep -q -- '--repo' "$LLOG"; echo $?)" "Lookup: ohne Repo-Slug kein --repo an 'gh issue list'"

# W3: Alle drei Pfade laufen als bloßer Aufruf unter `set -euo pipefail` durch – nicht nur der
# Treffer-Pfad, sondern gerade die errexit-EMPFINDLICHEN No-Match- (while-read-Heredoc-Schleife)
# und Fail-open-Pfade (`raw=$(…) || return 2`, `existing=$(…) || rc=$?`). Ein künftiger
# errexit-Bruch dort würde stumm zum Retry-Duplikat führen – genau der nothra/tch-gastro-services#207-Fehlerfall.
rc=$(PATH="$TMP_IDEM/bin:$PATH" FACTORY_REPO="test/repo" FAKE_OPEN="$open_204" \
  bash -c 'set -euo pipefail; source "$0"; create_issue_idempotent "Refactor foo bar" "B" "enhancement" >/dev/null; echo "$?"' \
  "$SEAM_LIB" 2>/dev/null)
assert_true "$([[ "$rc" = "0" ]]; echo $?)" "W3: Treffer-Pfad läuft unter set -euo pipefail durch (rc=0)"
rc=$(PATH="$TMP_IDEM/bin:$PATH" FACTORY_REPO="test/repo" FAKE_OPEN="" GH_LOG=/dev/null \
  bash -c 'set -euo pipefail; source "$0"; create_issue_idempotent "Frischer Fund" "B" "enhancement" >/dev/null; echo "$?"' \
  "$SEAM_LIB" 2>/dev/null)
assert_true "$([[ "$rc" = "0" ]]; echo $?)" "W3: No-Match-Pfad läuft unter set -euo pipefail durch (rc=0)"
rc=$(PATH="$TMP_IDEM/bin:$PATH" FACTORY_REPO="test/repo" FAKE_LIST_FAIL=1 GH_LOG=/dev/null \
  bash -c 'set -euo pipefail; source "$0"; create_issue_idempotent "Frischer Fund" "B" "enhancement" >/dev/null; echo "$?"' \
  "$SEAM_LIB" 2>/dev/null)
assert_true "$([[ "$rc" = "0" ]]; echo $?)" "W3: Fail-open-Pfad läuft unter set -euo pipefail durch (rc=0)"

# W4: F2 (Label-Degradation + fail-closed-Anlage) bleibt hinter dem Wrapper erhalten. No-Match →
# Delegation an create_issue; ein abgelehntes Aspekt-Label degradiert auf nur-Art, das Issue
# entsteht trotzdem (exit 0), stdout bleibt reine Nummer.
CLOG="$TMP_IDEM/w4.create"; : > "$CLOG"; ERR="$TMP_IDEM/w4.err"
out=$(FAKE_OPEN="" FAKE_BAD_LABEL="tech-debt" GH_LOG="$CLOG" idem "Frischer Fund" "B" "enhancement" "tech-debt" 2>"$ERR"); rc=$?
assert_exit 0 "$rc" "W4: abgelehntes Aspekt-Label über Wrapper → Issue trotzdem (exit 0, Degradation)"
assert_true "$([[ "$out" = "123" ]]; echo $?)" "W4: Degradation über Wrapper → stdout bleibt reine Nummer"
tail -n1 "$CLOG" | grep -q -- '--label enhancement'; assert_true "$?" "W4: Fallback-Anlage trägt das Art-Label (enhancement)"
assert_true "$(! tail -n1 "$CLOG" | grep -q -- 'tech-debt'; echo $?)" "W4: Fallback-Anlage trägt das abgelehnte Aspekt-Label NICHT mehr"

rm -rf "$TMP_IDEM"

# AC6 – Geltungsbereich: die Bestands-Aufrufer nutzen NICHT den Idempotenz-Wrapper
assert_true "$(! grep -qE 'create_issue_idempotent' "$SCRIPTS_DIR/start-work.sh"; echo $?)" \
  "AC6: start-work.sh nutzt den Idempotenz-Wrapper NICHT (unverändert)"
assert_true "$(! grep -qE 'create_issue_idempotent' "$SCRIPTS_DIR/sync-issues.sh"; echo $?)" \
  "AC6: sync-issues.sh nutzt den Idempotenz-Wrapper NICHT (unverändert)"

# nothra/tch-gastro-services#207: die drei autonomen Pipeline-Skills rufen den Idempotenz-Wrapper auf
for sk in codify review security-review; do
  grep -q 'create_issue_idempotent' "$FACTORY_ROOT/.claude/commands/$sk.md"
  assert_true "$?" "#207: /$sk-Skill nutzt create_issue_idempotent (Retry-Duplikat-Guard)"
done

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

# ── nothra/tch-gastro-services#155: git-workflow.md verweist auf ADR-029 (server-seitiger main-Schutz) ──
# AC3 bündelt Direktive + Rationale auf getrennt editierbaren Zeilen → je eigene
# Assertion (codifizierte nothra/tch-gastro-services#117-Regel), sonst bleibt das Framing ungetestet.
GITWF="$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md"
# (0) Verweis-Ziel existiert: sonst zeigen die ADR-029-Verweise ins Leere, ohne dass
# die grep-Guards (die nur git-workflow.md prüfen) das bemerken (dangling reference).
assert_true "$([[ -f "$FACTORY_ROOT/docs/factory/adr/029-branch-protection-main-ruleset.md" ]]; echo $?)" \
  "#155: ADR-029-Datei vorhanden (Verweis-Ziel nicht dangling)"
# (a) Direktive: der Verweis auf ADR-029 ist vorhanden.
grep -q 'ADR-029' "$GITWF"
assert_true "$?" "#155: git-workflow.md verweist auf ADR-029 (main-Ruleset)"
# (b) Rationale (separierbar): der pre-push-Hook ist als lokales, *umgehbares* Feedback
# eingeordnet – die Begründung, warum server-seitige Durchsetzung nötig ist. Token
# 'umgehbar' steht nur im Framing-Satz, unabhängig vom Verweis-Satz (ADR-029).
grep -q 'umgehbar' "$GITWF"
assert_true "$?" "#155: git-workflow.md ordnet den pre-push-Hook als umgehbares lokales Feedback ein (AC3-Rationale)"

# ─── Bug nothra/tch-gastro-services#8: Check-Skripte robust gegen Leerzeichen im Pfad ──────────────────
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
grep -q 'bash-gotchas.md' "$FACTORY_ROOT/docs/factory/FACTORY.md"
assert_true "$?" "bash-gotchas.md ist in FACTORY.md referenziert"

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

# K-2 (Issue nothra/tch-gastro-services#261): Laufzeit-Beweis der set-e-Sicherheit für den grep|head|while-Block
# (pipeline_summary's Codify-Regelzeilen-Ausgabe) gegen ein 0-Treffer-File unter set -e.
ZERO_WHILE_LOOP=$(mktemp); printf '# nur ein Header, keine Regel-Zeilen\n' > "$ZERO_WHILE_LOOP"
# Korrektes Idiom (|| true nach done) → kein Abbruch, rc=0:
( set -euo pipefail; grep "^- " "$ZERO_WHILE_LOOP" 2>/dev/null | head -3 | while IFS= read -r line; do echo "    ${line}"; done || true ) 2>/dev/null
assert_exit 0 "$?" "Issue #261 RICHTIG-Idiom (|| true nach done) ist set-e-sicher bei 0 Treffern"
# Gegenprobe: ohne || true bricht es unter set -e ab (beweist, dass der Test scharf ist):
( set -euo pipefail; grep "^- " "$ZERO_WHILE_LOOP" 2>/dev/null | head -3 | while IFS= read -r line; do echo "    ${line}"; done ) 2>/dev/null
assert_true "$([ $? -ne 0 ]; echo $?)" "Gegenprobe: ohne || true bricht der grep|head|while-Block unter set -e ab (K-2)"
rm -f "$ZERO_WHILE_LOOP"

# (3) run-pipeline.sh Codify-Regelzeilen-Block nutzt das set-e-sichere Idiom (|| true nach
# done) – Issue nothra/tch-gastro-services#261. Block-isoliert statt Datei-weitem Fragment-Grep (Review-Finding
# Runde 2/3, Lesson zu Reihenfolge-Guards aus nothra/tch-gastro-services#114/#265: Anker ist die exakte Aufruf-
# Zeile, nie ein Kommando-Fragment) – awk extrahiert nur den Block zwischen der
# Codify-Pipeline und ihrem "done", analog zur Job-Block-Isolation aus nothra/tch-gastro-services#255. Anders als
# dort schließt der Block hier Start- UND Endzeile bewusst mit ein (nicht aus), weil
# genau die "done"-Zeile selbst geprüft werden muss. Ein-Wort-Anker als Variable
# (nicht zweimal als Regex-Literal), damit Original- und Mutations-Extraktion (unten)
# nicht auseinanderlaufen können.
codify_block_awk='/grep "\^- " "\$codify_file" 2>\/dev\/null \| head -3 \| while/{f=1} f{print} f&&/done/{exit}'
codify_regelzeilen_block="$(awk "$codify_block_awk" "$PIPELINE")"
assert_true "$([[ -n "$codify_regelzeilen_block" ]]; echo $?)" "Codify-Regelzeilen-Block ist extrahierbar (Issue #261)"
printf '%s' "$codify_regelzeilen_block" | grep -qE 'done \|\| true'
assert_true "$?" "run-pipeline.sh Codify-Regelzeilen-Block ist set-e-sicher (|| true nach done, Issue #261)"

# Schärfe-Beweis: ein unabhängiges "done || true" an anderer Stelle im Skript darf den
# Guard nicht fälschlich grün machen, wenn der Codify-Block selbst ungesichert wäre.
MUT_PIPELINE=$(mktemp)
sed -e 's/    done || true/    done/' "$PIPELINE" > "$MUT_PIPELINE"
printf '\ndone || true\n' >> "$MUT_PIPELINE"
mut_block="$(awk "$codify_block_awk" "$MUT_PIPELINE")"
! printf '%s' "$mut_block" | grep -qE 'done \|\| true'
assert_true "$?" "Schärfe-Beweis: unabhängiges 'done || true' anderswo täuscht den Block-Guard nicht (Issue #261)"
rm -f "$MUT_PIPELINE"

# nothra/tch-gastro-services#261 AC2/AC3: End-to-end-Beweis über den echten pipeline_summary()-Pfad (--dry-run),
# dass 1-3 Treffer unverändert ausgegeben werden und >3 Treffer bei 3 gekappt + Hinweis
# ergänzt wird. Bisher nur strukturell begründet (|| true wirkt nur bei vorangehendem
# Fehlschlag, ändert im Treffer-Fall nichts) – hier zusätzlich empirisch belegt
# (/test-Vollständigkeitsprüfung), analog zum nothra/tch-gastro-services#91-Dry-Run-Scaffold.
if [ "$HAS_YQ" = 1 ]; then
  TMP_261="$(mktemp -d)"
  mkdir -p "$TMP_261/scripts/checks" "$TMP_261/scripts/lib" "$TMP_261/tasks" "$TMP_261/docs/factory"
  cp "$PIPELINE" "$TMP_261/scripts/"
  cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_261/scripts/checks/"
  cp "$FACTORY_ROOT/factory.defaults.yml" "$TMP_261/"
  cp_pipeline_libs "$TMP_261"
  echo "# ctx" > "$TMP_261/docs/factory/PROJECT-CONTEXT.md"
  echo "# Task 3: codify-regelzeilen-ac" > "$TMP_261/tasks/task-3-codify-regelzeilen-ac.md"
  printf '## Empfehlung\nAPPROVED\n' > "$TMP_261/tasks/review-3.md"
  git -C "$TMP_261" init -q
  git -C "$TMP_261" add .
  git -C "$TMP_261" -c user.email="t@t.com" -c user.name="t" commit -q -m init

  # AC2: 1-3 Treffer → alle Zeilen unverändert ausgegeben, kein "… weitere"-Hinweis
  printf -- '- Regel A\n- Regel B\n' > "$TMP_261/tasks/codify-3.md"
  git -C "$TMP_261" add .; git -C "$TMP_261" -c user.email="t@t.com" -c user.name="t" commit -q -m ac2
  ac2_out=$(bash "$TMP_261/scripts/run-pipeline.sh" 3 --dry-run 2>&1 || true)
  printf '%s' "$ac2_out" | grep -qF '2 neue Regel(n) hinzugefügt'
  assert_true "$?" "#261 AC2: 1-3 Treffer – Regelzahl korrekt im Summary"
  printf '%s' "$ac2_out" | grep -qF -- '- Regel A'
  assert_true "$?" "#261 AC2: 1-3 Treffer – erste Regelzeile unverändert ausgegeben"
  printf '%s' "$ac2_out" | grep -qF -- '- Regel B'
  assert_true "$?" "#261 AC2: 1-3 Treffer – zweite Regelzeile unverändert ausgegeben"
  printf '%s' "$ac2_out" | grep -qF '(weitere in tasks/codify-3.md)'
  assert_true "$([[ $? -ne 0 ]]; echo $?)" "#261 AC2: bei nur 2 Treffern erscheint kein '… weitere'-Hinweis"

  # AC3: >3 Treffer → erste 3 Zeilen ausgegeben, vierte gekappt, Hinweis ergänzt
  printf -- '- Regel A\n- Regel B\n- Regel C\n- Regel D\n- Regel E\n' > "$TMP_261/tasks/codify-3.md"
  git -C "$TMP_261" add .; git -C "$TMP_261" -c user.email="t@t.com" -c user.name="t" commit -q -m ac3
  ac3_out=$(bash "$TMP_261/scripts/run-pipeline.sh" 3 --dry-run 2>&1 || true)
  printf '%s' "$ac3_out" | grep -qF '5 neue Regel(n) hinzugefügt'
  assert_true "$?" "#261 AC3: >3 Treffer – reale Regelzahl (5) im Summary, nicht gekappt"
  printf '%s' "$ac3_out" | grep -qF -- '- Regel C'
  assert_true "$?" "#261 AC3: >3 Treffer – dritte Regelzeile noch ausgegeben"
  printf '%s' "$ac3_out" | grep -qF -- '- Regel D'
  assert_true "$([[ $? -ne 0 ]]; echo $?)" "#261 AC3: >3 Treffer – vierte Regelzeile NICHT ausgegeben (Kappung bei 3)"
  printf '%s' "$ac3_out" | grep -qF '(weitere in tasks/codify-3.md)'
  assert_true "$?" "#261 AC3: >3 Treffer – '… weitere'-Hinweis erscheint"
  rm -rf "$TMP_261"
else
  skip_yq "#261 AC2/AC3: End-to-end Codify-Regelzeilen-Ausgabe (1-3 / >3 Treffer)"
fi

# ─── Stufe-2.5: Factory-Config Phase 1b – run-pipeline liest die Config (nothra/tch-gastro-services#25) ─
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
  cp_pipeline_libs "$TMP_CFG"
  echo "# ctx" > "$TMP_CFG/docs/factory/PROJECT-CONTEXT.md"; echo "# Task 1: x" > "$TMP_CFG/tasks/task-1-x.md"
  git -C "$TMP_CFG" init -q; git -C "$TMP_CFG" add .
  git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  cfg_out=$(bash "$TMP_CFG/scripts/run-pipeline.sh" 1 --dry-run 2>&1 || true)
  printf '%s' "$cfg_out" | grep -q 'Starte: /implement 1 (model: claude-opus-5-5, max 20 turns)'
  assert_true "$?" "Phase 1b: run-pipeline löst implement aus der Config zu opus/20 auf (end-to-end)"
  # Team-Override greift: factory.config.yml setzt implement auf 5 Turns → 5 statt 20
  printf 'skills:\n  implement: { max_turns: 5 }\n' > "$TMP_CFG/factory.config.yml"
  git -C "$TMP_CFG" add .; git -C "$TMP_CFG" -c user.email="t@t.com" -c user.name="t" commit -q -m override
  ovr_out=$(bash "$TMP_CFG/scripts/run-pipeline.sh" 1 --dry-run 2>&1 || true)
  printf '%s' "$ovr_out" | grep -q 'Starte: /implement 1 (model: claude-opus-5-5, max 5 turns)'
  assert_true "$?" "Phase 1b: Team-Override (factory.config.yml) übersteuert Defaults (Turns 20→5)"

  rm -rf "$TMP_CFG"

  # nothra/tch-gastro-services#91 Turn-Budget-Dry-Run: review + security-review zeigen max 30 turns im Output (AC Lücke 2).
  # Bestehender mock review-2.md (APPROVED) sorgt dafür, dass Review-Loop sofort endet und
  # die Pipeline bis Phase 5 (security-review) läuft – beide "Starte:"-Zeilen erscheinen.
  TMP_DRY91="$(mktemp -d)"; mkdir -p "$TMP_DRY91/scripts/checks" "$TMP_DRY91/scripts/lib" "$TMP_DRY91/tasks" "$TMP_DRY91/docs/factory"
  cp "$PIPELINE" "$TMP_DRY91/scripts/"; cp "$CHECKS_DIR/config-validation-check.sh" "$TMP_DRY91/scripts/checks/"; cp "$DEFAULTS" "$TMP_DRY91/"
  cp_pipeline_libs "$TMP_DRY91"
  echo "# ctx" > "$TMP_DRY91/docs/factory/PROJECT-CONTEXT.md"
  echo "# Task 2: budget-dry" > "$TMP_DRY91/tasks/task-2-budget-dry.md"
  printf '## Empfehlung\nAPPROVED\n' > "$TMP_DRY91/tasks/review-2.md"
  git -C "$TMP_DRY91" init -q; git -C "$TMP_DRY91" add .
  git -C "$TMP_DRY91" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  dry91_out=$(bash "$TMP_DRY91/scripts/run-pipeline.sh" 2 --dry-run 2>&1 || true)
  printf '%s' "$dry91_out" | grep -q '/review 2 (model: claude-opus-5-5, max 30 turns)'
  assert_true "$?" "#91: dry-run zeigt /review mit max 30 turns (Turn-Budget, Lücke 2)"
  printf '%s' "$dry91_out" | grep -q '/security-review 2 (model: claude-opus-5-5, max 30 turns)'
  assert_true "$?" "#91: dry-run zeigt /security-review mit max 30 turns (Turn-Budget, Lücke 2)"
  # nothra/tch-gastro-services#212 F4: --dry-run läuft bis zum Ende (APPROVED-Review) und markiert die Endzustands-
  # Verifikation als übersprungen, statt sie auszuführen/abzubrechen.
  printf '%s' "$dry91_out" | grep -q 'DRY-RUN.*Endzustands-Verifikation übersprungen'
  assert_true "$?" "#212 F4: --dry-run markiert Endzustands-Verifikation als übersprungen (kein Abbruch)"
  # nothra/tch-gastro-services#312: dieselbe Dry-Run-Ausnahme für das jetzt fail-closed Security-Gate. Ohne sie blockierte
  # jeder --dry-run ab Phase 5 – dort läuft kein Skill, also entsteht nie ein Security-Report.
  # Direkte Assertion statt bloß transitiver Absicherung über die Erfolgs-Ausgabe darunter.
  printf '%s' "$dry91_out" | grep -q 'DRY-RUN.*Security-Gate übersprungen'
  assert_true "$?" "#312: --dry-run markiert das Security-Gate als übersprungen (kein Abbruch)"
  printf '%s' "$dry91_out" | grep -q 'Pipeline erfolgreich abgeschlossen'
  assert_true "$?" "#212 F4: --dry-run erreicht die Erfolgs-Ausgabe (Verifikation blockiert nicht)"
  rm -rf "$TMP_DRY91"
else
  skip_yq "YAML-Parse, Config-Werte (implement/codify/default) und End-to-End-Resolution"
fi

# ─── Stufe-2.6: Config-Validierungs-Gate (nothra/tch-gastro-services#36, ADR-010) ──────────────────────
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

  # Positiv (Grenzfall, nothra/tch-gastro-services#348/ADR-051): max_turns = 80 ist die neue Ceiling → exit 0
  printf 'skills:\n  implement: { max_turns: 80 }\n' > "$GTMP/ceil80.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/ceil80.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #348: max_turns = 80 (neue Ceiling) → exit 0"

  # Negativ (Grenzfall, nothra/tch-gastro-services#348/ADR-051): max_turns = 81 liegt über der neuen Ceiling
  printf 'skills:\n  implement: { max_turns: 81 }\n' > "$GTMP/ceil81.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/ceil81.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #348: max_turns = 81 (über neuer Ceiling) → fail-closed"

  # ── Mindest-Tier für sicherheitsrelevante Skills (Task 241, Regel 5) ────────
  # AK1 (Negativ): security-review.tier unter heavy → fail-closed. light ist ein
  #   gültiger model_tiers-Key (passiert Regel 2/4a) → nur Regel 5 kann greifen;
  #   die Meldungs-Assertion belegt, dass genau Regel 5 (nicht ein Fremdpfad) fällt.
  printf 'skills:\n  security-review: { tier: light }\n' > "$GTMP/sr-tier-light.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/sr-tier-light.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #241 AK1: security-review.tier=light (unter Mindest-Tier) → fail-closed"
  printf '%s' "$out" | grep -qi 'Mindest-Tier' && printf '%s' "$out" | grep -q 'security-review'
  assert_true "$?" "Gate #241 AK1: Fehlermeldung nennt Mindest-Tier + Skill (Regel 5 isoliert)"

  # AK2 (Negativ): review.tier unter heavy → fail-closed (analog AK1)
  printf 'skills:\n  review: { tier: light }\n' > "$GTMP/rv-tier-light.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/rv-tier-light.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #241 AK2: review.tier=light (unter Mindest-Tier) → fail-closed"
  printf '%s' "$out" | grep -qi 'Mindest-Tier' && printf '%s' "$out" | grep -qw 'review'
  assert_true "$?" "Gate #241 AK2: Fehlermeldung nennt Mindest-Tier + Skill (Regel 5 isoliert)"

  # AK3a (Negativ, reale Config): Override führt security-review.tier_by_size ein →
  #   fail-closed. Gegen die realen Defaults greift bereits die Unbekannte-Key-Regel 2
  #   (die Defaults lassen den Pfad bewusst weg) — Regel 5 ist hier Defense-in-Depth.
  printf 'skills:\n  security-review: { tier_by_size: { signal: diff, threshold: 150 } }\n' > "$GTMP/sr-tbs.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/sr-tbs.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #241 AK3a: security-review.tier_by_size (reale Defaults) → fail-closed"

  # AK3b (Negativ, Regel 5 isoliert): Custom-Defaults DEKLARIEREN den tier_by_size-Pfad
  #   für security-review (→ Regel 2 hat nichts zu beanstanden) und die Form ist laut
  #   4c gültig (→ 4c passiert) — dennoch muss Regel 5 fallen, weil security-review
  #   keine größenabhängige Tier-Wahl haben darf. So testet AK3 wirklich Regel 5, nicht
  #   einen Fremdpfad (nothra/tch-gastro-services#214: Ziel-Pfad isolieren + pfadspezifisches Signal assertieren).
  printf 'schemaVersion: 1\nmodel_tiers:\n  heavy: m-heavy\n  light: m-light\nskills:\n  security-review:\n    tier: heavy\n    max_turns: 14\n    tier_by_size: { signal: diff, threshold: 150 }\n  review:\n    tier: heavy\n    max_turns: 14\ndefault:\n  tier: light\n  max_turns: 10\n' > "$GTMP/def-sr-tbs.yml"
  # Expliziter leerer Override, damit NICHT die reale factory.config.yml als Default-$2
  # einspringt (deren Fremd-Keys würden sonst Regel 2 vor Regel 5 auslösen).
  : > "$GTMP/empty-ovr.yml"
  out="$(bash "$GATE" "$GTMP/def-sr-tbs.yml" "$GTMP/empty-ovr.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #241 AK3b: security-review.tier_by_size (Regel 5 isoliert) → fail-closed"
  printf '%s' "$out" | grep -q 'tier_by_size' && printf '%s' "$out" | grep -q 'security-review'
  assert_true "$?" "Gate #241 AK3b: Fehlermeldung nennt tier_by_size + Skill (Regel 5, nicht Regel 2)"

  # AK4 (Positiv): review.tier_by_size bleibt override-bar, solange tier=heavy → exit 0
  printf 'skills:\n  review: { tier_by_size: { signal: diff, threshold: 300 } }\n' > "$GTMP/rv-tbs.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/rv-tbs.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #241 AK4: review.tier_by_size-Override (tier bleibt heavy) → exit 0 (Nicht-Regression ADR-038)"

  # AK5 (Positiv): Override, der security-review/review unangetastet lässt → exit 0
  printf 'skills:\n  test: { max_turns: 15 }\n' > "$GTMP/untouched.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/untouched.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #241 AK5: Override ohne security-review/review-Änderung → exit 0"

  # AK6 (Positiv): explizite redundante Bestätigung des Minimums (tier=heavy) → exit 0
  printf 'skills:\n  security-review: { tier: heavy }\n' > "$GTMP/sr-tier-heavy.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/sr-tier-heavy.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #241 AK6: security-review.tier=heavy (redundant zum Default) → exit 0"

  # ── model_tiers.heavy ist nicht override-bar (Task 249, Regel 6) ───────────
  # AK1 (Negativ): abweichender Wert wird abgelehnt, unabhängig davon, dass er
  #   strukturell gültig ist (passiert Regel 2/4a) — nur Regel 6 kann greifen.
  printf 'model_tiers:\n  heavy: claude-sonnet-5\n' > "$GTMP/heavy-diff.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/heavy-diff.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #249 AK1: model_tiers.heavy-Override (abweichender Wert) → fail-closed"
  printf '%s' "$out" | grep -q 'model_tiers.heavy' && printf '%s' "$out" | grep -q 'nicht override-bar'
  assert_true "$?" "Gate #249 AK1: Fehlermeldung nennt den Pfad + 'nicht override-bar' (Regel 6, nicht Regel 2)"

  # AK2 (Negativ): redundante Bestätigung des exakten Defaults-Werts wird ebenfalls
  #   abgelehnt — der Pfad ist grundsätzlich gesperrt, nicht nur bei Abweichung. Wert
  #   bewusst dynamisch aus den Defaults gelesen (nicht wie AK1 literal), damit der
  #   Test bei einer künftigen Modell-ID-Änderung in factory.defaults.yml weiterhin
  #   exakt den Defaults-Wert trifft, statt gegen ein einfrierendes Literal zu altern.
  default_heavy="$(yq eval '.model_tiers.heavy' "$DEFAULTS")"
  printf 'model_tiers:\n  heavy: %s\n' "$default_heavy" > "$GTMP/heavy-same.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/heavy-same.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #249 AK2: model_tiers.heavy-Override (redundant zum Default) → fail-closed"

  # AK3 (Positiv, Nicht-Regression): model_tiers.light bleibt frei override-bar.
  printf 'model_tiers:\n  light: claude-sonnet-5\n' > "$GTMP/light-diff.yml"
  bash "$GATE" "$DEFAULTS" "$GTMP/light-diff.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #249 AK3: model_tiers.light-Override bleibt erlaubt (Nicht-Regression)"

  # AK4 (Positiv): reiner Default-Lauf ohne Override bleibt grün.
  bash "$GATE" "$DEFAULTS" >/dev/null 2>&1
  assert_true "$?" "Gate #249 AK4: reiner Default-Lauf (kein Override) → exit 0"

  # ── Config-Validation Root-Typ-Guard (Task 254) ─────────────────────────────
  # AK1 (Negativ): Skalar-Root im Override → explizite "kein Mapping"-Meldung, nicht
  #   die irreführende max_turns-Meldung aus Regel 4b.
  printf 'just_a_string\n' > "$GTMP/root-scalar.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/root-scalar.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #254 AK1: Skalar-Root im Override → fail-closed"
  printf '%s' "$out" | grep -qi 'kein YAML-Mapping' && ! printf '%s' "$out" | grep -qi 'max_turns'
  assert_true "$?" "Gate #254 AK1: Fehlermeldung nennt 'kein YAML-Mapping', nicht die max_turns-Folgemeldung"

  # AK2 (Negativ): Boolean-Root im Override → dieselbe explizite Meldung.
  printf 'true\n' > "$GTMP/root-bool.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/root-bool.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #254 AK2: Boolean-Root im Override → fail-closed"
  printf '%s' "$out" | grep -qi 'kein YAML-Mapping'
  assert_true "$?" "Gate #254 AK2: Fehlermeldung nennt 'kein YAML-Mapping'"

  # AK3 (Negativ): Sequence-Root im Override → dieselbe explizite Meldung.
  printf -- '- a\n- b\n' > "$GTMP/root-seq.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/root-seq.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #254 AK3: Sequence-Root im Override → fail-closed"
  printf '%s' "$out" | grep -qi 'kein YAML-Mapping'
  assert_true "$?" "Gate #254 AK3: Fehlermeldung nennt 'kein YAML-Mapping'"

  # AK4 (Negativ): Mehrdokument-Override (zwei gültige Mapping-Dokumente via '---') →
  #   eigene, von der "kein Mapping"-Meldung unterscheidbare Meldung.
  printf 'skills:\n  implement: { max_turns: 5 }\n---\nskills:\n  test: { max_turns: 10 }\n' > "$GTMP/root-multidoc.yml"
  out="$(bash "$GATE" "$DEFAULTS" "$GTMP/root-multidoc.yml" 2>&1)"; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "Gate #254 AK4: Mehrdokument-Override → fail-closed"
  printf '%s' "$out" | grep -qi 'mehrere YAML-Dokumente' && ! printf '%s' "$out" | grep -qi 'kein YAML-Mapping'
  assert_true "$?" "Gate #254 AK4: Fehlermeldung nennt Mehrdokument-Struktur, unterscheidbar vom 'kein Mapping'-Fall"

  # AK5 (Positiv, Nicht-Regression): gültiger Override (ein Dokument, Mapping-Root)
  #   verhält sich unverändert — deckt sich mit dem bereits oben laufenden "ok.yml"-Fall.
  bash "$GATE" "$DEFAULTS" "$GTMP/ok.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #254 AK5: gültiger Override (Mapping-Root, ein Dokument) → exit 0 (Nicht-Regression)"

  # AK6 (Positiv): kein Override-File vorhanden → neue Root-Typ-/Mehrdokument-Checks
  #   werden übersprungen (wie bei den bestehenden Override-only-Regeln). Explizit ein
  #   garantiert nicht existierender Pfad als $2 (statt kein $2), sonst defaultet das
  #   Gate auf das reale $REPO_ROOT/factory.config.yml (Zeile "OVERRIDE=..."), das
  #   selbst ein gültiger Override ist — der Skip-Pfad wäre dann nicht isoliert getestet
  #   (Review-Finding, Task 254).
  bash "$GATE" "$DEFAULTS" "$GTMP/does-not-exist.yml" >/dev/null 2>&1
  assert_true "$?" "Gate #254 AK6: kein Override-File vorhanden → neue Checks übersprungen, exit 0"

  rm -rf "$GTMP"
else
  skip_yq "Gate-Validierung (Positiv/Negativ-Fixtures)"
fi

# ─── Config-Validation als eigener CI-Required-Check (Task 255, ADR-041) ─────
echo ""
echo "Config-Validation CI-Wiring (Task 255, ADR-041):"

grep -q 'config-validation:' "$CI_FILE"
assert_true "$?" "config-validation-Job in factory-ci.yml"

# Job-Block isoliert extrahieren (nicht das ganze File scannen) — sonst würde die
# "kein Node/pnpm"-Prüfung (AK7) an einem Fremd-Job (z. B. lint/test) vorbeirutschen,
# der pnpm durchaus nutzt. Abbruchregeln siehe ci_job_block (oben, Lesson nothra/tch-gastro-services#255).
cv_job_block="$(ci_job_block config-validation "$CI_FILE")"
assert_true "$([[ -n "$cv_job_block" ]]; echo $?)" "config-validation-Job-Block ist extrahierbar"

printf '%s' "$cv_job_block" | grep -q 'actions/checkout'
assert_true "$?" "config-validation-Job checkt das Repo aus"

printf '%s' "$cv_job_block" | grep -qi 'yq'
assert_true "$?" "config-validation-Job stellt yq bereit (Gate-Prerequisite, ADR-009 §A)"

printf '%s' "$cv_job_block" | grep -q 'config-validation-check.sh'
assert_true "$?" "config-validation-Job ruft config-validation-check.sh auf"

printf '%s' "$cv_job_block" | grep -q 'GITHUB_WORKSPACE/factory.defaults.yml' \
  && printf '%s' "$cv_job_block" | grep -q 'GITHUB_WORKSPACE/factory.config.yml'
assert_true "$?" "AK3: Job ruft das Gate explizit mit den Pfaden der realen Repo-Dateien auf"

# AK3 (Positions-Reihenfolge): das Gate liest strikt positional ($1=Defaults,
# $2=Override, s. Script-Header). Reine Anwesenheits-Prüfung beider Pfade würde
# einen vertauschten Aufruf nicht erkennen (Review-Finding Runde 1, Task 255).
cv_defaults_line="$(printf '%s\n' "$cv_job_block" | grep -n 'GITHUB_WORKSPACE/factory.defaults.yml' | head -1 | cut -d: -f1)"
cv_config_line="$(printf '%s\n' "$cv_job_block" | grep -n 'GITHUB_WORKSPACE/factory.config.yml' | head -1 | cut -d: -f1)"
assert_true "$([[ -n "$cv_defaults_line" && -n "$cv_config_line" && "$cv_defaults_line" -lt "$cv_config_line" ]]; echo $?)" \
  "AK3: defaults-Pfad steht als \$1 VOR dem config-Pfad als \$2 (Positions-Reihenfolge)"

! printf '%s' "$cv_job_block" | grep -qE 'pnpm/action-setup|actions/setup-node'
assert_true "$?" "AK7: config-validation-Job braucht kein Node/pnpm-Setup"

# ── Behavior-Level: derselbe Aufruf wie im config-validation-Job, real ausgeführt ──
# Ersetzt strukturell die entfernte "Gate nothra/tch-gastro-services#249 AK5"-Zeile (AK5) auf CI-Wiring-Ebene:
# reine Wiring-Greps oben belegen nur, DASS der Job etwas Passendes aufruft, nicht
# DASS der Aufruf tatsächlich grün/rot läuft (Review-Finding Runde 1, Task 255 —
# Lesson nothra/tch-gastro-services#212: "Deterministisches Gate braucht E2E-Verhaltenstest, nicht nur Wiring-Grep").
if [ "$HAS_YQ" = 1 ] && [ -f "$GATE" ]; then
  # AK2 (Positiv, Nicht-Regression): realer, aktueller Repo-Stand → exit 0.
  bash "$GATE" "$FACTORY_ROOT/factory.defaults.yml" "$FACTORY_ROOT/factory.config.yml" >/dev/null 2>&1
  assert_true "$?" "AK2: config-validation-Job-Aufruf gegen reale Repo-Dateien → exit 0"

  CVTMP="$(mktemp -d)"

  # AK1 (Negativ): unbekannter Key in einer Kopie des realen factory.config.yml.
  cp "$FACTORY_ROOT/factory.config.yml" "$CVTMP/unknown-key.yml"
  printf '\nbogus_unknown_key_ak1: 1\n' >> "$CVTMP/unknown-key.yml"
  bash "$GATE" "$FACTORY_ROOT/factory.defaults.yml" "$CVTMP/unknown-key.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "AK1: unbekannter Key in factory.config.yml → config-validation-Job schlägt fehl"

  # AK4 (Negativ, Task-249-Regression): model_tiers.heavy-Override in einer Kopie.
  # Echter yq-Merge in den bestehenden model_tiers-Block (nicht per printf einen
  # zweiten Top-Level-Key anhängen) — sonst löst yq das Duplicate-Key-Dokument per
  # last-key-wins auf und model_tiers.light verschwindet, wodurch der Test kein
  # realistisches Override-Szenario mehr prüft (Review-Finding Runde 3, Task 255).
  cp "$FACTORY_ROOT/factory.config.yml" "$CVTMP/heavy-override.yml"
  yq -i eval '.model_tiers.heavy = "claude-sonnet-5"' "$CVTMP/heavy-override.yml"
  bash "$GATE" "$FACTORY_ROOT/factory.defaults.yml" "$CVTMP/heavy-override.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "AK4: model_tiers.heavy-Override (Task-249-Regression) → config-validation-Job schlägt fehl"

  rm -rf "$CVTMP"
else
  skip_yq "Config-Validation CI-Wiring (Behavior-Level AK1/AK2/AK4)"
fi

# ─── Stufe-3: Config-Wizards / Single-Source-Begründung (nothra/tch-gastro-services#35, ADR-011) ───────
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

# D (Task 249, AK8): model_tiers-Beispielblock widerspricht der Gate-Policy nicht mehr —
# 'heavy' darf dort nicht länger als überschreibbares Beispiel auftauchen. Block isolieren
# (von der "Knopf: model_tiers"-Überschrift bis zur nächsten "Knopf:"-Überschrift), analog
# zur bestehenden skills_block-Extraktion oben (Schreibweise-/Positions-unabhängig).
model_tiers_block=$(awk '/Knopf: model_tiers/{f=1} f&&/Knopf:/&&!/Knopf: model_tiers/{f=0} f' "$EXAMPLE" 2>/dev/null || true)
printf '%s\n' "$model_tiers_block" | grep -qE '^#[[:space:]]*heavy:'
assert_true "$([ $? -ne 0 ]; echo $?)" "D (Task 249 AK8): model_tiers-Beispielblock zeigt 'heavy' nicht mehr als Beispiel-Knopf"
printf '%s\n' "$model_tiers_block" | grep -qi 'nicht override-bar'
assert_true "$?" "D (Task 249 AK8): model_tiers-Beispielblock nennt 'heavy' explizit als nicht override-bar"
# Negativ-Kontrolle (F1-analog): die Positiv-Regex matcht, wenn der verbotene Beispiel-Knopf
# tatsächlich vorhanden wäre — belegt, dass der Test scharf ist und nicht zufällig grün läuft.
printf '#   heavy: claude-opus-4-8\n' | grep -qE '^#[[:space:]]*heavy:'
assert_true "$?" "D (Task 249 AK8): Positiv-Kontrolle — Regex erkennt einen vorhandenen 'heavy:'-Beispiel-Knopf"

# ─── start-work.sh: Worktree-Isolation (Kern-Vorkehrung gegen Session-Kollisionen, nothra/tch-gastro-services#74) ──
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
# Config der Fixture (nothra/tch-gastro-services#431): start-work liest commands.install / start_work.hint aus dem Quellbaum.
cp "$FACTORY_ROOT/factory.defaults.yml" "$REPO_SW/"
cat > "$REPO_SW/factory.config.yml" <<'SWCFG'
start_work:
  hint: |
    Vor dem ersten 'pnpm test:e2e': pnpm db:seed
    (.env.local wurde kopiert – die geteilte lokale DB kennt die SEED_ADMIN_*-Daten evtl. noch nicht)
SWCFG
git -C "$REPO_SW" add factory.defaults.yml factory.config.yml
git -C "$REPO_SW" commit -q -m "chore: config der Fixture"
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

# ─── Art-Label bei der Issue-Anlage aus dem Branch-Typ ableiten (nothra/tch-gastro-services#80) ─────────
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

# nothra/tch-gastro-services#82: --labels reicht Aspekt-Labels (zusätzlich zum Art-Label) an den Seam durch.
LOG_ASP="$TMP_SW/gh-asp.log"; : > "$LOG_ASP"
( cd "$REPO_SW" && env GH_LOG="$LOG_ASP" PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
    FACTORY_WORKTREE_BASE="$TMP_SW/wt-asp" FACTORY_WT_SKIP_INSTALL=1 \
    bash "$SW" eee feature --labels security,test ) >/dev/null 2>&1
{ grep -q -- '--label enhancement' "$LOG_ASP" && grep -q -- '--label security' "$LOG_ASP" \
  && grep -q -- '--label test' "$LOG_ASP"; }
assert_true "$?" "#82: start-work --labels reicht Aspekt-Labels an den Seam durch (Art + Aspekte)"

# nothra/tch-gastro-services#82: FACTORY_ASPECT_LABELS wirkt wie --labels (Env-Variante).
LOG_ENV="$TMP_SW/gh-env.log"; : > "$LOG_ENV"
( cd "$REPO_SW" && env GH_LOG="$LOG_ENV" PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" FACTORY_ASPECT_LABELS="security" \
    FACTORY_WORKTREE_BASE="$TMP_SW/wt-env" FACTORY_WT_SKIP_INSTALL=1 \
    bash "$SW" fff feature ) >/dev/null 2>&1
grep -q -- '--label security' "$LOG_ENV"
assert_true "$?" "#82: FACTORY_ASPECT_LABELS reicht Aspekt-Labels an den Seam durch"

# nothra/tch-gastro-services#82 (F2-Regression): --labels als letztes Argument ohne Wert → klare usage()-Meldung + exit 1,
# kein wortloser Abbruch durch 'shift 2' unter set -e.
asp_err=$( cd "$REPO_SW" && PATH="$TMP_SW/bin:$PATH" FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
  bash "$SW" "meine beschreibung" --labels 2>&1 ); asp_rc=$?
assert_exit 1 "$asp_rc" "#82: start-work --labels ohne Wert → exit 1 (kein wortloser set-e-Abbruch)"
printf '%s' "$asp_err" | grep -q -- '--labels erwartet einen Wert'
assert_true "$?" "#82: start-work --labels ohne Wert nennt die usage()-Ursache"

# ─── nothra/tch-gastro-services#236: .env.local in den neuen Worktree spiegeln ─────────────────────────
# Die Datei ist gitignored und wandert beim 'worktree add' nicht mit, alle DEV-Skripte
# laden sie aber per 'dotenv -e .env.local' (nothra/tch-gastro-services#228). Fixtures von oben werden bewusst
# wiederverwendet (gh-Stub, Wegwerf-Repo REPO_SW/REPO_IP, FACTORY_WT_SKIP_INSTALL=1).
echo ""
echo "#236 .env.local-Spiegelung in neue Worktrees:"

# run_start_work <worktree-basis> <task-id> <desc> [extra-env]
# start-work.sh im Worktree-Default gegen REPO_SW; gibt stdout+stderr zurück, damit die
# Output-Kriterien (Kopier-/Überspringen-Meldung, db:seed-Hinweis) prüfbar sind.
run_start_work() {
  # "${@:4}" statt ${4:-}: das gewollte Word-Splitting bleibt, die zusätzliche (ungewollte)
  # Pathname-Expansion des Werts entfällt.
  ( cd "$REPO_SW" && env "${@:4}" PATH="$TMP_SW/bin:$PATH" \
      FACTORY_DIR="$REPO_SW" FACTORY_REPO="acme/demo" \
      FACTORY_WORKTREE_BASE="$1" FACTORY_WT_SKIP_INSTALL=1 \
      bash "$SW" "$2" "$3" ) 2>&1
}

# AK2/AK7: bewusst VOR dem Anlegen der Quelle – so ist „Quelle fehlt" echt und nicht
# nur ein Nebeneffekt einer späteren Testreihenfolge.
WT_NOENV="$TMP_SW/wt-236-noenv/feature-780-demo-noenv"
OUT_NOENV=$(run_start_work "$TMP_SW/wt-236-noenv" 780 demo-noenv); RC_NOENV=$?
assert_exit 0 "$RC_NOENV" "#236 AK2: fehlende .env.local im Quellbaum (\$FACTORY_DIR) → start-work endet mit exit 0"
# Existenz-Anker vor jeder Abwesenheits-Prüfung: „keine Datei unter <pfad>" ist auch dann wahr,
# wenn es <pfad> gar nicht gibt – ein Tippfehler oder ein geändertes Slug-Schema in start-work.sh
# (WORKDIR="$WT_BASE/${BRANCH_NAME//\//-}") entwertete die Assertion sonst lautlos.
assert_true "$([ -d "$WT_NOENV" ]; echo $?)" \
  "#236 AK2: der Worktree wurde angelegt (Existenz-Anker für die Abwesenheits-Prüfung)"
[ ! -e "$WT_NOENV/.env.local" ]
assert_true "$?" "#236 AK2: ohne Quelle entsteht keine .env.local im Worktree"
assert_absent "$OUT_NOENV" 'pnpm db:seed' "#236 AK7: ohne Kopie kein db:seed-Hinweis im Abschluss-Output"

# Quelle im Quellbaum ($FACTORY_DIR, in dieser Fixture zugleich der Haupt-Baum):
# Modus 600 (AK5) + eindeutiger Inhalt (AK1 prüft byte-identisch).
printf 'DATABASE_URL=postgres://demo\nSEED_ADMIN_EMAIL=a@b\n' > "$REPO_SW/.env.local"
chmod 600 "$REPO_SW/.env.local"

OUT_COPY=$(run_start_work "$TMP_SW/wt-236-env" 781 demo-env)
WT_ENV="$TMP_SW/wt-236-env/feature-781-demo-env/.env.local"
cmp -s "$REPO_SW/.env.local" "$WT_ENV"
assert_true "$?" "#236 AK1: .env.local liegt byte-identisch im neuen Worktree"
printf '%s' "$OUT_COPY" | grep -qF '.env.local kopiert (Quelle:'
assert_true "$?" "#236 AK1: der Output nennt das Kopieren der .env.local"
assert_true "$(ls_mode_matches "$WT_ENV" '-rw-------'; echo $?)" \
  "#236 AK5: die Kopie behält Modus 600"
printf '%s' "$OUT_COPY" | grep -qF 'pnpm db:seed'
assert_true "$?" "#236 AK6: nach der Kopie nennt der Abschluss-Output pnpm db:seed"
# AK6 fordert Direktive UND Begründung („die geteilte lokale DB kennt die SEED_ADMIN_*-Daten
# evtl. noch nicht"). Ohne eigene Assertion ließe sich die Begründungszeile ersatzlos löschen,
# ohne dass die Suite es merkt (Lesson nothra/tch-gastro-services#117: je separierbaren AK-Teil eine eigene Assertion).
printf '%s' "$OUT_COPY" | grep -qF 'SEED_ADMIN_*-Daten evtl. noch nicht'
assert_true "$?" "#236 AK6: der db:seed-Hinweis nennt auch seine Begründung (SEED_ADMIN_*-Daten)"

# Diskriminierung für 'cp -p': bei einer 600er-Quelle liefert auch ein 'cp' OHNE -p am Ziel 600
# (die umask kann nur Bits entfernen) – erst eine 664er-Quelle trennt die beiden Varianten.
# Das 'umask 022' macht die Trennung umgebungsunabhängig: unter einer laxen umask (002/000)
# legte auch die -p-lose Variante 664 an und der Test bliebe grün, obwohl '-p' entfernt wurde.
chmod 664 "$REPO_SW/.env.local"
( umask 022; run_start_work "$TMP_SW/wt-236-mode" 786 demo-envmode >/dev/null )
assert_true "$(ls_mode_matches "$TMP_SW/wt-236-mode/feature-786-demo-envmode/.env.local" '-rw-rw-r--'; echo $?)" \
  "#236 AK5: cp -p überträgt den Quellmodus (664 bleibt 664, wird nicht umask-reduziert)"
chmod 600 "$REPO_SW/.env.local"

# AK3: derselbe Branch/dieselbe Basis erneut → Worktree wird wiederverwendet, die dort
# abweichende Datei bleibt unangetastet (fail-safe: nie fremde Konfiguration zerstören).
# Referenzdatei statt String-Vergleich: 'cmp -s' belegt „unverändert" byte-genau, eine Command
# Substitution schluckte den Trailing-Newline (wie AK1 oben).
printf 'LOKAL_ANGEPASST=1\n' | tee "$WT_ENV" > "$TMP_SW/env-lokal-referenz"
OUT_KEEP=$(run_start_work "$TMP_SW/wt-236-env" 781 demo-env)
cmp -s "$TMP_SW/env-lokal-referenz" "$WT_ENV"
assert_true "$?" "#236 AK3: vorhandene .env.local im Worktree bleibt byte-identisch erhalten"
printf '%s' "$OUT_KEEP" | grep -qF '.env.local existiert im Worktree bereits'
assert_true "$?" "#236 AK3: der Output weist auf das Überspringen hin"
# Pfadgenau auf das Spec-Fehlerszenario „wiederverwendeter Worktree": der zweite Lauf legt nichts
# neu an, sondern nimmt einen der beiden Wiederverwendungs-Zweige (start-work.sh:208/210).
# Bewusst NICHT auf „Worktree existiert bereits" festgenagelt: welcher der beiden greift, hängt an
# einem exakten String-Vergleich gegen `git worktree list --porcelain`, und git meldet dort den
# AUFGELÖSTEN Pfad. Unter einem symlink-behafteten Pfad (macOS: mktemp -d unter /var/folders →
# /private/var/folders) greift deshalb der Nachbar-Zweig. Vorbestehende Fragilität aus nothra/tch-gastro-services#74,
# außerhalb dieses Scopes (Task-Notiz nothra/tch-gastro-services#236).
printf '%s' "$OUT_KEEP" | grep -qF 'wird wiederverwendet'
assert_true "$?" "#236 AK3: der zweite Lauf verwendet den vorhandenen Worktree wieder"
assert_absent "$OUT_KEEP" 'Worktree + Branch angelegt' "#236 AK3: der zweite Lauf legt keinen Worktree neu an"
# Diskriminierung beider Assertions: der ERSTE Lauf gegen dieselbe Basis meldet genau umgekehrt.
# Ohne ihn blieben sie auch bei einem Output-Umbau grün, der beide Meldungen entfernt.
printf '%s' "$OUT_COPY" | grep -qF 'Worktree + Branch angelegt'
assert_true "$?" "#236 AK3: Diskriminierung – der erste Lauf meldet die Neuanlage"
assert_absent "$OUT_COPY" 'wird wiederverwendet' "#236 AK3: Diskriminierung – der erste Lauf meldet keine Wiederverwendung"

# Der Ziel-Guard prüft '-e ODER -L': ein DEFEKTER Symlink ist für -e unsichtbar, ist aber
# vorhandene lokale Konfiguration. Ohne die -L-Alternative ersetzte cp ihn und zerstörte genau
# das, was AK3 schützt (Lesson nothra/tch-gastro-services#258: OR-Fragment mit nie feuernder Alternative).
run_start_work "$TMP_SW/wt-236-symtgt" 787 demo-symtgt >/dev/null
WT_SYMTGT="$TMP_SW/wt-236-symtgt/feature-787-demo-symtgt/.env.local"
rm -f "$WT_SYMTGT"
# Eigener Sentinel je Test (nicht mit dem Quell-Symlink-Fall weiter unten geteilt): entstünde die
# geteilte Datei durch eine Regression doch, prüfte der andere Test in Wahrheit einen INTAKTEN
# Symlink und würde mit irreführender Ursache rot.
ln -s "$TMP_SW/existiert-nicht-ziel" "$WT_SYMTGT"
OUT_SYMTGT=$(run_start_work "$TMP_SW/wt-236-symtgt" 787 demo-symtgt)
{ [ -L "$WT_SYMTGT" ] && [ ! -e "$WT_SYMTGT" ]; }
assert_true "$?" "#236 AK3: defekter Ziel-Symlink bleibt Symlink (wird nicht durch die Kopie ersetzt)"
printf '%s' "$OUT_SYMTGT" | grep -qF '.env.local existiert im Worktree bereits'
assert_true "$?" "#236 AK3: defekter Ziel-Symlink erzeugt die Überspringen-Meldung"
rm -f "$WT_SYMTGT"

# AK4: Opt-out. Diskriminierung ist durch AK1 oben belegt – dieselbe Quelle wird dort
# kopiert, hier nicht.
WT_SKIP="$TMP_SW/wt-236-skipenv/feature-782-demo-skipenv"
OUT_SKIP=$(run_start_work "$TMP_SW/wt-236-skipenv" 782 demo-skipenv "FACTORY_WT_SKIP_ENV=1")
# „Der Lauf ist wirklich durchgelaufen"-Anker: ohne ihn wären die Abwesenheits-Assertions auch
# dann grün, wenn start-work vor dem Kopier-Schritt abgebrochen wäre (Lesson nothra/tch-gastro-services#214).
printf '%s' "$OUT_SKIP" | grep -q 'Bereit!'
assert_true "$?" "#236 AK4: der Lauf erreicht den Abschluss-Output (Anker für die Abwesenheits-Prüfungen)"
assert_true "$([ -d "$WT_SKIP" ]; echo $?)" \
  "#236 AK4: der Worktree wurde angelegt (Existenz-Anker für die Abwesenheits-Prüfung)"
[ ! -e "$WT_SKIP/.env.local" ]
assert_true "$?" "#236 AK4: FACTORY_WT_SKIP_ENV=1 kopiert die .env.local nicht"
assert_absent "$OUT_SKIP" 'pnpm db:seed' "#236 AK4: Opt-out erzeugt auch keinen db:seed-Hinweis"

# Fehlerszenario: Quelle ist ein Verzeichnis → der reguläre Datei-Test (-f) greift nicht,
# behandelt wird der Fall wie „Quelle fehlt" (kein Sonderfall-Handling).
mv "$REPO_SW/.env.local" "$TMP_SW/env-backup"
mkdir "$REPO_SW/.env.local"
WT_ENVDIR="$TMP_SW/wt-236-envdir/feature-784-demo-envdir"
run_start_work "$TMP_SW/wt-236-envdir" 784 demo-envdir >/dev/null
assert_exit 0 "$?" "#236 Fehlerfall: Verzeichnis als Quelle → exit 0 (wie fehlende Quelle)"
assert_true "$([ -d "$WT_ENVDIR" ]; echo $?)" \
  "#236 Fehlerfall: der Worktree wurde angelegt (Existenz-Anker für die Abwesenheits-Prüfung)"
[ ! -e "$WT_ENVDIR/.env.local" ]
assert_true "$?" "#236 Fehlerfall: Verzeichnis als Quelle wird nicht kopiert"
rmdir "$REPO_SW/.env.local"
mv "$TMP_SW/env-backup" "$REPO_SW/.env.local"

# Quelle ist ein Symlink AUF EINE DATEI: '-f' dereferenziert, und 'cp -p' folgt dem Link (kein
# -P/-d) → im Worktree entsteht eine vollwertige Datei-Kopie. Das ist gewolltes Verhalten (Spec:
# „regulärer Datei-Test als Vorbedingung"), hier gepinnt, damit ein späterer Wechsel auf 'cp -a'
# o. Ä. auffällt. NUR ein defekter Symlink fällt durch '-f' (Fall darunter).
mv "$REPO_SW/.env.local" "$TMP_SW/env-real"
ln -s "$TMP_SW/env-real" "$REPO_SW/.env.local"
WT_SYMSRC="$TMP_SW/wt-236-symsrc/feature-788-demo-symsrc/.env.local"
run_start_work "$TMP_SW/wt-236-symsrc" 788 demo-symsrc >/dev/null
{ [ -f "$WT_SYMSRC" ] && [ ! -L "$WT_SYMSRC" ] && cmp -s "$TMP_SW/env-real" "$WT_SYMSRC"; }
assert_true "$?" "#236: Symlink als Quelle wird als echte Datei-Kopie materialisiert (kein Symlink im Worktree)"

# Quelle ist ein DEFEKTER Symlink → fällt durch '-f' und wird wie „Quelle fehlt" behandelt.
rm "$REPO_SW/.env.local"
ln -s "$TMP_SW/existiert-nicht-quelle" "$REPO_SW/.env.local"
WT_SYMDEAD="$TMP_SW/wt-236-symdead/feature-789-demo-symdead"
run_start_work "$TMP_SW/wt-236-symdead" 789 demo-symdead >/dev/null
assert_exit 0 "$?" "#236 Fehlerfall: defekter Symlink als Quelle → exit 0 (wie fehlende Quelle)"
assert_true "$([ -d "$WT_SYMDEAD" ]; echo $?)" \
  "#236 Fehlerfall: der Worktree wurde angelegt (Existenz-Anker für die Abwesenheits-Prüfung)"
[ ! -e "$WT_SYMDEAD/.env.local" ]
assert_true "$?" "#236 Fehlerfall: defekter Symlink als Quelle wird nicht kopiert"
rm "$REPO_SW/.env.local"
mv "$TMP_SW/env-real" "$REPO_SW/.env.local"

# Fehlerszenario: Kopieren schlägt fehl (Quelle nicht lesbar) → Warnung, KEIN Abbruch;
# unter 'set -euo pipefail' darf start-work nicht wortlos enden. Als root ist chmod 000
# wirkungslos (Lesetest würde gelingen) → dann lautes Skip statt falsch-grün.
if [ "$(id -u)" != "0" ]; then
  chmod 000 "$REPO_SW/.env.local"
  OUT_FAIL=$(run_start_work "$TMP_SW/wt-236-envfail" 785 demo-envfail); RC_FAIL=$?
  chmod 600 "$REPO_SW/.env.local"
  assert_exit 0 "$RC_FAIL" "#236 Fehlerfall: unlesbare Quelle → start-work läuft weiter (exit 0)"
  printf '%s' "$OUT_FAIL" | grep -qF '.env.local konnte nicht kopiert werden'
  assert_true "$?" "#236 Fehlerfall: unlesbare Quelle erzeugt eine Warnung"
  printf '%s' "$OUT_FAIL" | grep -q 'Bereit!'
  assert_true "$?" "#236 Fehlerfall: der Abschluss-Output wird trotz Kopier-Fehler erreicht"
  assert_absent "$OUT_FAIL" 'pnpm db:seed' "#236 Fehlerfall: fehlgeschlagene Kopie erzeugt keinen db:seed-Hinweis"
else
  echo "  • #236 Fehlerfall unlesbare Quelle – übersprungen (Suite läuft als root)"
fi

# Fehlerszenario: 'cp' scheitert, NACHDEM das Ziel entstanden ist – Abbruch mitten im Schreiben
# (ENOSPC/EIO) oder nur das '-p' (chmod/utimes) misslingt (exFAT/SMB). Ohne Aufräumen bliebe ein
# Rest liegen, den der AK3-Guard („existiert bereits – wird nicht überschrieben") bei JEDEM
# Folgelauf konservierte: der kaputte Zustand wäre permanent, Symptom wieder CredentialsSignin
# (nothra/tch-gastro-services#228). Der bereits unlesbar getestete Fall deckt das nicht ab – dort scheitert cp am open()
# der Quelle, das Ziel entsteht nie. Ein echtes cp lässt sich nicht zum Teilabbruch zwingen;
# der PATH-Stub (dieselbe Mechanik wie der gh-Stub dieses Blocks) stellt genau diesen Zustand her.
cat > "$TMP_SW/bin/cp" << 'CPSTUB'
#!/usr/bin/env bash
printf 'HALB_KOPIERT=' > "${@: -1}"   # Ziel angelegt, Inhalt unvollständig
exit 1
CPSTUB
chmod +x "$TMP_SW/bin/cp"
WT_PARTIAL="$TMP_SW/wt-236-envpartial/feature-790-demo-envpartial"
OUT_PARTIAL=$(run_start_work "$TMP_SW/wt-236-envpartial" 790 demo-envpartial); RC_PARTIAL=$?
rm -f "$TMP_SW/bin/cp"
assert_exit 0 "$RC_PARTIAL" "#236 Fehlerfall: cp-Teilabbruch → start-work läuft weiter (exit 0)"
assert_true "$([ -d "$WT_PARTIAL" ]; echo $?)" \
  "#236 Fehlerfall: der Worktree wurde angelegt (Existenz-Anker für die Abwesenheits-Prüfung)"
printf '%s' "$OUT_PARTIAL" | grep -qF '.env.local konnte nicht kopiert werden'
assert_true "$?" "#236 Fehlerfall: cp-Teilabbruch erzeugt eine Warnung"
[ ! -e "$WT_PARTIAL/.env.local" ]
assert_true "$?" "#236 Fehlerfall: der halb kopierte Rest wird entfernt, nicht liegengelassen"
# Diskriminierung: derselbe Worktree, diesmal mit echtem cp – der Zustand ist reparierbar und
# nicht durch den AK3-Guard eingefroren. Ohne das Aufräumen oben bliebe hier der Rest stehen.
run_start_work "$TMP_SW/wt-236-envpartial" 790 demo-envpartial >/dev/null
cmp -s "$REPO_SW/.env.local" "$WT_PARTIAL/.env.local"
assert_true "$?" "#236 Fehlerfall: der Folgelauf kopiert vollständig (Teilabbruch ist nicht permanent)"

# Fehlerszenario: am Worktree-Pfad liegt eine REGULÄRE DATEI. start-work nimmt dann den
# Wiederverwendungs-Zweig (:210) und läuft weiter – der Kopier-Block darf diesen Ablauf nicht
# verkürzen. Ohne den '-d'-Guard scheitern dort cp UND rm mit ENOTDIR ('rm -f' unterdrückt nur
# ENOENT); die rm-Zeile steht in keiner Bedingung, also bricht 'set -e' den Lauf WORTLOS ab –
# ohne Warnung und ohne die Schritte 3–5, die vor diesem PR noch erreicht wurden.
# Referenzpunkt ist bewusst „Schritt 3 wird erreicht", nicht 'Bereit!': dass Schritt 3 an
# seinem eigenen 'mkdir -p' scheitert, ist vorbestehendes nothra/tch-gastro-services#74-Verhalten (der :210-Zweig kennt
# keinen Nicht-Verzeichnis-Pfad) und außerhalb dieses Scopes – gemessen wird nur, dass der
# Kopier-Block den Abbruchpunkt nicht nach vorne zieht.
WT_NOTDIR_BASE="$TMP_SW/wt-236-notdir"
mkdir -p "$WT_NOTDIR_BASE"
: > "$WT_NOTDIR_BASE/feature-791-demo-notdir"
OUT_NOTDIR=$(run_start_work "$WT_NOTDIR_BASE" 791 demo-notdir)
# Existenz-Anker: der Pfad ist wirklich eine reguläre Datei – ein geändertes Slug-Schema in
# start-work.sh entwertete den ganzen Testfall sonst lautlos (er liefe gegen einen freien Pfad).
assert_true "$([ -f "$WT_NOTDIR_BASE/feature-791-demo-notdir" ]; echo $?)" \
  "#236 Fehlerfall: am Worktree-Pfad liegt eine reguläre Datei (Anker für den Nicht-Verzeichnis-Fall)"
printf '%s' "$OUT_NOTDIR" | grep -qF 'wird wiederverwendet'
assert_true "$?" "#236 Fehlerfall: Nicht-Verzeichnis am Worktree-Pfad nimmt den Wiederverwendungs-Zweig"
printf '%s' "$OUT_NOTDIR" | grep -qF '3/5  Task-Datei anlegen'
assert_true "$?" "#236 Fehlerfall: Nicht-Verzeichnis am Worktree-Pfad bricht den Lauf nicht im Kopier-Block ab"
assert_absent "$OUT_NOTDIR" '.env.local in den Worktree spiegeln' \
  "#236 Fehlerfall: der Kopier-Block wird bei einem Nicht-Verzeichnis gar nicht erst betreten"
# Bewusst auf die Kommando-Präfixe der beiden Aufrufe des Blocks verankert und NICHT auf den
# Fehlertext 'Not a directory': den erzeugt in Schritt 3 auch das vorbestehende
# 'mkdir -p "$WORKDIR/tasks"' – eine Assertion darauf wäre aus dem falschen Grund rot.
assert_absent "$OUT_NOTDIR" 'cp: ' \
  "#236 Fehlerfall: Nicht-Verzeichnis am Worktree-Pfad erzeugt keine rohe cp-Fehlerzeile"
assert_absent "$OUT_NOTDIR" 'rm: ' \
  "#236 Fehlerfall: Nicht-Verzeichnis am Worktree-Pfad erzeugt keine rohe rm-Fehlerzeile"

# Fehlerszenario: das Aufräumen selbst scheitert (nicht nur das cp). Ein schreibgeschütztes
# Zielverzeichnis, ein Fremd-'rm' auf PATH – der Grund ist egal, die Zeile darf den Lauf nie
# beenden. start-work.sh ruft 'rm' an genau EINER Stelle auf (der Aufräumzeile), der PATH-Stub
# trifft also präzise sie und nichts sonst. Die Kombination aus beiden Stubs ist nötig: ohne
# den cp-Stub wird die Aufräumzeile gar nicht erreicht.
cat > "$TMP_SW/bin/cp" << 'CPSTUB'
#!/usr/bin/env bash
printf 'HALB_KOPIERT=' > "${@: -1}"
exit 1
CPSTUB
cat > "$TMP_SW/bin/rm" << 'RMSTUB'
#!/usr/bin/env bash
exit 1
RMSTUB
chmod +x "$TMP_SW/bin/cp" "$TMP_SW/bin/rm"
OUT_RMFAIL=$(run_start_work "$TMP_SW/wt-236-rmfail" 792 demo-rmfail); RC_RMFAIL=$?
rm -f "$TMP_SW/bin/cp" "$TMP_SW/bin/rm"
assert_exit 0 "$RC_RMFAIL" "#236 Fehlerfall: fehlgeschlagenes Aufräumen → start-work läuft weiter (exit 0)"
printf '%s' "$OUT_RMFAIL" | grep -qF '.env.local konnte nicht kopiert werden'
assert_true "$?" "#236 Fehlerfall: fehlgeschlagenes Aufräumen erzeugt trotzdem die Warnung"
printf '%s' "$OUT_RMFAIL" | grep -q 'Bereit!'
assert_true "$?" "#236 Fehlerfall: der Abschluss-Output wird trotz fehlgeschlagenem Aufräumen erreicht"

# AK8: In-Place-Modus – der Arbeitsbaum IST der Haupt-Baum, es gibt nichts zu kopieren.
printf 'DATABASE_URL=postgres://demo\n' > "$REPO_IP/.env.local"
OUT_IP=$( cd "$REPO_IP" && PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_IP" FACTORY_REPO="acme/demo" FACTORY_NO_WORKTREE=1 \
    bash "$SW" 783 demo-ip 2>&1 )
# „Der Lauf ist wirklich durchgelaufen"-Anker vor den Abwesenheits-Assertions (Lesson nothra/tch-gastro-services#214):
# der In-Place-Zweig macht zusätzlich checkout/rebase gegen das Bare-Remote und könnte davor enden.
printf '%s' "$OUT_IP" | grep -q 'Bereit!'
assert_true "$?" "#236 AK8: der In-Place-Lauf erreicht den Abschluss-Output (Anker für die Abwesenheits-Prüfungen)"
assert_absent "$OUT_IP" '.env.local kopiert (Quelle:' "#236 AK8: In-Place-Modus führt keine Kopieraktion aus"
assert_absent "$OUT_IP" 'pnpm db:seed' "#236 AK8: In-Place-Modus gibt keinen db:seed-Hinweis"

# Reihenfolge „Kopie VOR pnpm install" (Spec-Hinweis: die Datei soll auch bei fehlgeschlagener
# Installation daliegen). Alle Läufe oben setzen FACTORY_WT_SKIP_INSTALL=1 und decken sie nicht
# ab → Positionsvergleich der beiden echten Aufrufzeilen (Lesson „Reihenfolge-/Präsenz-Guards":
# Anker ist die exakte Kommandozeile, nie ein Fragment), fail-closed bei fehlendem Anker.
sw_cp_line=$(grep -nF 'cp -p "$FACTORY_DIR/.env.local" "$WORKDIR/.env.local"' "$SW" | head -1 | cut -d: -f1)
sw_inst_line=$(grep -nF 'eval "$INSTALL_COMMAND"' "$SW" | head -1 | cut -d: -f1)
{ [ -n "$sw_cp_line" ] && [ -n "$sw_inst_line" ] && [ "$sw_cp_line" -lt "$sw_inst_line" ]; }
assert_true "$?" "#236: der .env.local-Kopierschritt steht vor dem Install-Schritt im Worktree"

# AK9: Doku-Drift im selben PR nachgezogen. Die Mehrwort-Prosa-Anker laufen über flat_286()
# (Definition am Dateikopf): ein Doku-Reflow bräche einen zeilengebundenen `grep -qF`-Anker
# sonst lautlos – den Präsenz-Guard rot, den Abwesenheits-Guard grün (Lesson nothra/tch-gastro-services#240/#249/#286).
sw_header=$(awk '/^set -euo pipefail/{exit} {print}' "$SW")
# Die Extraktion selbst belegen (nothra/tch-gastro-services#255, hier in Fail-open-Richtung): ändert sich der Sentinel
# (z. B. 'set -Eeuo pipefail'), liefert awk die GANZE Datei – der Guard darunter fände
# FACTORY_WT_SKIP_ENV dann im Produktionscode (:228) und bliebe grün, obwohl der Kopf-Kommentar,
# also der Prüfgegenstand von AK9(d), gelöscht sein kann.
{ [ "$(printf '%s\n' "$sw_header" | wc -l)" -lt "$(wc -l < "$SW")" ]; }
assert_true "$?" "#236 AK9(d): die Kopf-Extraktion bricht am Sentinel ab (kein Fail-open auf die ganze Datei)"
# Auf die Kommentarform ankern, nicht auf das nackte Wort: der Prüfgegenstand ist die
# Schalter-Zeile im Kopf, nicht irgendeine Erwähnung.
printf '%s\n' "$sw_header" | grep -q '^#   FACTORY_WT_SKIP_ENV=1'
assert_true "$?" "#236 AK9(d): start-work.sh nennt FACTORY_WT_SKIP_ENV im Kopf-Kommentar"

# AK9(c) fordert die Env-Schalter-LISTE, nicht eine beliebige Erwähnung → Mehrwort-Anker über
# flat_286 gegen $GITWF (bereits oben definiert), symmetrisch zur Isolation in AK9(d).
assert_contains_286 "$(flat_286 "$GITWF")" '`FACTORY_WT_SKIP_ENV=1` = die (gitignorete) `.env.local`' \
  "#236 AK9(c): git-workflow.md listet FACTORY_WT_SKIP_ENV in der Env-Schalter-Liste"

# (AK9(a)/(b) – Lesson und Index-Zeile zur .env.local-Spiegelung – entfallen im Factory-Repo: die Lesson
# gehört dem adoptierenden Projekt, nicht der Factory-Auslieferung.)

# ─── nothra/tch-gastro-services#267 AK5: start-work.sh trennt Worktree-Fakt und Session-Empfehlung ─────
# Läuft hier (vor dem TMP_SW-Aufräumen unten), weil AK5 die gh-Stub/REPO_SW-Fixtures aus dem
# nothra/tch-gastro-services#74/#236-Block braucht. Die Session-Empfehlung wird nicht mehr mit „kein geteilter HEAD"
# begründet – zwei getrennte Aussagen im Abschluss-Output.
echo ""
echo "#267 AK5: start-work.sh Abschluss-Output trennt Worktree-Fakt und Session-Empfehlung:"

OUT_267=$(run_start_work "$TMP_SW/wt-267" 792 demo-267)
assert_contains_286 "$OUT_267" "kein geteilter HEAD" \
  "AK5: der Worktree-Fakt (kein geteilter HEAD) steht weiterhin im Output"
assert_contains_286 "$OUT_267" "Empfehlung (keine Pflicht)" \
  "AK5: die Session-Empfehlung ist explizit als 'keine Pflicht' markiert"

# Getrennte Aussagen: keine einzelne Zeile nennt HEAD-Teilen UND Claude-Session zugleich.
head_session_same_line_267=$(printf '%s\n' "$OUT_267" | grep -F "kein geteilter HEAD" | grep -c "Claude-Session")
assert_true "$([ "$head_session_same_line_267" -eq 0 ]; echo $?)" \
  "AK5: die HEAD-Begründung und die Session-Empfehlung stehen NICHT in derselben Zeile"

# Mutation: die ALTE, kombinierte Formulierung hätte HEAD-Begründung und Session-Empfehlung in
# derselben Zeile – belegt per Fixture-String, dass der obige Guard eine Regression erkennen würde.
OLD_LINE_267="Eigener Arbeitsbaum = parallele Sessions kollidieren nicht (kein geteilter HEAD), starte eine neue Claude-Session."
old_same_line_267=$(printf '%s\n' "$OLD_LINE_267" | grep -F "kein geteilter HEAD" | grep -c "Claude-Session")
assert_true "$([ "$old_same_line_267" -gt 0 ]; echo $?)" \
  "AK5 (Mutation): die alte, kombinierte Formulierung hätte den Trennungs-Guard reißen lassen"

# ─── nothra/tch-gastro-services#322: Session-Empfehlung ist an Schritt 2 (/implement) gebunden, nicht an den ───────────
# Worktree-Fakt oder an Schritt 0/1 (/requirements). Nutzt denselben OUT_267 wie AK5 oben.
echo ""
echo "#322: start-work.sh bindet die Session-Empfehlung an Schritt 2 (/implement):"

step1_line_322=$(printf '%s\n' "$OUT_267" | grep -n '1\. Task-Datei mit Beschreibung' | head -1 | cut -d: -f1)
step2_line_322=$(printf '%s\n' "$OUT_267" | grep -n '2\. Implementieren starten' | head -1 | cut -d: -f1)
rec_line_322=$(printf '%s\n' "$OUT_267" | grep -n 'Empfehlung (keine Pflicht)' | head -1 | cut -d: -f1)
head_fact_line_322=$(printf '%s\n' "$OUT_267" | grep -n 'kein geteilter HEAD' | head -1 | cut -d: -f1)

assert_true "$([ -n "$step1_line_322" ] && [ -n "$step2_line_322" ] && [ -n "$rec_line_322" ] \
    && [ -n "$head_fact_line_322" ] && [ "$step1_line_322" -lt "$step2_line_322" ] \
    && [ "$step2_line_322" -lt "$rec_line_322" ] && [ "$rec_line_322" -lt "$head_fact_line_322" ]; echo $?)" \
  "#322: Reihenfolge im Abschluss-Output ist Schritt 1 (/requirements) → Schritt 2 (/implement) → Session-Empfehlung → Worktree-Fakt (nicht mehr umgekehrt)"

# Exakt 1: die Empfehlungszeile ist die unmittelbar nächste Zeile nach Schritt 2 (kein
# unbegründeter Toleranzbereich – die Zeile folgt in start-work.sh direkt auf die Schritt-2-Zeile).
rec_gap_322=$((rec_line_322 - step2_line_322))
assert_true "$([ "$rec_gap_322" -eq 1 ]; echo $?)" \
  "#322: die Session-Empfehlung steht in der unmittelbar nächsten Zeile nach Schritt 2 (/implement), nicht als entkoppelter Schlussabsatz"

no_claude_session_before_step2_322=$(printf '%s\n' "$OUT_267" | head -n "$((step2_line_322 - 1))" | grep -c "Claude-Session")
assert_true "$([ "$no_claude_session_before_step2_322" -eq 0 ]; echo $?)" \
  "#322: vor Schritt 2 (/implement) wird keine neue Claude-Session empfohlen (Schritt 0/1 bleiben unqualifiziert)"

# Mutation: die ALTE Reihenfolge (Fakt-Zeile, danach erst die generische Empfehlung am Schluss)
# hätte die neue Bindungs-/Reihenfolge-Prüfung reißen lassen.
OLD_TAIL_322=$(printf '%s\n%s\n' \
  "⚡ Eigener Arbeitsbaum: parallele Sessions kollidieren nicht (kein geteilter HEAD)." \
  "Empfehlung (keine Pflicht): Starte für Task 792 zusätzlich eine neue Claude-Session in diesem Worktree.")
old_head_line_322=$(printf '%s\n' "$OLD_TAIL_322" | grep -n 'kein geteilter HEAD' | head -1 | cut -d: -f1)
old_rec_line_322=$(printf '%s\n' "$OLD_TAIL_322" | grep -n 'Empfehlung (keine Pflicht)' | head -1 | cut -d: -f1)
assert_true "$([ -n "$old_head_line_322" ] && [ -n "$old_rec_line_322" ] && [ "$old_head_line_322" -lt "$old_rec_line_322" ]; echo $?)" \
  "#322 (Mutation): die alte Reihenfolge (Fakt vor Empfehlung) hätte die neue Bindungs-Prüfung nicht erfüllt"

# ─── nothra/tch-gastro-services#322 Fehlerszenario 1 (Spec): FACTORY_NO_WORKTREE=1 – Formulierung bleibt sinnvoll ──────
# Nutzt den bereits geklonten In-Place-Baum $REPO_IP (siehe nothra/tch-gastro-services#74/#236-Block oben) für einen
# zweiten start-work.sh-Lauf mit anderer Task-ID – start-work.sh checkt vorher $DEFAULT_BRANCH
# aus, ein zweiter Lauf auf demselben Klon ist damit unproblematisch.
echo ""
echo "#322 Fehlerszenario 1: start-work.sh im In-Place-Modus (FACTORY_NO_WORKTREE=1):"

OUT_NOWT_322=$( cd "$REPO_IP" && PATH="$TMP_SW/bin:$PATH" \
    FACTORY_DIR="$REPO_IP" FACTORY_REPO="acme/demo" FACTORY_NO_WORKTREE=1 \
    bash "$SW" 793 demo-nowt-322 2>&1 )

assert_absent "$OUT_NOWT_322" "In den isolierten Worktree wechseln" \
  "#322 Fehlerszenario 1: im In-Place-Modus wird kein Worktree-Wechsel genannt, der nicht stattfindet"

step2_line_nowt_322=$(printf '%s\n' "$OUT_NOWT_322" | grep -n '2\. Implementieren starten' | head -1 | cut -d: -f1)
rec_line_nowt_322=$(printf '%s\n' "$OUT_NOWT_322" | grep -n 'Empfehlung (keine Pflicht)' | head -1 | cut -d: -f1)
assert_true "$([ -n "$step2_line_nowt_322" ] && [ -n "$rec_line_nowt_322" ] \
    && [ "$((rec_line_nowt_322 - step2_line_nowt_322))" -eq 1 ]; echo $?)" \
  "#322 Fehlerszenario 1: die Session-Empfehlung bleibt auch ohne Worktree-Modus unmittelbar an Schritt 2 (/implement) gebunden"

no_claude_session_before_step2_nowt_322=$(printf '%s\n' "$OUT_NOWT_322" | head -n "$((step2_line_nowt_322 - 1))" | grep -c "Claude-Session")
assert_true "$([ "$no_claude_session_before_step2_nowt_322" -eq 0 ]; echo $?)" \
  "#322 Fehlerszenario 1: vor Schritt 2 wird auch ohne Worktree-Modus keine Claude-Session empfohlen"

rm -rf "$TMP_SW"

# ─── nothra/tch-gastro-services#91: factory-commit.sh (Commit/Push-Seam, ADR-019) ──────────────────────
echo ""
echo "#91 factory-commit.sh (Commit/Push-Seam, ADR-019):"

FCOMMIT="$SCRIPTS_DIR/factory-commit.sh"
assert_true "$([[ -f "$FCOMMIT" ]]; echo $?)" "scripts/factory-commit.sh vorhanden"

# Wegwerf-Repo mit Bare-Remote als Push-Ziel (reales git, Muster start-work-Test nothra/tch-gastro-services#74).
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

# ─── nothra/tch-gastro-services#239: leerer Commit-Zweig holt ausstehenden Push nach ───────────────────
echo ""
echo "#239 factory-commit.sh (Push-Nachholen im leeren Zweig):"

# 9. Nichts zu committen, aber Branch hat Upstream + unpushten Commit → Push wird
#    nachgeholt (exit 0), Remote-Tracking-Ref zeigt danach auf den lokalen Stand.
WT=$(fc_repo pushpending)
git -C "$WT" checkout -q -b feature/239-pushpending
git -C "$WT" push -q -u origin feature/239-pushpending
echo "lokal, noch nicht gepusht" > "$WT/change.txt"
git -C "$WT" add -A
git -C "$WT" commit -q -m "feat: lokaler commit ohne push"
fc_out=$( cd "$WT" && bash "$FCOMMIT" "feat: nichts zu committen" 2>&1 ); fc_rc=$?
assert_exit 0 "$fc_rc" "factory-commit: nichts zu committen + unpushter Commit → exit 0 (Push nachgeholt)"
git -C "$WT" diff --quiet HEAD origin/feature/239-pushpending
assert_true "$?" "factory-commit: holt ausstehenden Push nach (Remote-Ref = lokaler Stand)"
printf '%s' "$fc_out" | grep -qF 'committet und gepusht'
assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit: Nachhol-Meldung unterscheidet sich vom Happy-Path-Text"
printf '%s' "$fc_out" | grep -qF 'ausstehenden Push nachgeholt'
assert_true "$?" "factory-commit: Nachhol-Meldung bestätigt den nachgeholten Push positiv"

# 10. Nichts zu committen, kein Upstream (frischer Branch mit lokalem Commit) →
#     Push mit `-u origin HEAD` wird nachgeholt (exit 0), Tracking-Ref entsteht.
WT=$(fc_repo noupstream)
git -C "$WT" checkout -q -b feature/239-noupstream
echo "lokal, kein upstream" > "$WT/change.txt"
git -C "$WT" add -A
git -C "$WT" commit -q -m "feat: lokaler commit, kein upstream"
( cd "$WT" && bash "$FCOMMIT" "feat: nichts zu committen" ) >/dev/null 2>&1
assert_exit 0 "$?" "factory-commit: nichts zu committen + kein Upstream → exit 0 (Push mit -u nachgeholt)"
git -C "$WT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
assert_true "$?" "factory-commit: legt beim Nachhol-Push das Tracking-Ref an"

# 11. Nichts zu committen, Branch deckungsgleich mit Upstream → weiterhin keine
#     Aktion, unveränderte Meldung „übersprungen" (Regression zu Fall 4).
WT=$(fc_repo insync)
git -C "$WT" checkout -q -b feature/239-insync
git -C "$WT" push -q -u origin feature/239-insync
fc_out=$( cd "$WT" && bash "$FCOMMIT" "feat: nichts zu committen" 2>&1 ); fc_rc=$?
assert_exit 0 "$fc_rc" "factory-commit: deckungsgleich mit Upstream → exit 0, keine Aktion"
printf '%s' "$fc_out" | grep -qi 'übersprungen'
assert_true "$?" "factory-commit: deckungsgleicher Branch behält die unveränderte 'übersprungen'-Meldung"

# 12. Nichts zu committen, unpushter Commit vorhanden, Nachhol-Push scheitert →
#     exit ≠ 0 (Fehlschlag wird weitergereicht, kein stiller Erfolg).
WT=$(fc_repo pushpendingfail)
git -C "$WT" checkout -q -b feature/239-pushpendingfail
git -C "$WT" push -q -u origin feature/239-pushpendingfail
echo "lokal, push schlaegt fehl" > "$WT/change.txt"
git -C "$WT" add -A
git -C "$WT" commit -q -m "feat: lokaler commit, nachhol-push scheitert"
git -C "$WT" remote set-url origin "$TMP_FC/does-not-exist.git"
fc_out=$( cd "$WT" && bash "$FCOMMIT" "feat: nichts zu committen" 2>&1 ); fc_rc=$?
assert_true "$([ $fc_rc -ne 0 ]; echo $?)" "factory-commit: Nachhol-Push scheitert → exit ≠ 0"
printf '%s' "$fc_out" | grep -qF 'hole ausstehenden Push nach'
assert_true "$?" "factory-commit: Fehlschlag stammt aus dem erreichten Push-Pfad (nicht aus einem anderen Grund)"

# ─── nothra/tch-gastro-services#262: -h/--help ist eine Hilfe-Anfrage, keine Commit-Message ────────────
echo ""
echo "#262 factory-commit.sh (-h/--help-Guard):"

# AK5 (reguläre Message committet + pusht wie bisher) ist bereits durch Fall 1 oben
# abgedeckt – hier keine zweite Happy-Path-Schleife (Lesson nothra/tch-gastro-services#240).
# Tabelle „Flag|Fixture-Name", damit die Wegwerf-Repos sprechend heißen (statt aus dem Flag
# generierter Namen wie 'helph').
for flag_case in "-h|helpshort" "--help|helplong"; do
  IFS='|' read -r flag_arg fixture_name <<< "$flag_case"
  WT=$(fc_repo "$fixture_name")
  git -C "$WT" checkout -q -b feature/262-help
  HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
  echo "darf nicht committet werden" > "$WT/change.txt"
  fc_out=$( cd "$WT" && bash "$FCOMMIT" "$flag_arg" 2>/dev/null ); fc_rc=$?
  assert_exit 0 "$fc_rc" "factory-commit AK4: '$flag_arg' → exit 0"
  printf '%s' "$fc_out" | grep -qF 'Aufruf: factory-commit.sh'
  assert_true "$?" "factory-commit AK4: '$flag_arg' gibt die Usage aus"
  [ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
  assert_true "$?" "factory-commit AK4: '$flag_arg' committet nichts"
  # `git diff --cached --quiet` vergleicht Index gegen HEAD, nicht gegen leer: liefe trotz
  # entferntem Guard `git add -A && git commit`, wäre der Index danach == neuer HEAD → grün
  # aus dem falschen Grund. Stattdessen direkt prüfen, dass die neue Datei unverändert
  # untracked bleibt – das gilt nur, wenn `git add` nie lief (Lesson nothra/tch-gastro-services#214).
  [ "$(git -C "$WT" status --porcelain -- change.txt)" = "?? change.txt" ]
  assert_true "$?" "factory-commit AK4: '$flag_arg' führt kein 'git add' aus (Datei bleibt untracked)"
  git -C "$WT" rev-parse origin/feature/262-help >/dev/null 2>&1
  assert_true "$([ $? -ne 0 ]; echo $?)" "factory-commit AK4: '$flag_arg' pusht nichts"
done

# `--help` plus Zusatz-Argument ist keine Hilfe-Anfrage → bestehende Argumentzahl-Prüfung.
WT=$(fc_repo helpextra)
git -C "$WT" checkout -q -b feature/262-helpextra
echo "x" > "$WT/change.txt"
fc_out=$( cd "$WT" && bash "$FCOMMIT" "--help" "extra" 2>&1 ); fc_rc=$?
assert_true "$([ $fc_rc -ne 0 ]; echo $?)" "factory-commit AK4: '--help' mit Zusatz-Argument → exit ≠ 0 (kein Help-Sonderfall)"
printf '%s' "$fc_out" | grep -qF 'genau ein Argument erwartet'
assert_true "$?" "factory-commit AK4: '--help extra' scheitert an der Argumentzahl-Prüfung (pfadspezifisches Signal)"

# Fehlerszenario 2 der Spec, `factory-commit.sh`-Seite: die leere Message läuft weiterhin in
# die bestehende Leer-Prüfung (`[ -z "${1:-}" ]`) – der neue -h/--help-Guard davor darf sie
# nicht aushebeln. Der Fall „gar kein Argument" (nothra/tch-gastro-services#91, Fall 5) deckt das nicht ab.
WT=$(fc_repo emptymsg)
git -C "$WT" checkout -q -b feature/262-emptymsg
HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
echo "darf nicht committet werden" > "$WT/change.txt"
fc_out=$( cd "$WT" && bash "$FCOMMIT" "" 2>&1 ); fc_rc=$?
assert_true "$([ $fc_rc -ne 0 ]; echo $?)" "factory-commit: leere Message ('') → exit ≠ 0 (Leer-Prüfung unverändert wirksam)"
printf '%s' "$fc_out" | grep -qF 'genau ein Argument erwartet'
assert_true "$?" "factory-commit: leere Message scheitert an der Leer-/Argumentprüfung (pfadspezifisches Signal)"
[ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
assert_true "$?" "factory-commit: leere Message committet nichts"

# AK6 – Abgrenzung: jedes andere '-'-präfigierte Argument bleibt eine gewöhnliche Message.
WT=$(fc_repo dashx)
git -C "$WT" checkout -q -b feature/262-dashx
echo "x" > "$WT/change.txt"
( cd "$WT" && bash "$FCOMMIT" "-x" ) >/dev/null 2>&1
assert_exit 0 "$?" "factory-commit AK6: '-x' wird wie jede andere Message behandelt (exit 0)"
[ "$(git -C "$WT" log --format=%s -1)" = "-x" ]
assert_true "$?" "factory-commit AK6: '-x' landet unverändert als Commit-Message"
git -C "$WT" diff --quiet HEAD origin/feature/262-dashx
assert_true "$?" "factory-commit AK6: '-x' wird wie bisher gepusht"

rm -rf "$TMP_FC"

# ─── nothra/tch-gastro-services#91: Report-Verdict-Helper / run_skill-Report-Guard (ADR-019 §4) ────────
echo ""
echo "#91 Report-Verdict-Helper (run_skill-Guard, ADR-019 §4):"

RV_LIB="$SCRIPTS_DIR/lib/report-verdict.sh"
assert_true "$([[ -f "$RV_LIB" ]]; echo $?)" "scripts/lib/report-verdict.sh vorhanden"

TMP_RV="$(mktemp -d)"; mkdir -p "$TMP_RV/tasks"
# rv <skill> <task_id> → ruft report_verdict aus der gesourcten Lib (tasks_dir = 3. Arg).
rv() { bash -c 'source "$1"; report_verdict "$2" "$3" "$4"' _ "$RV_LIB" "$1" "$2" "$TMP_RV/tasks"; }

# AK1 – Verdict aus der ersten nicht-leeren Zeile unter dem Anker (review → '## Empfehlung').
printf '## Empfehlung\nAPPROVED\n' > "$TMP_RV/tasks/review-1.md"
assert_true "$([ "$(rv review 1)" = "APPROVED" ]; echo $?)" "AK1: review APPROVED aus Anker-Zeile"
printf '## Empfehlung\nNEEDS_REWORK\n' > "$TMP_RV/tasks/review-2.md"
assert_true "$([ "$(rv review 2)" = "NEEDS_REWORK" ]; echo $?)" "AK1: review NEEDS_REWORK aus Anker-Zeile"

# AK4 – Security-Review-Anker '## Ergebnis' analog (PASSED | NEEDS_FIXES).
printf '## Ergebnis\nPASSED\n' > "$TMP_RV/tasks/security-3.md"
assert_true "$([ "$(rv security-review 3)" = "PASSED" ]; echo $?)" "AK4: security PASSED aus Anker-Zeile"
printf '## Ergebnis\nNEEDS_FIXES\n' > "$TMP_RV/tasks/security-4.md"
assert_true "$([ "$(rv security-review 4)" = "NEEDS_FIXES" ]; echo $?)" "AK4: security NEEDS_FIXES aus Anker-Zeile"

# AK2 – Fließtext-Erwähnung NACH der Verdict-Zeile wird ignoriert (Reihenfolge irrelevant).
printf '## Empfehlung\nNEEDS_REWORK\n\nAlle Personas empfahlen für sich APPROVED.\n' > "$TMP_RV/tasks/review-9.md"
assert_true "$([ "$(rv review 9)" = "NEEDS_REWORK" ]; echo $?)" "AK2: Fließtext-APPROVED nach Verdict-Zeile ignoriert"
printf '## Ergebnis\nNEEDS_FIXES\nBasis PASSED, aber ein kritisches Finding offen.\n' > "$TMP_RV/tasks/security-10.md"
assert_true "$([ "$(rv security-review 10)" = "NEEDS_FIXES" ]; echo $?)" "AK4: Fließtext-PASSED nach Verdict-Zeile ignoriert"
# AK6 – Spiegel-Richtung: PASSED-Verdict + Fließtext-NEEDS_FIXES → PASSED (Gate blockiert NICHT).
printf '## Ergebnis\nPASSED\nHinweis: ohne den Anker hätte grep hier NEEDS_FIXES gematcht.\n' > "$TMP_RV/tasks/security-14.md"
assert_true "$([ "$(rv security-review 14)" = "PASSED" ]; echo $?)" "AK6: Fließtext-NEEDS_FIXES nach PASSED-Zeile ignoriert (Gate blockiert nicht)"

# AK3 – Leerzeilen zwischen Überschrift und Verdict-Zeile werden übersprungen.
printf '## Empfehlung\n\n\nNEEDS_REWORK\n' > "$TMP_RV/tasks/review-11.md"
assert_true "$([ "$(rv review 11)" = "NEEDS_REWORK" ]; echo $?)" "AK3: Leerzeilen nach Überschrift übersprungen"

# F1 – Fehlender Anker → leeres Verdict (kein Volltext-Fallback), auch wenn Token im Fließtext steht.
printf 'VERDICT: APPROVED\nirgendein Fließtext\n' > "$TMP_RV/tasks/review-5.md"
assert_true "$([ -z "$(rv review 5)" ]; echo $?)" "F1: fehlender Anker → leeres Verdict (fail-closed)"

# F2 – Anker-Zeile ohne gültiges Token → leeres Verdict.
printf '## Empfehlung\n(noch offen)\n' > "$TMP_RV/tasks/review-12.md"
assert_true "$([ -z "$(rv review 12)" ]; echo $?)" "F2: Anker-Zeile ohne Token → leeres Verdict"

# F3 – Fehlende Report-Datei → leer, Exit 0 (unverändertes Verhalten).
assert_true "$([ -z "$(rv security-review 6)" ]; echo $?)" "F3: fehlender Report → leeres Verdict"

# F4 – Anker-Zeile mit BEIDEN Tokens (Template kopiert) → leeres Verdict (fail-closed, kein Raten).
printf '## Empfehlung\nAPPROVED | NEEDS_REWORK\n' > "$TMP_RV/tasks/review-13.md"
assert_true "$([ -z "$(rv review 13)" ]; echo $?)" "F4: mehrdeutige Anker-Zeile → leeres Verdict (fail-closed)"

# Robustheit – EXAKTER Anker (Kernannahme des Fixes): weder eine Präfix-/Superset-Überschrift
# ('## Empfehlungen') noch ein Verdict auf der Überschriftszeile selbst ('## Empfehlung: APPROVED')
# dürfen matchen. Nur die erste Nicht-Leerzeile UNTER der exakten Anker-Zeile zählt → sonst leer.
printf '## Empfehlungen\nAPPROVED\n' > "$TMP_RV/tasks/review-15.md"
assert_true "$([ -z "$(rv review 15)" ]; echo $?)" "Robust: Superset-Überschrift '## Empfehlungen' ist kein Anker → leer"
printf '## Empfehlung: APPROVED\n' > "$TMP_RV/tasks/review-16.md"
assert_true "$([ -z "$(rv review 16)" ]; echo $?)" "Robust: Verdict auf der Überschriftszeile → leer (nur Folgezeile zählt)"

# Nicht-Report-Skill → immer leer (Verhalten unverändert, auch bei vorhandener Datei mit Anker).
printf '## Empfehlung\nAPPROVED\n' > "$TMP_RV/tasks/review-7.md"
assert_true "$([ -z "$(rv implement 7)" ]; echo $?)" "Nicht-Report-Skill → kein Verdict (Verhalten unverändert)"

rm -rf "$TMP_RV"

# Wiring: run-pipeline.sh nutzt den geteilten Helper (kein Drift Guard ↔ Summary).
grep -q 'report-verdict.sh' "$PIPELINE"
assert_true "$?" "#91: run-pipeline.sh sourct den geteilten Verdict-Helper"
grep -q 'report_verdict' "$PIPELINE"
assert_true "$?" "#91: run_skill/pipeline_summary nutzen report_verdict (ein Ort)"

# AK5/AK6/AK7 (nothra/tch-gastro-services#211): Phase-2-Loop + Security-Gate lesen den Verdict ausschließlich über den
# Anker-Helper – die alten Volltext-Greps über den ganzen Report sind entfernt (ein Ort).
grep -qF 'grep -q "APPROVED"' "$PIPELINE"; approved_grep=$?
assert_true "$([ "$approved_grep" -ne 0 ]; echo $?)" "AK5 (#211): Phase-2-Loop ohne Volltext-grep \"APPROVED\""
grep -qF 'grep -q "NEEDS_FIXES"' "$PIPELINE"; needsfixes_grep=$?
assert_true "$([ "$needsfixes_grep" -ne 0 ]; echo $?)" "AK6 (#211): Security-Gate ohne Volltext-grep \"NEEDS_FIXES\""

# Budget-Puffer: review + security-review auf max_turns 30 (ADR-019 §5 + Nachtrag nothra/tch-gastro-services#252;
# 8→14 in Task 91, 14→30 in Task 241/252 als validierter Wert kalibriert).
if [ "$HAS_YQ" = 1 ]; then
  [ "$(yq '.skills.review.max_turns' "$DEFAULTS_YML")" = "30" ] \
    && [ "$(yq '.skills.security-review.max_turns' "$DEFAULTS_YML")" = "30" ]
  assert_true "$?" "#91: review + security-review max_turns=30 (Budget-Puffer)"
else
  skip_yq "#91: review + security-review max_turns=30"
fi

# ─── nothra/tch-gastro-services#214: Contract-Drift-Guard – Report-Anker ↔ Parser-Konstanten ───────────
# Die Verdict-/Section-Parser koppeln HART an die Anker-Überschriften der Report-Contracts
# (.claude/commands/review.md, security-review.md). Wird eine Überschrift umbenannt, bricht die
# Pipeline STILL (leeres Verdict / Count 0), ohne dass ein Test rot wird. Dieser Guard macht den
# Drift sichtbar. Reiner Test (tech-debt + test); Spec/AC in docs/specs/spec-214-*.md.
echo ""
echo "#214 Contract-Drift-Guard (Report-Anker ↔ Parser-Konstanten):"

RV_LIB214="$SCRIPTS_DIR/lib/report-verdict.sh"
PIPELINE214="$SCRIPTS_DIR/run-pipeline.sh"
REVIEW_MD214="$FACTORY_ROOT/.claude/commands/review.md"
SECURITY_MD214="$FACTORY_ROOT/.claude/commands/security-review.md"

# extract_verdict_header <skill> <report-verdict.sh> – liest die EXAKTE Anker-Überschrift der
# report_verdict-case-Zeile aus dem echten Parser-Skript (AC6: nicht im Test dupliziert).
extract_verdict_header() {
  local skill="$1" lib="$2"
  # Die Lib hat seit nothra/tch-gastro-services#310 mehrere case-Blöcke über dieselben Skill-Namen (report_file für den
  # Pfad, report_verdict für Anker + Tokens). Der `header='`-Filter wählt den Parser-Block –
  # ohne ihn liefert `head -n1` die Pfad-Zeile aus report_file und der Guard wird falsch rot.
  # Der Pipeline-Exit wird bewusst nicht ausgewertet (nur der String zählt, kein `set -e`):
  # `head -n1` kann unter pipefail SIGPIPE(141) erzeugen, ist hier aber folgenlos.
  grep -E "^[[:space:]]*${skill}\)" "$lib" | grep -F "header='" \
    | sed -E "s/.*header='([^']*)'.*/\1/" | head -n1
}

# extract_section_headers <run-pipeline.sh> – liest die distinct "## …"-Sektions-Muster, die
# count_section_items als Argumente übergeben bekommt (AC6: aus der echten Quelle).
extract_section_headers() {
  local pipeline="$1"
  grep 'count_section_items "' "$pipeline" | grep -oE '"## [^"]*"' | tr -d '"' | sort -u
}

# drift_guard <review_md> <security_md> <report-verdict.sh> <run-pipeline.sh>
#   Exit 0 = jede Parser-Konstante als Anker im zugehörigen Command auffindbar.
#   Exit 1 = Drift: druckt die betroffene Konstante + Datei auf stdout (fail-closed).
drift_guard() {
  local review_md="$1" security_md="$2" rv_lib="$3" pipeline="$4"
  local rc=0

  # Fail-closed: Command-Dateien müssen existieren und nicht-leer sein.
  local f
  for f in "$review_md" "$security_md"; do
    if [ ! -s "$f" ]; then
      echo "DRIFT: Command-Datei fehlt oder ist leer: $f"
      return 1
    fi
  done

  # report_verdict: exakt-verankerte Überschriftszeile (Semantik aus report-verdict.sh:
  # '^[[:space:]]*<header>[[:space:]]*$'). Extraktion aus der echten Quelle → sonst fail-closed.
  local review_header sec_header
  review_header="$(extract_verdict_header review "$rv_lib")"
  sec_header="$(extract_verdict_header security-review "$rv_lib")"
  if [ -z "$review_header" ] || [ -z "$sec_header" ]; then
    echo "DRIFT: report_verdict-Anker nicht aus $rv_lib extrahierbar (Parser-Format geändert?)"
    return 1
  fi
  if ! grep -Eq "^[[:space:]]*${review_header}[[:space:]]*\$" "$review_md"; then
    echo "DRIFT: report_verdict(review) erwartet Anker '${review_header}' in $review_md"; rc=1
  fi
  if ! grep -Eq "^[[:space:]]*${sec_header}[[:space:]]*\$" "$security_md"; then
    echo "DRIFT: report_verdict(security-review) erwartet Anker '${sec_header}' in $security_md"; rc=1
  fi

  # count_section_items: Teilstring/unankert wie das awk-Muster (/pattern/) – alle drei
  # Findings-Sektionen liegen in review.md. Leere Extraktion → fail-closed (Parser-Format geändert).
  local sections sec
  sections="$(extract_section_headers "$pipeline")"
  if [ -z "$sections" ]; then
    echo "DRIFT: count_section_items-Sektionen nicht aus $pipeline extrahierbar (Parser-Format geändert?)"
    return 1
  fi
  while IFS= read -r sec; do
    [ -n "$sec" ] || continue
    if ! grep -Eq "$sec" "$review_md"; then
      echo "DRIFT: count_section_items erwartet Sektion '${sec}' in $review_md"; rc=1
    fi
  done <<SECEOF
$sections
SECEOF

  return "$rc"
}

# ── AC6: Konstanten wurden aus den echten Skripten gelesen (nicht leer) ──
review_header214="$(extract_verdict_header review "$RV_LIB214")"
security_header214="$(extract_verdict_header security-review "$RV_LIB214")"
section_headers214="$(extract_section_headers "$PIPELINE214")"
assert_true "$([ -n "$review_header214" ]; echo $?)" \
  "AC6: review-Verdict-Anker aus report-verdict.sh extrahiert (nicht leer)"
assert_true "$([ -n "$security_header214" ]; echo $?)" \
  "AC6: security-Verdict-Anker aus report-verdict.sh extrahiert (nicht leer)"
assert_true "$([ -n "$section_headers214" ]; echo $?)" \
  "AC6: count_section_items-Sektionen aus run-pipeline.sh extrahiert (nicht leer)"
# AC3-Abdeckung pinnen: count_section_items deckt GENAU die drei Findings-Sektionen ab. Schrumpft
# die Extraktion still (z. B. 2 statt 3), bliebe der Guard grün, obwohl eine Sektion ungeprüft ist.
section_count214="$(printf '%s\n' "$section_headers214" | grep -c '^## ')"
assert_true "$([ "$section_count214" -eq 3 ]; echo $?)" \
  "AC3: alle drei count_section_items-Sektionen extrahiert (Guard-Abdeckung vollständig)"

# ── AC1-3/AC5: Guard grün gegen die echten Quellen (heute konsistent) ──
drift_guard "$REVIEW_MD214" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214" >/dev/null; guard_rc214=$?
assert_exit 0 "$guard_rc214" "AC1-3: alle Parser-Konstanten als Anker im Command auffindbar (Guard grün)"

TMP214="$(mktemp -d)"
# Erste extrahierte Sektion für den Section-Drift-Negativtest (aus der Quelle abgeleitet, nicht
# hardcodet – ein konsistenter beidseitiger Rename bräche diesen Test sonst fälschlich).
first_section214="$(printf '%s\n' "$section_headers214" | head -n1)"

# ── AC4: umbenannter review-Verdict-Anker (## Empfehlung) → rot + nennt Konstante ──
sed "s/^${review_header214}\$/## Fazit/" "$REVIEW_MD214" > "$TMP214/review-verdict-drift.md"
out214=$(drift_guard "$TMP214/review-verdict-drift.md" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "AC4: umbenannter review-Verdict-Anker → Guard rot"
printf '%s' "$out214" | grep -q 'report_verdict(review)'
assert_true "$?" "AC4: Guard nennt betroffene Konstante report_verdict(review)"

# ── AC4: umbenannter security-Verdict-Anker (## Ergebnis) → rot + nennt Konstante ──
sed "s/^${security_header214}\$/## Fazit/" "$SECURITY_MD214" > "$TMP214/security-verdict-drift.md"
out214=$(drift_guard "$REVIEW_MD214" "$TMP214/security-verdict-drift.md" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "AC4: umbenannter security-Verdict-Anker → Guard rot"
printf '%s' "$out214" | grep -q 'report_verdict(security-review)'
assert_true "$?" "AC4: Guard nennt betroffene Konstante report_verdict(security-review)"

# ── AC4: umbenannte Findings-Sektion → rot + nennt Konstante (Anker aus der Quelle) ──
sed "s/^${first_section214}.*/## Blocker/" "$REVIEW_MD214" > "$TMP214/section-drift.md"
out214=$(drift_guard "$TMP214/section-drift.md" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "AC4: umbenannte Findings-Sektion → Guard rot"
printf '%s' "$out214" | grep -q 'count_section_items'
assert_true "$?" "AC4: Guard nennt betroffene Konstante count_section_items"

# ── Fehlerszenario 1: fehlende Command-Datei → fail-closed (rot), nicht still bestanden ──
out214=$(drift_guard "$TMP214/does-not-exist.md" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "F1 (#214): fehlende Command-Datei → Guard rot (fail-closed)"

# ── Fehlerszenario 1b: LEERE Command-Datei → ebenfalls fail-closed (Spec: „fehlt oder ist leer") ──
: > "$TMP214/empty.md"
out214=$(drift_guard "$TMP214/empty.md" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "F1 (#214): leere Command-Datei → Guard rot (fail-closed)"

# ── Fehlerszenario 2: Verdict-Anker NUR im Fließtext (keine ##-Überschriftszeile) ──
# Isoliert auf den exakt-verankerten report_verdict-Pfad: die echte review.md wird kopiert und nur
# die '## Empfehlung'-Überschriftszeile in Fließtext verwandelt. Alle Findings-Sektionen bleiben
# intakt → count_section_items besteht; rot darf NUR die Verdict-Exaktverankerung erzeugen (sonst
# bliebe die nothra/tch-gastro-services#211-Regression „Verdict unankert" unentdeckt – Review-Finding W1).
sed "s/^${review_header214}\$/Siehe Abschnitt ${review_header214} weiter unten./" \
  "$REVIEW_MD214" > "$TMP214/prose-only.md"
out214=$(drift_guard "$TMP214/prose-only.md" "$SECURITY_MD214" "$RV_LIB214" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "F2 (#214): Verdict-Anker nur im Fließtext → Guard rot (exakt-verankert)"
printf '%s' "$out214" | grep -q 'report_verdict(review)'
assert_true "$?" "F2 (#214): Guard nennt report_verdict(review) (nicht durch fehlende Sektionen rot)"
printf '%s' "$out214" | grep -q 'count_section_items'
assert_true "$([ $? -ne 0 ]; echo $?)" "F2 (#214): Findings-Sektionen bleiben intakt (rot NUR wegen Verdict-Anker)"

# ── AC6 (Parser-Seite): Konstante NUR im Parser umbenannt (Command unverändert) → rot ──
# Zweite Drift-Richtung: AC4 mutiert die Command-Seite; AC6 verlangt Erkennung auch, wenn die
# PARSER-Konstante driftet. Fake-report-verdict.sh mit umbenanntem review-Anker → Guard rot.
printf "  review)          header='## Fazit' ;;\n  security-review) header='## Ergebnis' ;;\n" \
  > "$TMP214/rv-verdict-drift.sh"
out214=$(drift_guard "$REVIEW_MD214" "$SECURITY_MD214" "$TMP214/rv-verdict-drift.sh" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "AC6: Parser-seitig umbenannter Verdict-Anker (nur report-verdict.sh) → Guard rot"
printf '%s' "$out214" | grep -q 'report_verdict(review)'
assert_true "$?" "AC6: Guard nennt report_verdict(review) bei Parser-seitigem Drift"

# ── AC6 (Parser-Seite): count_section_items-Sektion nur im Parser umbenannt → rot ──
printf 'count_section_items "$f" "## Geändert" "## Wichtige Findings"\ncount_section_items "$f" "## Wichtige Findings" "## Nitpicks"\n' \
  > "$TMP214/pipeline-section-drift.sh"
out214=$(drift_guard "$REVIEW_MD214" "$SECURITY_MD214" "$RV_LIB214" "$TMP214/pipeline-section-drift.sh"); rc214=$?
assert_exit 1 "$rc214" "AC6: Parser-seitig umbenannte Sektion (nur run-pipeline.sh) → Guard rot"
printf '%s' "$out214" | grep -q 'count_section_items'
assert_true "$?" "AC6: Guard nennt count_section_items bei Parser-seitigem Drift"

# ── Fail-closed: Parser-Format ganz verändert (keine Konstante extrahierbar) → rot, nicht grün ──
printf '# report-verdict.sh ohne case-Zweige (Format geändert)\n' > "$TMP214/rv-empty.sh"
out214=$(drift_guard "$REVIEW_MD214" "$SECURITY_MD214" "$TMP214/rv-empty.sh" "$PIPELINE214"); rc214=$?
assert_exit 1 "$rc214" "Fail-closed (#214): Verdict-Anker nicht extrahierbar → Guard rot"
printf '%s' "$out214" | grep -q 'report_verdict-Anker nicht aus'
assert_true "$?" "Fail-closed (#214): meldet nicht-extrahierbaren Verdict-Anker (kein stilles Grün)"

printf '# run-pipeline.sh ohne count_section_items-Aufrufe (Format geändert)\n' > "$TMP214/pipeline-empty.sh"
out214=$(drift_guard "$REVIEW_MD214" "$SECURITY_MD214" "$RV_LIB214" "$TMP214/pipeline-empty.sh"); rc214=$?
assert_exit 1 "$rc214" "Fail-closed (#214): Sektionen nicht extrahierbar → Guard rot"
printf '%s' "$out214" | grep -q 'count_section_items-Sektionen nicht'
assert_true "$?" "Fail-closed (#214): meldet nicht-extrahierbare Sektionen (kein stilles Grün)"

rm -rf "$TMP214"
unset -f drift_guard extract_verdict_header extract_section_headers

# ─── nothra/tch-gastro-services#91: Permissions-Konsistenz (.claude/settings.json, ADR-019 §2/§3) ──────
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

# nothra/tch-gastro-services#94: pr-shepherd.md dokumentiert 'gh pr ready' (Draft-Status auflösen, Schritt 5b) –
# konsistent zur allow-Liste, damit der freigegebene Verb auch im Skill sichtbar genutzt wird.
grep -qF 'gh pr ready' "$SHEPHERD"
assert_true "$?" "#94: pr-shepherd.md dokumentiert 'gh pr ready' (Draft-Auflösung)"

# nothra/tch-gastro-services#94 (AC2): 'gh pr ready' ist hinter einem isDraft-Guard dokumentiert – nicht unbedingt
# aufgerufen. Schützt die "nur bei Draft"-Semantik gegen ein späteres Entfernen des Guards.
grep -qF 'isDraft' "$SHEPHERD"
assert_true "$?" "#94: pr-shepherd.md guardet 'gh pr ready' hinter isDraft-Check (AC2)"

# nothra/tch-gastro-services#114: pr-shepherd Schritt 6 committet+pusht die Abschlussnotiz VOR dem Auto-Merge.
# Bei Squash-Merge landet eine nur lokal geschriebene Notiz sonst nie auf main (nothra/tch-gastro-services#112).
# factory-commit.sh ist der mandatierte Commit/Push-Seam (ADR-019) → deckt commit UND push ab.
grep -qF 'factory-commit.sh' "$SHEPHERD"
assert_true "$?" "#114: pr-shepherd.md committet Abschlussnotiz via factory-commit.sh"

# nothra/tch-gastro-services#114 (Reihenfolge): der commit+push-Schritt steht VOR dem Freigabe-Kommando
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

# nothra/tch-gastro-services#117: pr-shepherd Schritt 2 (Review-Kommentare auflösen) committet Review-Fixes über den
# Commit/Push-Seam factory-commit.sh (ADR-019) – analog Schritt 6 (nothra/tch-gastro-services#114) und implement/test/
# refactor. Bewusst gegen den Schritt-2-ABSCHNITT geprüft (Zeilenbereich zwischen den Headern
# '### Schritt 2' und '### Schritt 3'), NICHT global: der bereits vorhandene Schritt-6-Treffer
# darf den Guard nicht fälschlich grün färben (Lehre nothra/tch-gastro-services#114: ein Treffer im falschen Abschnitt ist
# so wenig ein Nachweis wie ein Prosa-Treffer).
assert_true "$(section_contains '### Schritt 2' '### Schritt 3' "$SHEPHERD" 'factory-commit.sh'; echo $?)" \
  "#117: pr-shepherd.md Schritt 2 committet Review-Fixes via factory-commit.sh (Seam)"

# nothra/tch-gastro-services#117 (AC2): das Seam-Kommando trägt im selben Abschnitt die fail-closed-Begründung mit
# ADR-019-Verweis – separat vom Kommando prüfbar, damit ein späteres Entfernen der Begründung
# (bei erhaltenem Kommando) auffällt. Wieder auf den Schritt-2-Abschnitt eingegrenzt.
assert_true "$(section_contains '### Schritt 2' '### Schritt 3' "$SHEPHERD" 'ADR-019'; echo $?)" \
  "#117: pr-shepherd.md Schritt 2 nennt die fail-closed-Begründung (ADR-019)"

# nothra/tch-gastro-services#158 (ADR-030): pr-shepherd Schritt 6 wählt den Merge-Modus nach PR-Zustand.
# GitHub lehnt 'gh pr merge --auto' bei bereits mergebarem PR (mergeStateStatus: CLEAN)
# ab – Schritt 6 muss den Zustand lesen und bei CLEAN direkt squash-mergen (fail-closed:
# alles außer CLEAN → --auto). Schritt 6 ist der letzte '### Schritt' → Abschnittsende ist
# '## Regeln'. AC1, AC2 und AC4 sind separat prüfbare Kriterien (je eine Assertion, nothra/tch-gastro-services#117-Regel):
# entfällt die Zustandsprüfung, bleibt AC2 grün und umgekehrt, und die AC4-Reihenfolge ist von
# beiden unabhängig (Unabhängigkeit belegt in der nothra/tch-gastro-services#94-Temp-Verifikation: unpatched → alle rot,
# patched → alle grün).

# AC1: Zustandsprüfung 'mergeStateStatus' im Schritt-6-Abschnitt.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'mergeStateStatus'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 liest den PR-Merge-Zustand (mergeStateStatus)"

# AC2: Direct-Merge-Fallback 'gh pr merge --squash' (ohne --auto) im Schritt-6-Abschnitt.
# Bewusst gegen die volle 'gh pr merge --squash'-Zeile geprüft: sie ist KEIN Teilstring von
# 'gh pr merge --auto --squash' (Lehre nothra/tch-gastro-services#114: Kommando ≠ Teil-Match), der Grep matcht also
# nicht fälschlich die --auto-Zeile.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'gh pr merge --squash'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 hat Direct-Merge-Fallback (gh pr merge --squash)"

# AC3: der --auto-Fallback bleibt im Schritt-6-Abschnitt für laufende Checks (≠ CLEAN) erhalten.
# Separierbar von AC2 (nothra/tch-gastro-services#117): würde der else-Zweig ebenfalls auf direkten Merge umgestellt,
# bliebe AC2 grün, aber dieser Guard rot. Section-begrenzt (nicht global wie der nothra/tch-gastro-services#114-Order-
# Guard), damit AC3 als eigenes Kriterium diagnostizierbar ist – nicht nur transitiv über nothra/tch-gastro-services#114.
assert_true "$(section_contains '### Schritt 6' '## Regeln' "$SHEPHERD" 'gh pr merge --auto --squash'; echo $?)" \
  "#158: pr-shepherd.md Schritt 6 behält --auto-Fallback für laufende Checks (gh pr merge --auto --squash)"

# AC4: die Abschlussnotiz (factory-commit.sh) steht AUCH VOR dem Direct-Merge-Zweig – nicht
# nur vor der --auto-Zeile (bereits durch nothra/tch-gastro-services#114 oben geprüft). Sonst könnte der direkte Merge
# vor dem Notiz-Push feuern (Notiz landet nie auf main, nothra/tch-gastro-services#112/#114). Zweiter Marker
# 'gh pr merge --squash' ist die Direct-Zeile, nicht die --auto-Zeile (kein Teilstring, s. o.).
assert_true "$(line_before 'factory-commit.sh' 'gh pr merge --squash' "$SHEPHERD"; echo $?)" \
  "#158: Abschlussnotiz wird vor 'gh pr merge --squash' (Direct-Merge) committet (Reihenfolge)"

# Fail-closed: kein pauschales Bash(git *) / Bash(gh *).
assert_true "$(! grep -qE 'Bash\(git \*\)|Bash\(gh \*\)' "$SETTINGS"; echo $?)" \
  "#91: kein pauschales Bash(git *)/Bash(gh *)"

# deny unverändert: .claude/** und .env* bleiben gesperrt. Bewusster jq-unabhängiger
# Fallback (läuft IMMER, auch ohne jq) neben der geparsten nothra/tch-gastro-services#224-Gegenrichtungsprüfung unten
# (AK4) – die dortige jq-Prüfung wird bei fehlendem jq übersprungen (Review-Finding nothra/tch-gastro-services#224).
# Write(...)-Pendants sind seit nothra/tch-gastro-services#240 entfernt (wirkungslos, Edit(...) deckt beide Tools ab).
{ grep -qF 'Edit(.claude/**)' "$SETTINGS" && grep -qF 'Edit(.env*)' "$SETTINGS" \
  && grep -qF 'Read(.env*)' "$SETTINGS" \
  && ! grep -qF 'Write(.claude/**)' "$SETTINGS" && ! grep -qF 'Write(.env*)' "$SETTINGS"; }
assert_true "$?" "#91/#240: deny behält .claude/** und .env* (Edit), ohne wirkungslose Write(...)"

# Skill-Doku: Code-erzeugende Skills committen/pushen über den Seam, nicht rohes git.
for sk in implement test refactor bug-fix; do
  grep -q 'factory-commit.sh' "$FACTORY_ROOT/.claude/commands/$sk.md"
  assert_true "$?" "#91: /$sk committet/pusht über scripts/factory-commit.sh"
done

# ─── nothra/tch-gastro-services#224: Top-Level-YAML-Freigabe + Write-Symmetrie (.claude/settings.json) ─
# AK5: die GEPARSTE allow-/deny-Liste wird geprüft (jq-Array-Lookup), nicht ein bloßer
# Text-Treffer irgendwo in der Datei – je Eintrag eine eigene Assertion, damit der Wegfall
# genau eines Eintrags genau die zugehörige Assertion rot färbt (AK5). AK6: $SETTINGS zeigt auf
# die committete Live-Datei im Arbeitsbaum, nicht auf tasks/patch-224.diff.
echo ""
echo "#224 Top-Level-YAML-Freigabe (.claude/settings.json):"

# nothra/tch-gastro-services#251: gemeinsame Werteliste für die jq-Schleife (unten) UND den jq-unabhängigen Grep-Fallback
# (weiter unten, außerhalb des HAS_JQ-Blocks) – als geteilte Konstante statt zweimal ausgeschrieben,
# damit beide Stellen nicht auseinanderdriften können (lessons/testing.md: Literale, die an zwei
# Stellen identisch bleiben müssen, sofort als geteilte Konstante einführen).
# Im Factory-Repo nur die Edit-Freigaben des Factory-Fragments (die App-Pfade gehören adoptierenden Projekten).
EDIT_ALLOW_88=(
  'Edit(scripts/**)' 'Edit(docs/**)' 'Edit(tasks/**)' 'Edit(config/**)'
  'Edit(.github/workflows/**)' 'Edit(*.json)' 'Edit(*.md)'
)

if [ "$HAS_JQ" -eq 1 ]; then
  # AK8: settings.json bleibt valides JSON mit unveränderter Grundstruktur.
  jq -e '.hooks and .permissions.allow and .permissions.deny' "$SETTINGS" >/dev/null 2>&1
  assert_true "$?" "#224: settings.json valides JSON mit hooks/permissions.allow/deny (AK8)"

  # AK1: Top-Level-YAML per Edit freigegeben. Root-verankert (führender Slash) statt slash-frei
  # (Security-Review-Finding: slash-freie Muster matchen laut Claude-Code-Doku auf jeder
  # Verzeichnistiefe, gitignore-Semantik – die Spec adressiert aber ausdrücklich nur
  # Top-Level-Dateien; alle vier realen Zieldateien liegen im Root, root-verankert verliert
  # nichts, schließt aber die Least-Privilege-Lücke für künftige *.yml/*.yaml-Dateien).
  # nothra/tch-gastro-services#251 erweitert dieselbe Liste um die 16 ursprünglichen nothra/tch-gastro-services#88-Edit(...)-Allow-Einträge (statt
  # einer zweiten, rumpfidentischen Schleife danebenzustellen – exakt das in
  # lessons/testing.md ("Neue Regressions-Assertion-Schleife … abgleichen") kodifizierte
  # nothra/tch-gastro-services#240-Learning; Präzedenzfall im selben File: die nothra/tch-gastro-services#240-AK1-Schleife unten vereint ebenso
  # zwei unterschiedliche Eintragsgruppen in einer Liste statt zwei getrennten Schleifen).
  # Die 16 nothra/tch-gastro-services#88-Einträge kommen aus dem gemeinsamen EDIT_ALLOW_88-Array oben (geteilt mit dem
  # Grep-Fallback weiter unten).
  for entry in 'Edit(/*.yml)' 'Edit(/*.yaml)' "${EDIT_ALLOW_88[@]}"; do
    jq -e --arg v "$entry" '.permissions.allow | index($v) != null' "$SETTINGS" >/dev/null 2>&1
    assert_true "$?" "#224/#251: allow (geparst) enthält '$entry'"
  done

  # nothra/tch-gastro-services#240 AK1 (alle 18 vormals in allow vorhandenen Write(...)-Einträge): Die 11 ursprünglichen
  # Write(<verzeichnis>/**)-Einträge (aus nothra/tch-gastro-services#88) und die 7 Write(<extension>)-Einträge (aus der
  # nothra/tch-gastro-services#224-Symmetrie-Ergänzung) waren laut claude --print-Probe gleichermaßen wirkungslos (nur
  # Edit(pfad) deckt Edit+Write ab – das eigentliche Verhalten liefert weiterhin Edit(/*.yml)/
  # Edit(/*.yaml) aus der Schleife oben) und wurden in nothra/tch-gastro-services#240 entfernt. Je Eintrag eine eigene
  # Assertion (nicht nur der pauschale Check weiter unten), damit ein versehentlich wieder
  # eingeführter Einzeleintrag namentlich rot färbt.
  for entry in 'Write(app/**)' 'Write(lib/**)' 'Write(db/**)' 'Write(e2e/**)' \
    'Write(types/**)' 'Write(scripts/**)' 'Write(docs/**)' 'Write(tasks/**)' \
    'Write(config/**)' 'Write(public/**)' 'Write(.github/workflows/**)' \
    'Write(*.ts)' 'Write(*.tsx)' 'Write(*.mjs)' 'Write(*.json)' 'Write(*.md)' \
    'Write(/*.yml)' 'Write(/*.yaml)'; do
    jq -e --arg v "$entry" '.permissions.allow | index($v) == null' "$SETTINGS" >/dev/null 2>&1
    assert_true "$?" "#240: allow (geparst) enthält NICHT mehr '$entry'"
  done

  # AK4 (Gegenrichtung): nothra/tch-gastro-services#88-Grenze unverändert – bestehende Edit(...)-Deny-Einträge bleiben
  # erhalten. Die Write(...)-Pendants waren wirkungslos und sind seit nothra/tch-gastro-services#240 entfernt (separat
  # unten geprüft).
  for entry in 'Edit(.claude/**)' 'Edit(.env*)' 'Read(.env*)'; do
    jq -e --arg v "$entry" '.permissions.deny | index($v) != null' "$SETTINGS" >/dev/null 2>&1
    assert_true "$?" "#224: deny (geparst) behält '$entry' (#88-Grenze)"
  done

  # nothra/tch-gastro-services#240 AK2 (alle 3 vormals in deny vorhandenen Write(...)-Einträge): Write(pnpm-lock.yaml),
  # Write(.claude/**) und Write(.env*) waren aus demselben Grund wie in allow wirkungslos und
  # wurden in nothra/tch-gastro-services#240 entfernt.
  for entry in 'Write(pnpm-lock.yaml)' 'Write(.claude/**)' 'Write(.env*)'; do
    jq -e --arg v "$entry" '.permissions.deny | index($v) == null' "$SETTINGS" >/dev/null 2>&1
    assert_true "$?" "#240: deny (geparst) enthält NICHT mehr '$entry'"
  done

  # AK1/AK2/AK7 (nothra/tch-gastro-services#240, umfassend): Keine einzelne Assertion oben deckt einen KÜNFTIGEN, nicht
  # in der Liste antizipierten Write(...)-Eintrag ab – deshalb zusätzlich eine pauschale
  # geparste Prüfung über allow UND deny hinweg, dass kein Eintrag mehr mit "Write(" beginnt.
  jq -e '[.permissions.allow[], .permissions.deny[]] | map(select(startswith("Write("))) | length == 0' \
    "$SETTINGS" >/dev/null 2>&1
  assert_true "$?" "#240: weder allow noch deny (geparst) enthalten irgendeinen Write(...)-Eintrag"
else
  echo "  • #224/#240: Permissions-Konsistenz (geparst) – übersprungen (jq fehlt)"
fi

# nothra/tch-gastro-services#240 (jq-unabhängiger Fallback, analog zum nothra/tch-gastro-services#91-Grep-Fallback oben): kein Write(...)-Eintrag
# mehr irgendwo in der Datei, unabhängig davon ob jq verfügbar ist.
assert_true "$(! grep -qF '"Write(' "$SETTINGS"; echo $?)" \
  "#240: settings.json enthält keinen 'Write(...)'-Eintrag mehr (jq-unabhängiger Fallback)"

# nothra/tch-gastro-services#251 (jq-unabhängiger Fallback, analog zum nothra/tch-gastro-services#91/#240-Muster): läuft IMMER, auch ohne jq,
# damit die Regressionsabsicherung für die 16 ursprünglichen nothra/tch-gastro-services#88-Edit(...)-Allow-Einträge
# nicht stillschweigend übersprungen wird, wenn jq in der Ausführungsumgebung fehlt (die
# geparste nothra/tch-gastro-services#251-Schleife oben wird dann laut Zeile "übersprungen (jq fehlt)" nicht erreicht).
# Nutzt dasselbe EDIT_ALLOW_88-Array wie die jq-Schleife oben (geteilte Konstante, kein
# Literal-Duplikat mehr – Refactor-Finding aus /review).
for entry in "${EDIT_ALLOW_88[@]}"; do
  grep -qF -- "$entry" "$SETTINGS"
  assert_true "$?" "#251: settings.json enthält '$entry' (jq-unabhängiger Fallback)"
done

# AK7: die stale Präsens-Aussage zu factory.defaults.yml ist korrigiert; die weiterhin gültige
# Patch-Workflow-Regel (nothra/tch-gastro-services#94) bleibt erhalten. Bislang die einzige Regressionsabsicherung für
# AK7 (/test-Selbstfund) – ohne diesen Test könnte ein künftiger Edit die Korrektur
# stillschweigend zurückdrehen, ohne dass irgendein Test rot würde.
WORKFLOW_LESSON="$FACTORY_ROOT/docs/factory/lessons/factory-workflow.md"

assert_true "$(! grep -qF 'außerhalb von `scripts/*`/`pnpm`-Scope sind nicht' "$WORKFLOW_LESSON"; echo $?)" \
  "#224: stale Präsens-Aussage zu factory.defaults.yml aus der Lesson entfernt (AK7)"

grep -qF 'ist seit nothra/tch-gastro-services#224 über eine generische' "$WORKFLOW_LESSON"
assert_true "$?" "#224: Lesson nennt die korrigierte Allow-Regel für Top-Level-YAML (AK7)"

grep -qF 'Patch NICHT von Hand schreiben (aus nothra/tch-gastro-services#94)' "$WORKFLOW_LESSON"
assert_true "$?" "#224: Patch-Workflow-Regel (#94) bleibt in der Lesson erhalten (AK7)"

# AK8 (nothra/tch-gastro-services#240): die stale Präsens-Aussage zur "existierenden" Write(...)-Liste ist korrigiert
# (Cleanup-Kandidat ist erledigt, nicht mehr offen) – ohne diesen Test könnte ein künftiger Edit
# die Korrektur stillschweigend zurückdrehen, ohne dass irgendein Test rot würde.
assert_true "$(! grep -qF 'existiert) ist aktuell' "$WORKFLOW_LESSON"; echo $?)" \
  "#240: stale Präsens-Aussage zur 'existierenden' Write(...)-Liste aus der Lesson entfernt (AK8)"

grep -qF 'in **nothra/tch-gastro-services#240 entfernt**' "$WORKFLOW_LESSON"
assert_true "$?" "#240: Lesson nennt die erledigte Entfernung der Write(...)-Liste (AK8)"

# ─── Task 101: Pipeline-Quality-Gates rufen echte Befehle (kein Platzhalter) ──
echo ""
echo "Task 101: Pipeline-Quality-Gates (echte Befehle statt Platzhalter):"

# (Struktur, yq-frei) Kein *_PLACEHOLDER-Gate-Befehl mehr in run-pipeline.sh.
# Der alte echo-Platzhalter lief immer auf Exit 0 → Gate fail-open. Regressions-Guard.
assert_true "$(! grep -q '_PLACEHOLDER' "$PIPELINE"; echo $?)" \
  "#101: run-pipeline.sh enthält keinen *_PLACEHOLDER-Gate-Befehl mehr (Regressions-Guard)"

# (Struktur) Echte Befehle über gate_command (Env-Override vor commands.* der Config) –
# konsistent mit pre-commit/pre-push (nothra/tch-gastro-services#431, AK-H3).
{ grep -qF 'gate_command lint required' "$PIPELINE" && grep -qF 'gate_command test required' "$PIPELINE" \
  && grep -qF 'gate_command coverage required' "$PIPELINE"; }
assert_true "$?" "#101/#431: run-pipeline.sh liest lint/test/coverage über gate_command (Env-Override wie Hook-Gates)"

# (Struktur) Kein pnpm-Default mehr im Orchestrator (nothra/tch-gastro-services#431 AK-H3): die Kommandos stehen in factory.config.yml.
grep -q 'pnpm' "$PIPELINE"
assert_exit 1 "$?" "#431 AK-H3: run-pipeline.sh enthält keinen hartkodierten pnpm-Aufruf mehr"

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
  cp_pipeline_libs "$TMP_G101"
  cp "$DEFAULTS_YML" "$TMP_G101/"
  echo "# ctx" > "$TMP_G101/docs/factory/PROJECT-CONTEXT.md"
  echo "# implement mock" > "$TMP_G101/.claude/commands/implement.md"
  echo "# Task 101: gate" > "$TMP_G101/tasks/task-101-gate.md"
  printf '#!/bin/sh\nexit 0\n' > "$TMP_G101/bin/claude"; chmod +x "$TMP_G101/bin/claude"
  git -C "$TMP_G101" init -q; git -C "$TMP_G101" add .
  git -C "$TMP_G101" -c user.email="t@t.com" -c user.name="t" commit -q -m init
  MARKER_G101="$TMP_G101/lint-ran.marker"
  # env -u (nothra/tch-gastro-services#264): Konsistenz-Härtung, kein beobachteter Vektor an dieser Stelle – dieser Lauf
  # bricht am Lint-Gate ab, bevor die PR_SHEPHERD-Verzweigung (Phase 7) erreichbar wäre.
  # Grundsatz: kein Testblock entscheidet aus der Env der aufrufenden Shell, sondern aus
  # seinem eigenen Setup. Real beobachtet wurde der Vektor im nothra/tch-gastro-services#212-W3-Block (siehe dort).
  g101_out=$(cd "$TMP_G101" && PATH="$TMP_G101/bin:$PATH" \
    FACTORY_LINT_COMMAND="touch '$MARKER_G101'; false" \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$TMP_G101/scripts/run-pipeline.sh" 101 2>&1 || true)
  printf '%s' "$g101_out" | grep -q 'Gate fehlgeschlagen: Lint'
  assert_true "$?" "#101: non-dry-run stoppt fail-closed am Lint-Gate (rotes Lint → Pipeline-Abbruch)"
  assert_true "$([ -f "$MARKER_G101" ]; echo $?)" \
    "#101: Lint-Gate führt den ECHTEN Befehl aus (Marker geschrieben, kein echo-Platzhalter)"
  rm -rf "$TMP_G101"
else
  skip_yq "#101: Verhaltens-Test rotes Lint-Gate (non-dry-run)"
fi

# ─── nothra/tch-gastro-services#431 AK-H3/H4/F-6: run-pipeline.sh liest die Gate-Kommandos aus der Config (Verhalten) ───
# Der Struktur-Grep oben belegt nur die Verdrahtung. Hier beide Richtungen am echten Konsumenten
# (Lesson nothra/tch-gastro-services#348: „Wert gültig" ≠ „Wert angewendet"): (a) ohne Env gewinnt commands.* aus der Config,
# (b) fehlt ein Pflicht-Kommando in Config UND Env, bricht der Lauf VOR dem ersten Agenten-Schritt ab.
echo ""
echo "#431 AK-H3/H4: run-pipeline.sh – Gate-Kommandos aus factory.config.yml, fail-closed:"
if [ "$HAS_YQ" = 1 ]; then
  TMP_H431="$(mktemp -d)"
  mkdir -p "$TMP_H431/scripts/checks" "$TMP_H431/scripts/lib" "$TMP_H431/tasks" \
           "$TMP_H431/docs/factory" "$TMP_H431/.claude/commands" "$TMP_H431/bin"
  cp "$PIPELINE" "$TMP_H431/scripts/"
  cp "$CHECKS_DIR/config-validation-check.sh" "$CHECKS_DIR/interrupt-check.sh" "$TMP_H431/scripts/checks/"
  cp_pipeline_libs "$TMP_H431"
  cp "$DEFAULTS_YML" "$TMP_H431/"
  echo "# ctx" > "$TMP_H431/docs/factory/PROJECT-CONTEXT.md"
  echo "# implement mock" > "$TMP_H431/.claude/commands/implement.md"
  echo "# Task 431: gate" > "$TMP_H431/tasks/task-431-gate.md"
  CLAUDE_CALLED_H431="$TMP_H431/claude-called.marker"
  printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$CLAUDE_CALLED_H431" > "$TMP_H431/bin/claude"; chmod +x "$TMP_H431/bin/claude"
  git -C "$TMP_H431" init -q
  # run_pipe_h431 <env-Zuweisungen…> – alle drei Gate-Variablen vorab entfernen (die Suite exportiert sie global).
  run_pipe_h431() {
    ( cd "$TMP_H431" && PATH="$TMP_H431/bin:$PATH" \
        env -u PR_SHEPHERD -u FACTORY_STAGE \
            -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_COVERAGE_COMMAND "$@" \
        bash "$TMP_H431/scripts/run-pipeline.sh" 431 2>&1 )
  }

  # (b) weder Config noch Env: Abbruch mit Schlüsselname, ohne dass /implement je startet.
  out_h431="$(run_pipe_h431)"; rc_h431=$?
  assert_exit 1 "$rc_h431" "#431 AK-H4/F-6: Pipeline ohne Lint-Kommando bricht mit exit 1 ab"
  assert_contains_286 "$out_h431" 'commands.lint' "#431 AK-H4/F-6: Pipeline ohne Lint-Kommando nennt den Schlüssel commands.lint"
  assert_true "$([ ! -f "$CLAUDE_CALLED_H431" ]; echo $?)" "#431 AK-H4/F-6: der Abbruch erfolgt vor dem ersten Agenten-Schritt (claude nie aufgerufen)"
  # Je Pflicht-Kommando ein eigener Fall: nur das fehlende wird genannt, die gesetzten nicht.
  out_h431="$(run_pipe_h431 FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true)"; rc_h431=$?
  assert_exit 1 "$rc_h431" "#431 AK-H4/F-6: Pipeline ohne Coverage-Kommando bricht mit exit 1 ab"
  assert_contains_286 "$out_h431" 'commands.coverage' "#431 AK-H4/F-6: fehlendes Coverage-Kommando wird mit commands.coverage genannt"
  assert_absent "$out_h431" 'commands.lint' "#431 AK-H4: das gesetzte Lint-Kommando wird nicht als fehlend gemeldet"
  assert_true "$([ ! -f "$CLAUDE_CALLED_H431" ]; echo $?)" "#431 AK-H4/F-6: auch bei fehlendem Coverage-Kommando startet kein Agent"

  # (a) Config-Kommandos werden angewendet: rotes Lint aus der Config stoppt den Lauf, Marker beweist die Ausführung.
  MARKER_H431="$TMP_H431/cfg-lint-ran.marker"
  cat > "$TMP_H431/factory.config.yml" <<CFG
commands:
  lint: "touch '$MARKER_H431'; false"
  test: "true"
  coverage: "true"
CFG
  out_h431="$(run_pipe_h431)"; rc_h431=$?
  assert_exit 1 "$rc_h431" "#431 AK-H3: rotes commands.lint aus der Config beendet den Lauf mit exit 1"
  assert_contains_286 "$out_h431" 'Gate fehlgeschlagen: Lint' "#431 AK-H3: rotes commands.lint aus der Config stoppt die Pipeline am Lint-Gate"
  assert_true "$([ -f "$MARKER_H431" ]; echo $?)" "#431 AK-H3: das Lint-Gate führt das Kommando aus der Config tatsächlich aus (Marker)"
  # Env-Override hat Vorrang vor der Config.
  rm -f "$MARKER_H431"
  out_h431="$(run_pipe_h431 FACTORY_LINT_COMMAND=false)"
  assert_contains_286 "$out_h431" 'Gate fehlgeschlagen: Lint' "#431 AK-H3: der Lauf scheitert mit dem Env-Kommando (false)"
  assert_true "$([ ! -f "$MARKER_H431" ]; echo $?)" "#431 AK-H3: FACTORY_LINT_COMMAND hat Vorrang – das Config-Kommando läuft nicht"
  rm -rf "$TMP_H431"
else
  skip_yq "#431 AK-H3/H4: run-pipeline.sh liest Gate-Kommandos aus der Config"
fi

# ─── nothra/tch-gastro-services#112: pr-closes-keyword-check.sh (CI-Gate für Closing-Keyword) ──────────
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

# ─── nothra/tch-gastro-services#149: Format-Gate in pre-push.sh (Prettier-Konformität) ─────────────────
# Ursache des Drifts (Task 149): format:check war an keinem Gate verdrahtet.
# Struktur UND Verhalten absichern – analog zum nothra/tch-gastro-services#101-Lint-Gate-Test.
echo ""
echo "#149 pre-push.sh Format-Gate (prettier --check):"

# (Struktur) Distinktive CODE-Zeile prüfen, nicht die Bezeichner allein: `FACTORY_FORMAT_COMMAND`
# und `format:check` kommen im Gate auch in Kommentar-Prosa vor – ein Grep darauf bliebe grün,
# wenn nur ein Kommentar stehen bliebe (nothra/tch-gastro-services#114 „Kommando ≠ Prosa-Erwähnung"). Der `${…-…}`-Ausdruck
# taucht ausschließlich in der Zuweisung auf und belegt zugleich den fail-closed-Default
# (`pnpm format:check` bei unset) und die Single-Dash-Semantik (leerer Wert = echter Opt-out).
grep -qF 'gate_command format optional' "$CHECKS_DIR/pre-push.sh"
assert_true "$?" "#149: pre-push.sh verdrahtet das Format-Gate über gate_command (Env FACTORY_FORMAT_COMMAND vor commands.format, #431)"

# (Verhalten) In einem Temp-Repo auf einem Feature-Branch die teuren Gates via Override
# neutralisieren (true), sodass allein das Format-Gate das Ergebnis bestimmt. Beweist,
# dass das Gate den ECHTEN Befehl ausführt (rot → blockiert) und der Env-Override greift.
TMP_G149="$(mktemp -d)"
# Gate als Kopie in der Wegwerf-Wurzel (Factory-Issue #32): das Original würde über FACTORY_DIR die echte
# CLAUDE.md/PROJECT-CONTEXT.md des Konsumenten lesen (Check 6, @import-Deckel) – ein indirekter Leser.
mkdir -p "$TMP_G149/scripts/checks" "$TMP_G149/scripts/lib"
cp "$CHECKS_DIR/pre-push.sh" "$TMP_G149/scripts/checks/"
cp "$SCRIPTS_DIR/lib/gate-config.sh" "$TMP_G149/scripts/lib/"
cp "$FACTORY_ROOT/factory.defaults.yml" "$TMP_G149/"
mk_feature_repo "$TMP_G149" feature/149-format-gate-test
run_prepush_149() { # $1 = FACTORY_FORMAT_COMMAND-Wert
  ( cd "$TMP_G149" && FACTORY_TEST_COMMAND=true FACTORY_TYPECHECK_COMMAND=true \
      FACTORY_FORMAT_COMMAND="$1" bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
}
run_prepush_149 "false"
assert_exit 1 "$?" "#149: Drift (Format-Befehl exit 1) blockiert den Push fail-closed"
run_prepush_149 "true"
assert_exit 0 "$?" "#149: konform (Format-Befehl exit 0) lässt den Push zu"
run_prepush_149 ""
assert_exit 0 "$?" "#149: leerer FACTORY_FORMAT_COMMAND deaktiviert das Gate (nicht blockierend)"
rm -rf "$TMP_G149"

# ─── nothra/tch-gastro-services#197: Größenabhängige Modell-Tier-Wahl (ADR-038) ────────────────────────
echo ""
echo "#197 Größenabhängige Modell-Tiers (ADR-038):"

TIER_LIB="$SCRIPTS_DIR/lib/tier-select.sh"
assert_true "$([[ -f "$TIER_LIB" ]]; echo $?)" "#197: scripts/lib/tier-select.sh vorhanden"

# Reine Funktionen im Subshell testbar OHNE claude/yq (Kern der ADR-038-Testbarkeit).
tsel()  { ( source "$TIER_LIB"; select_tier "$@" ); }
msize() { ( source "$TIER_LIB"; measure_size "$@" ); }

# select_tier: Schwellwert-Grenzen + Fail-Safe (F1/F2 = leere/nicht-numerische Größe → Fallback).
assert_true "$([[ "$(tsel 149 150 heavy)" = "light" ]]; echo $?)" "#197 AK1: select_tier 149/150 → light (unter Schwelle)"
assert_true "$([[ "$(tsel 150 150 heavy)" = "heavy" ]]; echo $?)" "#197 AK2: select_tier 150/150 → heavy (an Schwelle)"
assert_true "$([[ "$(tsel 500 150 heavy)" = "heavy" ]]; echo $?)" "#197 AK2: select_tier 500/150 → heavy (über Schwelle)"
assert_true "$([[ "$(tsel 5 6 heavy)"   = "light" ]]; echo $?)" "#197 AK4: select_tier 5/6 → light (Proxy unter Schwelle)"
assert_true "$([[ "$(tsel 6 6 heavy)"   = "heavy" ]]; echo $?)" "#197 AK5: select_tier 6/6 → heavy (Proxy an Schwelle)"
assert_true "$([[ "$(tsel '' 150 heavy)" = "heavy" ]]; echo $?)" "#197 F1/F2: leere Größe → Fail-Safe auf Fallback-Tier (heavy)"
assert_true "$([[ "$(tsel abc 150 heavy)" = "heavy" ]]; echo $?)" "#197 F1/F2: nicht-numerische Größe → Fail-Safe (heavy)"
assert_true "$([[ "$(tsel '' 150 light)" = "light" ]]; echo $?)" "#197: Fail-Safe respektiert den übergebenen Fallback-Tier"
assert_true "$([[ "$(tsel 200 abc heavy)" = "heavy" ]]; echo $?)" "#197: nicht-numerische Schwelle → Fail-Safe (kein stilles Downgrade auf light)"

# measure_size proxy: AK-Checkboxen im Abschnitt zählen; fehlende Spec/fehlender Abschnitt → leer.
PXR="$(mktemp -d)"; mkdir -p "$PXR/docs/specs"
printf '# Spec\n## Akzeptanzkriterien\n- [ ] A\n- [ ] B\n- [x] C\n## Weiter\n- [ ] nicht zaehlen\n' > "$PXR/docs/specs/spec-7-x.md"
assert_true "$([[ "$(msize proxy 7 "$PXR")" = "3" ]]; echo $?)" "#197 AK4/AK5: measure_size proxy zählt genau die AK-Checkboxen (3)"
printf '# Spec\n## Kontext\nkein AK-Abschnitt\n' > "$PXR/docs/specs/spec-8-x.md"
assert_true "$([[ -z "$(msize proxy 8 "$PXR")" ]]; echo $?)" "#197 F2: fehlender AK-Abschnitt → leer (Fail-Safe)"
printf '# Spec\n## Akzeptanzkriterien\n(noch keine Kriterien)\n' > "$PXR/docs/specs/spec-9-x.md"
assert_true "$([[ "$(msize proxy 9 "$PXR")" = "0" ]]; echo $?)" "#197: Abschnitt vorhanden, 0 Checkboxen → 0 (nicht leer)"
assert_true "$([[ -z "$(msize proxy 404 "$PXR")" ]]; echo $?)" "#197 F2: keine Spec-Datei → leer (Fail-Safe)"
assert_true "$([[ -z "$(msize bogus 7 "$PXR")" ]]; echo $?)" "#197: unbekanntes Signal → leer (Fail-Safe)"
rm -rf "$PXR"

# measure_size diff: added+deleted gegen origin/main; misst NUR die Branch-eigenen Änderungen.
DFR="$(mktemp -d)"
git init -q --bare "$DFR/origin.git"
git clone -q "$DFR/origin.git" "$DFR/work" 2>/dev/null
printf 'base\n' > "$DFR/work/f.txt"
git -C "$DFR/work" add .; git -C "$DFR/work" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$DFR/work" push -q origin HEAD:main 2>/dev/null
git -C "$DFR/work" checkout -q -b feature/x
printf 'a\nb\nc\n' >> "$DFR/work/f.txt"
git -C "$DFR/work" add .; git -C "$DFR/work" -c user.email=t@t -c user.name=t commit -q -m small
assert_true "$([[ "$(msize diff '' "$DFR/work")" = "3" ]]; echo $?)" "#197 AK1: measure_size diff summiert added+deleted der Branch-Commits (3)"
# AK3: ein Fremd-Commit auf origin/main darf die Größe NICHT aufblähen (Drei-Punkt/Merge-Base).
git clone -q "$DFR/origin.git" "$DFR/work2" 2>/dev/null
git -C "$DFR/work2" checkout -q -B main origin/main
seq 1 100 >> "$DFR/work2/f.txt"
git -C "$DFR/work2" add .; git -C "$DFR/work2" -c user.email=t@t -c user.name=t commit -q -m fremd
git -C "$DFR/work2" push -q origin main 2>/dev/null
assert_true "$([[ "$(msize diff '' "$DFR/work")" = "3" ]]; echo $?)" "#197 AK3: Fremd-Commit auf origin/main bläht die Diff-Größe nicht auf (weiter 3)"
# O4: Binärdatei (numstat "-") wird übersprungen → zählt nicht zur Größe (weiter 3, nicht mehr).
printf '\x00\x01\x02\xff\x00\x10' > "$DFR/work/bin.dat"
git -C "$DFR/work" add .; git -C "$DFR/work" -c user.email=t@t -c user.name=t commit -q -m binary
assert_true "$([[ "$(msize diff '' "$DFR/work")" = "3" ]]; echo $?)" "#197 O4: Binärdatei wird bei der Diff-Größe übersprungen (weiter 3)"
# F1: kein origin-Remote → git-Fehler → leer (Fail-Safe heavy).
git init -q "$DFR/noremote"
printf 'x\n' > "$DFR/noremote/f.txt"
git -C "$DFR/noremote" add .; git -C "$DFR/noremote" -c user.email=t@t -c user.name=t commit -q -m init
assert_true "$([[ -z "$(msize diff '' "$DFR/noremote")" ]]; echo $?)" "#197 F1: kein origin/main → measure_size diff leer (Fail-Safe)"
rm -rf "$DFR"

# End-to-End über run-pipeline --dry-run (nur mit yq, ADR-009-Prerequisite).
if [ "$HAS_YQ" = 1 ]; then
  # gemeinsames Scaffolding einer minimalen Pipeline-Repo-Kopie
  _mk_pipe_repo() {
    mkdir -p "$1/scripts/checks" "$1/scripts/lib" "$1/tasks" "$1/docs/factory" "$1/docs/specs"
    cp "$PIPELINE" "$1/scripts/"
    cp "$SCRIPTS_DIR/metrics.sh" "$1/scripts/"  # run-pipeline ruft metrics.sh im EXIT-Trap (ADR-045)
    cp "$CHECKS_DIR/config-validation-check.sh" "$1/scripts/checks/"
    cp_pipeline_libs "$1"
    cp "$DEFAULTS" "$1/"
    echo "# ctx" > "$1/docs/factory/PROJECT-CONTEXT.md"
  }

  # E2E-1: review mit kleinem Diff → light; security-review + test bleiben; CLAUDE_MODEL sticht.
  RVO="$(mktemp -d)"; RVW="$(mktemp -d)"
  git init -q --bare "$RVO/origin.git"
  _mk_pipe_repo "$RVW"
  echo "# Task 3: review-tier" > "$RVW/tasks/task-3-review-tier.md"
  printf '## Empfehlung\nAPPROVED\n' > "$RVW/tasks/review-3.md"   # Review-Loop endet sofort
  git -C "$RVW" init -q
  git -C "$RVW" remote add origin "$RVO/origin.git"
  git -C "$RVW" add .
  git -C "$RVW" -c user.email=t@t -c user.name=t commit -q -m base
  git -C "$RVW" push -q origin HEAD:main 2>/dev/null
  git -C "$RVW" checkout -q -b feature/tier
  printf 'x\ny\nz\n' >> "$RVW/tasks/task-3-review-tier.md"   # kleiner Diff (< 150)
  git -C "$RVW" add .
  git -C "$RVW" -c user.email=t@t -c user.name=t commit -q -m small
  rv_out=$(bash "$RVW/scripts/run-pipeline.sh" 3 --dry-run 2>&1 || true)
  printf '%s' "$rv_out" | grep -q '/review 3 (model: claude-sonnet-5-5, max 30 turns)'
  assert_true "$?" "#197 AK1/AK3 (E2E): kleiner Diff → /review auf light (Basis origin/main)"
  printf '%s' "$rv_out" | grep -q '/security-review 3 (model: claude-opus-5-5, max 30 turns)'
  assert_true "$?" "#197 AK6 (E2E): /security-review immer heavy (kein tier_by_size)"
  printf '%s' "$rv_out" | grep -q '/test 3 (model: claude-sonnet-5-5, max 20 turns)'
  assert_true "$?" "#197 AK7 (E2E): übriger Skill /test bleibt light"
  rv_ovr=$(CLAUDE_MODEL=my-forced-model bash "$RVW/scripts/run-pipeline.sh" 3 --dry-run 2>&1 || true)
  printf '%s' "$rv_ovr" | grep -q '/review 3 (model: my-forced-model'
  assert_true "$?" "#197 AK10 (E2E): CLAUDE_MODEL-Override sticht die größenabhängige Wahl"
  # AK2 (E2E, Symmetrie zum proxy-Signal): großer Diff (>= 150) → /review auf heavy.
  seq 1 200 >> "$RVW/tasks/task-3-review-tier.md"
  git -C "$RVW" add .
  git -C "$RVW" -c user.email=t@t -c user.name=t commit -q -m big
  rv_big=$(bash "$RVW/scripts/run-pipeline.sh" 3 --dry-run 2>&1 || true)
  printf '%s' "$rv_big" | grep -q '/review 3 (model: claude-opus-5-5, max 30 turns)'
  assert_true "$?" "#197 AK2 (E2E): großer Diff (>= 150) → /review auf heavy"
  rm -rf "$RVO" "$RVW"

  # E2E-2: implement-Proxy klein (<6) → light, groß (>=6) → heavy.
  IMS="$(mktemp -d)"; _mk_pipe_repo "$IMS"
  echo "# Task 4: small" > "$IMS/tasks/task-4-small.md"
  printf '# Spec\n## Akzeptanzkriterien\n- [ ] A\n- [ ] B\n- [ ] C\n## Weiter\n- [ ] x\n' > "$IMS/docs/specs/spec-4-small.md"
  git -C "$IMS" init -q; git -C "$IMS" add .; git -C "$IMS" -c user.email=t@t -c user.name=t commit -q -m init
  ims_out=$(bash "$IMS/scripts/run-pipeline.sh" 4 --dry-run 2>&1 || true)
  printf '%s' "$ims_out" | grep -q '/implement 4 (model: claude-sonnet-5-5, max 20 turns)'
  assert_true "$?" "#197 AK4 (E2E): kleiner Proxy (3 AK < 6) → /implement auf light"
  rm -rf "$IMS"

  IML="$(mktemp -d)"; _mk_pipe_repo "$IML"
  echo "# Task 5: large" > "$IML/tasks/task-5-large.md"
  printf '# Spec\n## Akzeptanzkriterien\n- [ ] A\n- [ ] B\n- [ ] C\n- [ ] D\n- [ ] E\n- [ ] F\n- [ ] G\n- [ ] H\n' > "$IML/docs/specs/spec-5-large.md"
  git -C "$IML" init -q; git -C "$IML" add .; git -C "$IML" -c user.email=t@t -c user.name=t commit -q -m init
  iml_out=$(bash "$IML/scripts/run-pipeline.sh" 5 --dry-run 2>&1 || true)
  printf '%s' "$iml_out" | grep -q '/implement 5 (model: claude-opus-5-5, max 20 turns)'
  assert_true "$?" "#197 AK5 (E2E): großer Proxy (8 AK >= 6) → /implement auf heavy"
  rm -rf "$IML"

  # AK9 + F3: Config-Gate akzeptiert reale tier_by_size-Defaults, lehnt ungültige Werte ab.
  G4="$(mktemp -d)"
  bash "$GATE" "$DEFAULTS" >/dev/null 2>&1
  assert_true "$?" "#197 AK9: Defaults mit tier_by_size bestehen das Config-Gate (Regel 4c)"
  printf 'skills:\n  review: { tier_by_size: { threshold: 200 } }\n' > "$G4/ok.yml"
  bash "$GATE" "$DEFAULTS" "$G4/ok.yml" >/dev/null 2>&1
  assert_true "$?" "#197: Override justiert tier_by_size.threshold → exit 0"
  printf 'skills:\n  review: { tier_by_size: { threshold: viele } }\n' > "$G4/nonint.yml"
  bash "$GATE" "$DEFAULTS" "$G4/nonint.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "#197 F3: tier_by_size.threshold nicht-integer → fail-closed"
  printf 'skills:\n  review: { tier_by_size: { threshold: 0 } }\n' > "$G4/zero.yml"
  bash "$GATE" "$DEFAULTS" "$G4/zero.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "#197 F3: tier_by_size.threshold = 0 → fail-closed"
  printf 'skills:\n  review: { tier_by_size: { signal: bogus } }\n' > "$G4/sig.yml"
  bash "$GATE" "$DEFAULTS" "$G4/sig.yml" >/dev/null 2>&1; rc=$?
  assert_true "$([[ $rc -ne 0 ]]; echo $?)" "#197 F3: ungültiges tier_by_size.signal → fail-closed"
  rm -rf "$G4"

  # AK7: übrige pipeline-getriebene Skills + default bleiben light UND tragen KEIN tier_by_size
  # (keine Tier-Änderung durch nothra/tch-gastro-services#197).
  ak7_ok=0
  for s in test refactor codify pr-shepherd; do
    [ "$(yq ".skills.\"$s\".tier" "$DEFAULTS")" = "light" ] || ak7_ok=1
    [ "$(yq ".skills.\"$s\" | has(\"tier_by_size\")" "$DEFAULTS")" = "false" ] || ak7_ok=1
  done
  [ "$(yq '.default.tier' "$DEFAULTS")" = "light" ] || ak7_ok=1
  assert_true "$ak7_ok" "#197 AK7: test/refactor/codify/pr-shepherd + default = light ohne tier_by_size"

  # nothra/tch-gastro-services#201 AK1/AK2/AK5: Phase-1-Skills (requirements/architecture/release-notes) sind pipeline-inert
  # (run-pipeline.sh ruft sie nie über run_skill auf) und tragen daher KEINEN eigenen skills-Eintrag
  # mehr. Ihre effektive Auflösung fällt über cfg_skill_field (.skills.<s>.<feld> // .default.<feld>)
  # sauber auf default-light / max_turns 10 zurück — kein stilles Heavy-Upgrade.
  ph1_ok=0
  for s in requirements architecture release-notes; do
    [ "$(yq ".skills | has(\"$s\")" "$DEFAULTS")" = "false" ] || ph1_ok=1
    [ "$(yq ".skills.\"$s\".tier // .default.tier" "$DEFAULTS")" = "light" ] || ph1_ok=1
    [ "$(yq ".skills.\"$s\".max_turns // .default.max_turns" "$DEFAULTS")" = "10" ] || ph1_ok=1
  done
  assert_true "$ph1_ok" "#201 AK1/AK2: requirements/architecture/release-notes ohne eigenen Eintrag → effektiv default-light, max_turns 10"

else
  skip_yq "#197 End-to-End (run-pipeline get_model) + Config-Gate Regel 4c + AK7/AK12"
fi

# AK11 (yq-frei): token-efficiency.md §6 verweist auf die reale SSOT, nicht auf eine README-Tabelle.
TOKEFF="$FACTORY_ROOT/docs/factory/guidelines/token-efficiency.md"
grep -q 'factory.defaults.yml' "$TOKEFF"
assert_true "$?" "#197 AK11: token-efficiency.md verweist auf die reale SSOT (factory.defaults.yml)"
grep -q 'README.md (Tier-Tabelle)' "$TOKEFF"
assert_true "$([ $? -ne 0 ]; echo $?)" "#197 AK11: veralteter README-Tier-Tabellen-Verweis ist entfernt"

# ─── nothra/tch-gastro-services#212: Endzustands-Verifikation (ADR-040) ────────────────────────────────
echo ""
echo "#212 evaluate_final_state (reine Entscheidung, ADR-040):"

VFS_LIB="$SCRIPTS_DIR/lib/verify-final-state.sh"
assert_true "$([[ -f "$VFS_LIB" ]]; echo $?)" "#212: scripts/lib/verify-final-state.sh vorhanden"
# shellcheck source=/dev/null
source "$VFS_LIB"

# Signatur: evaluate_final_state <tree_status> <unpushed> <pr_shepherd> <pr_state> <is_draft> <auto_merge>
efs()     { evaluate_final_state "$@" >/dev/null 2>&1; }   # nur Exit-Code
efs_msg() { evaluate_final_state "$@" 2>/dev/null; }        # nur Reason (stdout)

# AK2: sauber + gepusht, ohne PR_SHEPHERD → verifiziert (Erfolg)
efs clean 0 false "" "" "";  assert_exit 0 "$?" "#212 AK2: sauber+gepusht (PR_SHEPHERD=false) → verifiziert (exit 0)"
# AK1: ungepushte Commits → nicht verifiziert + gemeldeter Zustand
efs clean 3 false "" "" "";  assert_exit 1 "$?" "#212 AK1: ungepushte Commits → nicht verifiziert (exit 1)"
printf '%s' "$(efs_msg clean 3 false '' '' '')" | grep -q 'Ungepushte Commits'
assert_true "$?" "#212 AK1: meldet 'Ungepushte Commits' als realen Zustand"
# F3: uncommittete Änderungen (dirty) → nicht verifiziert
efs dirty 0 false "" "" "";  assert_exit 1 "$?" "#212 F3: uncommittete Änderungen → nicht verifiziert (exit 1)"
printf '%s' "$(efs_msg dirty 0 false '' '' '')" | grep -q 'Working Tree nicht sauber'
assert_true "$?" "#212 F3: meldet 'Working Tree nicht sauber'"
# F2: kein Upstream (nicht-numerischer unpushed) → fail-closed
efs clean NO_UPSTREAM false "" "" ""; assert_exit 1 "$?" "#212 F2: kein Upstream → fail-closed nicht verifiziert"
printf '%s' "$(efs_msg clean NO_UPSTREAM false '' '' '')" | grep -q 'Push-Zustand nicht verifizierbar'
assert_true "$?" "#212 F2: meldet 'Push-Zustand nicht verifizierbar'"
# AK3: PR_SHEPHERD, PR noch Draft → blockiert
efs clean 0 true OPEN true none; assert_exit 1 "$?" "#212 AK3: Draft-PR (PR_SHEPHERD) → nicht verifiziert"
printf '%s' "$(efs_msg clean 0 true OPEN true none)" | grep -q 'PR noch Draft'
assert_true "$?" "#212 AK3: meldet 'PR noch Draft'"
# AK4: PR_SHEPHERD, nicht Draft, aber weder gemergt noch Auto-Merge scharf → blockiert
efs clean 0 true OPEN false none; assert_exit 1 "$?" "#212 AK4: weder gemergt noch Auto-Merge scharf → nicht verifiziert"
printf '%s' "$(efs_msg clean 0 true OPEN false none)" | grep -q 'weder gemergt noch Auto-Merge'
assert_true "$?" "#212 AK4: meldet 'weder gemergt noch Auto-Merge scharfgeschaltet'"
# AK4-Edge: geschlossener, NICHT gemergter PR (pr_state=CLOSED) → blockiert (kein Sonderfall)
efs clean 0 true CLOSED false none; assert_exit 1 "$?" "#212 AK4-Edge: geschlossener (nicht gemergter) PR → nicht verifiziert"
# AK5: PR_SHEPHERD, nicht Draft, Auto-Merge scharf → verifiziert (Erfolg)
efs clean 0 true OPEN false set;  assert_exit 0 "$?" "#212 AK5: Auto-Merge scharf → verifiziert (exit 0)"
# AK6: PR_SHEPHERD, PR bereits MERGED → verifiziert (Erfolg)
efs clean 0 true MERGED false none; assert_exit 0 "$?" "#212 AK6: PR MERGED → verifiziert (exit 0)"
# F1: PR_SHEPHERD, gh nicht verwertbar (leerer pr_state) → fail-closed
efs clean 0 true "" "" "";    assert_exit 1 "$?" "#212 F1: gh ohne verwertbaren PR-Zustand → fail-closed"
printf '%s' "$(efs_msg clean 0 true '' '' '')" | grep -q 'PR-Zustand nicht verifizierbar'
assert_true "$?" "#212 F1: meldet 'PR-Zustand nicht verifizierbar'"

# nothra/tch-gastro-services#298: MERGED zählt unabhängig vom Unpushed-Status sofort als Erfolg (Branch-Auto-Delete
# nach Squash-Merge macht origin/<branch> weg → unpushed ist NO_UPSTREAM/nicht-numerisch,
# soll den MERGED-Kurzschluss aber nicht verhindern).
efs clean NO_UPSTREAM true MERGED false none; assert_exit 0 "$?" "#298 AK: MERGED + unpushed=NO_UPSTREAM → verifiziert (exit 0)"
efs clean 3 true MERGED false none; assert_exit 0 "$?" "#298 AK: MERGED + unpushed=3 → ebenfalls verifiziert (exit 0)"
# Regressions-Guard: Tree-Check bleibt VOR dem MERGED-Kurzschluss
efs dirty 0 true MERGED false none; assert_exit 1 "$?" "#298 Regressions-Guard: dirty + MERGED → weiterhin 'Working Tree nicht sauber'"
printf '%s' "$(efs_msg dirty 0 true MERGED false none)" | grep -q 'Working Tree nicht sauber'
assert_true "$?" "#298 Regressions-Guard: meldet 'Working Tree nicht sauber' trotz MERGED"
# Regressions-Guard: nicht-MERGED + nicht-numerisch unpushed bleibt fail-closed
efs clean NO_UPSTREAM true OPEN false none; assert_exit 1 "$?" "#298 Regressions-Guard: OPEN + unpushed nicht-numerisch → weiterhin fail-closed"
printf '%s' "$(efs_msg clean NO_UPSTREAM true OPEN false none)" | grep -q 'Push-Zustand nicht verifizierbar'
assert_true "$?" "#298 Regressions-Guard: meldet 'Push-Zustand nicht verifizierbar'"
# spec-298 Fehlerszenario 2: geschlossener, NICHT gemergter PR + kein Upstream (Branch dennoch
# server-seitig gelöscht) → bleibt fail-closed, kein stiller Erfolg für abgelehnte PRs.
efs clean NO_UPSTREAM true CLOSED false none; assert_exit 1 "$?" "#298 Fehlerszenario 2: CLOSED + unpushed=NO_UPSTREAM → weiterhin fail-closed"
printf '%s' "$(efs_msg clean NO_UPSTREAM true CLOSED false none)" | grep -q 'Push-Zustand nicht verifizierbar'
assert_true "$?" "#298 Fehlerszenario 2: meldet 'Push-Zustand nicht verifizierbar'"
# spec-298 Fehlerszenario 1: pr_state leer (gh-Fehler, F1) UND unpushed gleichzeitig
# nicht-numerisch → Unpushed-Check greift zuerst (pr_state ist nicht MERGED), Meldung bleibt F2.
efs clean NO_UPSTREAM true "" "" ""; assert_exit 1 "$?" "#298 Fehlerszenario 1: leerer pr_state + unpushed nicht-numerisch → weiterhin fail-closed"
printf '%s' "$(efs_msg clean NO_UPSTREAM true '' '' '')" | grep -q 'Push-Zustand nicht verifizierbar'
assert_true "$?" "#298 Fehlerszenario 1: meldet 'Push-Zustand nicht verifizierbar' (nicht 'PR-Zustand')"

echo ""
echo "#212 verify_final_state (I/O über echtes git + gestubbtes gh):"

VFS_REPO="$(mktemp -d)"; VFS_ORIGIN="$(mktemp -d)"; mkdir -p "$VFS_REPO/bin"
git init --bare -q "$VFS_ORIGIN"
git -C "$VFS_REPO" init -q
git -C "$VFS_REPO" -c init.defaultBranch=main symbolic-ref HEAD refs/heads/feature/x 2>/dev/null
git -C "$VFS_REPO" config user.email t@t; git -C "$VFS_REPO" config user.name t
printf 'hi\n' > "$VFS_REPO/f.txt"; git -C "$VFS_REPO" add .; git -C "$VFS_REPO" commit -q -m init
git -C "$VFS_REPO" remote add origin "$VFS_ORIGIN"
VFS_BR="$(git -C "$VFS_REPO" rev-parse --abbrev-ref HEAD)"
git -C "$VFS_REPO" push -q origin "$VFS_BR"

# Fakten neu erzeugen: schreibt einen gh-Stub, der genau eine TSV-Zeile ausgibt (isDraft state auto).
# HINWEIS (Coverage-Loch, bewusst): Der Stub ignoriert die gh-Argumente und bildet die TSV fest
# nach → der `-q '[.isDraft,.state,(.autoMergeRequest!=null)]|@tsv'`-Ausdruck in verify-final-state.sh
# wird NICHT ausgeführt (kein echtes gh im Harness). Getestet ist nur das IFS-read-Mapping; die
# gh-Filter-Semantik ist durch Codelesen abgesichert (siehe Kommentar an der Lib-Zeile).
mkgh() { printf '#!/bin/sh\nprintf "%%s\\t%%s\\t%%s\\n" "%s" "%s" "%s"\n' "$1" "$2" "$3" > "$VFS_REPO/bin/gh"; chmod +x "$VFS_REPO/bin/gh"; }
# gh-Stub, der scheitert (simuliert nicht verwertbaren Aufruf → F1)
failgh() { printf '#!/bin/sh\nexit 1\n' > "$VFS_REPO/bin/gh"; chmod +x "$VFS_REPO/bin/gh"; }

# Sauber + gepusht, PR_SHEPHERD=false → verifiziert
verify_final_state "$VFS_BR" false "$VFS_REPO" >/dev/null 2>&1
assert_exit 0 "$?" "#212 I/O AK2: sauber+gepusht (false) → verifiziert (exit 0)"
# Ein ungepushter Commit → nicht verifiziert
printf 'more\n' >> "$VFS_REPO/f.txt"; git -C "$VFS_REPO" add .; git -C "$VFS_REPO" commit -q -m second
verify_final_state "$VFS_BR" false "$VFS_REPO" >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O AK1: ungepushter Commit → nicht verifiziert (exit 1)"
git -C "$VFS_REPO" push -q origin "$VFS_BR"    # wieder sauber+gepusht
# Dirty Working Tree → nicht verifiziert
printf 'dirty\n' >> "$VFS_REPO/f.txt"
verify_final_state "$VFS_BR" false "$VFS_REPO" >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O F3: dirty Working Tree → nicht verifiziert (exit 1)"
git -C "$VFS_REPO" checkout -q -- f.txt        # wieder sauber
# Branch ohne origin-Tracking → fail-closed
git -C "$VFS_REPO" checkout -q -b feature/no-upstream
verify_final_state feature/no-upstream false "$VFS_REPO" >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O F2: kein origin-Tracking → fail-closed (exit 1)"
git -C "$VFS_REPO" checkout -q "$VFS_BR"
# Detached HEAD (branch='HEAD') bzw. leerer Branch-Name → fail-closed, nie gegen origin/HEAD
# (Default-Branch) auflösen (neuer Guard aus dem Review-Rework).
verify_final_state HEAD false "$VFS_REPO" >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O: detached HEAD (branch='HEAD') → fail-closed (exit 1)"
verify_final_state "" false "$VFS_REPO" >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O: leerer Branch-Name → fail-closed (exit 1)"
# PR_SHEPHERD=true über gh-Stub (PATH im Subshell exportiert → (cd && gh) findet den Stub)
mkgh false OPEN true
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 0 "$?" "#212 I/O AK5: nicht Draft + Auto-Merge scharf → verifiziert (exit 0)"
mkgh false MERGED false
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 0 "$?" "#212 I/O AK6: PR MERGED → verifiziert (exit 0)"
mkgh false OPEN false
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O AK4: nicht Draft, weder gemergt noch Auto-Merge → nicht verifiziert (exit 1)"
mkgh true OPEN false
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O AK3: Draft-PR → nicht verifiziert (exit 1)"
failgh
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 1 "$?" "#212 I/O F1: gh-Aufruf scheitert → fail-closed (exit 1)"

# nothra/tch-gastro-services#298 I/O: origin/<branch> gelöscht (Branch-Auto-Delete nach Squash-Merge) + PR MERGED
# → unpushed ist nicht verwertbar (NO_UPSTREAM), MERGED-Kurzschluss muss trotzdem greifen.
git -C "$VFS_REPO" push -q origin --delete "$VFS_BR"
mkgh false MERGED false
( export PATH="$VFS_REPO/bin:$PATH"; verify_final_state "$VFS_BR" true "$VFS_REPO" ) >/dev/null 2>&1
assert_exit 0 "$?" "#298 I/O: origin/<branch> gelöscht + MERGED → verifiziert (exit 0)"
rm -rf "$VFS_REPO" "$VFS_ORIGIN"

echo ""
echo "#212 Pipeline-Wiring (run-pipeline.sh, ADR-040):"

# Sourced die Lib und ruft die Verifikationsfunktion auf
grep -q 'source .*lib/verify-final-state.sh' "$PIPELINE"
assert_true "$?" "#212: run-pipeline.sh sourct verify-final-state.sh"
grep -q 'verify_final_state' "$PIPELINE"
assert_true "$?" "#212: run-pipeline.sh ruft verify_final_state auf"
# Verletzung wird als Interrupt geloggt (Typ INCOMPLETE_OUTCOME, ADR-040 §3)
grep -q 'INCOMPLETE_OUTCOME' "$PIPELINE"
assert_true "$?" "#212: BLOCKED-Endzustand wird per raise-interrupt (INCOMPLETE_OUTCOME) geloggt"
# Reihenfolge (Kommando, nicht Prosa): Verifikation steht VOR der Erfolgs-Ausgabe
verify_line=$(grep -n 'verify_final_state' "$PIPELINE" | head -1 | cut -d: -f1)
banner_line=$(grep -n 'Pipeline erfolgreich abgeschlossen' "$PIPELINE" | head -1 | cut -d: -f1)
{ [ -n "$verify_line" ] && [ -n "$banner_line" ] && [ "$verify_line" -lt "$banner_line" ]; }
assert_true "$?" "#212: Endzustands-Verifikation läuft VOR der Erfolgs-Ausgabe"
# --dry-run überspringt die Verifikation (F4)
grep -q 'DRY-RUN.*Endzustands-Verifikation übersprungen' "$PIPELINE"
assert_true "$?" "#212 F4: --dry-run-Zweig überspringt die Verifikation"

echo ""
echo "#212 AK8: Interrupt-Sentinel stoppt Pipeline vor der Erfolgs-Ausgabe (Regressions-Guard):"
if [ "$HAS_YQ" = 1 ]; then
  TMP_INT="$(mktemp -d)"
  mkdir -p "$TMP_INT/scripts/checks" "$TMP_INT/scripts/lib" "$TMP_INT/tasks" \
           "$TMP_INT/docs/factory" "$TMP_INT/.claude/commands" "$TMP_INT/bin"
  cp "$PIPELINE" "$TMP_INT/scripts/"
  cp "$CHECKS_DIR/config-validation-check.sh" "$CHECKS_DIR/interrupt-check.sh" "$TMP_INT/scripts/checks/"
  cp "$SCRIPTS_DIR/raise-interrupt.sh" "$TMP_INT/scripts/"
  cp_pipeline_libs "$TMP_INT"
  cp "$DEFAULTS_YML" "$TMP_INT/"
  echo "# ctx" > "$TMP_INT/docs/factory/PROJECT-CONTEXT.md"
  echo "# implement mock" > "$TMP_INT/.claude/commands/implement.md"
  echo "# Task 77: interrupt" > "$TMP_INT/tasks/task-77-interrupt.md"
  # Mock claude: signalisiert beim implement-Aufruf einen Interrupt (schreibt Sentinel), exit 0.
  cat > "$TMP_INT/bin/claude" <<'CLEOF'
#!/bin/sh
FACTORY_DIR="$PWD" bash "$PWD/scripts/raise-interrupt.sh" 77 PUSH_GATE_BLOCKED \
  "fremdes getracktes Artefakt blockiert den Push-Gate" >/dev/null 2>&1
exit 0
CLEOF
  chmod +x "$TMP_INT/bin/claude"
  git -C "$TMP_INT" init -q; git -C "$TMP_INT" add .
  git -C "$TMP_INT" -c user.email=t@t -c user.name=t commit -q -m init
  # env -u (nothra/tch-gastro-services#264): Konsistenz-Härtung, kein beobachteter Vektor an dieser Stelle – der Lauf
  # stoppt bereits in Phase 1 am Interrupt-Sentinel (run_skill → interrupt-check.sh) und
  # erreicht die PR_SHEPHERD-Verzweigung (Phase 7) nie. Steht trotzdem hier: kein Testblock
  # hängt vom Env-Zustand der aufrufenden Shell ab. Realer Vektor: nothra/tch-gastro-services#212-W3-Block unten.
  int_out=$(cd "$TMP_INT" && PATH="$TMP_INT/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$TMP_INT/scripts/run-pipeline.sh" 77 2>&1); int_rc=$?
  assert_true "$([[ "$int_rc" -ne 0 ]]; echo $?)" "#212 AK8: Interrupt-Sentinel → Non-Zero-Exit"
  printf '%s' "$int_out" | grep -q 'Pipeline erfolgreich abgeschlossen'
  assert_true "$([ $? -ne 0 ]; echo $?)" "#212 AK8: Erfolgs-Ausgabe wird bei Interrupt NICHT erreicht"
  grep -q 'PUSH_GATE_BLOCKED' "$TMP_INT/tasks/interrupt-log.jsonl" 2>/dev/null
  assert_true "$?" "#212 AK8: Stopp-Grund (PUSH_GATE_BLOCKED) ist im interrupt-log protokolliert"
  rm -rf "$TMP_INT"
else
  skip_yq "#212 AK8: Interrupt-Sentinel stoppt Pipeline"
fi

echo ""
echo "#212 WICHTIG-3: Verifikations-Interrupt end-to-end (Kern-Symptomatik #212):"
# Der neue Pfad „Endzustand verletzt → raise-interrupt INCOMPLETE_OUTCOME → exit 1" wird echt
# ausgeführt (nicht nur grep-verifiziert): mock claude (no-op) durchläuft alle Phasen, kein
# Sentinel, aber am Ende liegt ein ungepushter Commit → Verifikation blockiert den Erfolg.
if [ "$HAS_YQ" = 1 ]; then
  TMP_E2E="$(mktemp -d)"; TMP_E2E_ORIGIN="$(mktemp -d)"
  mkdir -p "$TMP_E2E/scripts/checks" "$TMP_E2E/scripts/lib" "$TMP_E2E/tasks" \
           "$TMP_E2E/docs/factory" "$TMP_E2E/.claude/commands" "$TMP_E2E/bin"
  cp "$PIPELINE" "$TMP_E2E/scripts/"
  cp "$CHECKS_DIR/config-validation-check.sh" "$CHECKS_DIR/interrupt-check.sh" "$TMP_E2E/scripts/checks/"
  cp "$SCRIPTS_DIR/raise-interrupt.sh" "$TMP_E2E/scripts/"
  cp_pipeline_libs "$TMP_E2E"
  cp "$DEFAULTS_YML" "$TMP_E2E/"
  echo "# ctx" > "$TMP_E2E/docs/factory/PROJECT-CONTEXT.md"
  # SKILL-<name>-Marker wie in scaffold_310: daran erkennt der Stub im Prompt, welches Skill
  # läuft ('SKILL-review' ist kein Teilstring von 'SKILL-security-review').
  for s in implement review test refactor security-review codify; do
    printf '# SKILL-%s mock\n' "$s" > "$TMP_E2E/.claude/commands/$s.md"
  done
  echo "# Task 78: e2e" > "$TMP_E2E/tasks/task-78-e2e.md"
  # Der Stub schreibt die Reports IM Aufruf (seit nothra/tch-gastro-services#312 gilt ein report-erzeugendes Skill nur
  # so als erfolgreich – ein vorab abgelegter APPROVED wäre stale und bräche den Lauf schon
  # in Phase 2 ab). Der Zähler variiert den Inhalt, damit auch der zweite und dritte Lauf
  # gegen dasselbe Scaffold einen VERÄNDERTEN Report sehen. Alle drei Dateien bleiben
  # untrackt (sie entstehen erst nach dem letzten `git add .`) – Preflight und
  # verify_final_state bewerten nur getrackte Diffs.
  cat > "$TMP_E2E/bin/claude" <<'CLAUDE_E2E'
#!/bin/sh
n=$(cat "$PWD/.stub-calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$PWD/.stub-calls"
case "$*" in
  *SKILL-security-review*) printf '## Ergebnis\nPASSED\nAufruf %s\n' "$n" > "$PWD/tasks/security-78.md" ;;
  *SKILL-review*)          printf '## Empfehlung\nAPPROVED\nAufruf %s\n' "$n" > "$PWD/tasks/review-78.md" ;;
esac
exit 0
CLAUDE_E2E
  chmod +x "$TMP_E2E/bin/claude"
  git init --bare -q "$TMP_E2E_ORIGIN"
  git -C "$TMP_E2E" init -q
  git -C "$TMP_E2E" symbolic-ref HEAD refs/heads/feature/e2e 2>/dev/null
  git -C "$TMP_E2E" config user.email t@t; git -C "$TMP_E2E" config user.name t
  git -C "$TMP_E2E" add .; git -C "$TMP_E2E" commit -q -m init
  git -C "$TMP_E2E" remote add origin "$TMP_E2E_ORIGIN"
  E2E_BR="$(git -C "$TMP_E2E" rev-parse --abbrev-ref HEAD)"
  git -C "$TMP_E2E" push -q origin "$E2E_BR"
  # Unvollständiger Endzustand: ein ungepushter Commit (Working Tree bleibt sauber → Preflight ok)
  echo "extra" > "$TMP_E2E/extra.txt"; git -C "$TMP_E2E" add .; git -C "$TMP_E2E" commit -q -m unpushed
  # env -u: siehe nothra/tch-gastro-services#264 – ohne Neutralisierung entscheidet ein exportiertes PR_SHEPHERD über
  # Phase 7 und über den PR-Zweig der Endzustands-Verifikation, nicht dieses Test-Setup.
  e2e_out=$(cd "$TMP_E2E" && PATH="$TMP_E2E/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$TMP_E2E/scripts/run-pipeline.sh" 78 2>&1); e2e_rc=$?
  assert_true "$([[ "$e2e_rc" -ne 0 ]]; echo $?)" "#212 W3: unverifizierter Endzustand → Non-Zero-Exit (E2E)"
  printf '%s' "$e2e_out" | grep -q 'Pipeline erfolgreich abgeschlossen'
  assert_true "$([ $? -ne 0 ]; echo $?)" "#212 W3: kein Erfolgs-Banner bei unverifiziertem Endzustand (E2E)"
  printf '%s' "$e2e_out" | grep -q 'Endzustand nicht verifiziert'
  assert_true "$?" "#212 W3: meldet den realen Zustand (Endzustand nicht verifiziert)"
  grep -q '"type":"INCOMPLETE_OUTCOME"' "$TMP_E2E/tasks/interrupt-log.jsonl" 2>/dev/null
  assert_true "$?" "#212 W3: INCOMPLETE_OUTCOME wird ins interrupt-log geschrieben (ADR-006)"
  # Positiv-Gegenprobe: sauber+gepusht → Erfolgs-Banner erreicht (kein Fehlalarm)
  git -C "$TMP_E2E" push -q origin "$E2E_BR"
  # env -u: siehe nothra/tch-gastro-services#264 (identischer Leck-Vektor wie im Negativ-Fall darüber).
  e2e_ok=$(cd "$TMP_E2E" && PATH="$TMP_E2E/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$TMP_E2E/scripts/run-pipeline.sh" 78 2>&1); e2e_ok_rc=$?
  assert_exit 0 "$e2e_ok_rc" "#212 W3: sauber+gepushter Endzustand → Erfolg (exit 0, Gegenprobe)"
  printf '%s' "$e2e_ok" | grep -q 'Pipeline erfolgreich abgeschlossen'
  assert_true "$?" "#212 W3: Erfolgs-Banner erscheint bei verifiziertem Endzustand"

  # ─── nothra/tch-gastro-services#264: Env-Isolation der realen run-pipeline.sh-Testaufrufe ────────────
  # Verhaltensbeweis (kein Grep auf `env -u`): Dieselbe Positiv-Gegenprobe läuft erneut,
  # diesmal mit PR_SHEPHERD/FACTORY_STAGE EXPORTIERT in der Shell, die run-pipeline.sh
  # aufruft. Ohne die `env -u`-Härtung erbt der Wegwerf-Lauf PR_SHEPHERD=true, startet
  # Phase 7 (pr-shepherd), bricht dort mangels .claude/commands/pr-shepherd.md ab und
  # verlangt zusätzlich einen verwertbaren PR-Zustand (gh) → Non-Zero-Exit statt
  # Erfolgs-Banner. Der Export ist die divergenzerzeugende Aktion – ohne ihn wäre der
  # Block blind (Lesson nothra/tch-gastro-services#253).
  # Er lebt bewusst INNERHALB der Kommando-Substitutions-Subshell: so kann er weder in
  # nachfolgende Blöcke lecken noch dort einen künftig ungehärteten Aufruf maskieren
  # (ein `unset` danach würde eine vom Aufrufer geerbte Variable mit verschlucken).
  # Dritter Lauf gegen dasselbe $TMP_E2E-Scaffold: nutzt bewusst den Endzustand der
  # Gegenprobe weiter (sauber + gepusht) – idempotent, weil die Wegwerf-Läufe nur untrackte
  # Artefakte erzeugen und verify_final_state ausschließlich getrackte Diffs bewertet.
  e2e_dirty_env=$(cd "$TMP_E2E" && export PR_SHEPHERD=true FACTORY_STAGE=3 && \
    PATH="$TMP_E2E/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$TMP_E2E/scripts/run-pipeline.sh" 78 2>&1); e2e_dirty_env_rc=$?
  assert_exit 0 "$e2e_dirty_env_rc" "#264: exportiertes PR_SHEPHERD/FACTORY_STAGE ändert das Ergebnis nicht (exit 0)"
  printf '%s' "$e2e_dirty_env" | grep -q 'Pipeline erfolgreich abgeschlossen'
  assert_true "$?" "#264: Erfolgs-Banner erscheint trotz exportiertem PR_SHEPHERD/FACTORY_STAGE"
  # Pfadspezifisches Negativ-Signal: 'Phase 7' erscheint ausschließlich im PR_SHEPHERD-Zweig.
  printf '%s' "$e2e_dirty_env" | grep -q 'Phase 7'
  assert_true "$([ $? -ne 0 ]; echo $?)" "#264: Phase 7 (pr-shepherd) wird nicht ungewollt ausgelöst"
  # Zusätzlicher Positiv-Beleg (kein zweiter unabhängiger Beweis): die Verifikation meldet den
  # git-Modus-Text; bei pr_shepherd=true lautete er '(sauber, gepusht, PR merge-ready/gemergt)'.
  printf '%s' "$e2e_dirty_env" | grep -q 'Endzustand verifiziert (sauber, gepusht)'
  assert_true "$?" "#264: Endzustands-Verifikation läuft im git-Modus (ohne PR-Invarianten)"

  rm -rf "$TMP_E2E" "$TMP_E2E_ORIGIN"
else
  skip_yq "#212 W3: Verifikations-Interrupt end-to-end"
  skip_yq "#264: Env-Isolation gegen exportiertes PR_SHEPHERD/FACTORY_STAGE"
fi

# ─── nothra/tch-gastro-services#264 Drift-Guard: JEDE reale run-pipeline.sh-Aufrufstelle bleibt gehärtet ──────
# Der Verhaltenstest oben hängt an genau EINER der fünf gehärteten Aufrufstellen. Entfernt
# jemand `env -u` an einer der anderen (oder fügt eine neue ungehärtete hinzu), bliebe die
# Suite grün – genau die stille Regressionsklasse, die zu nothra/tch-gastro-services#262/#264 geführt hat. Dieser
# Guard schließt sie strukturell: er liest run-tests.sh selbst und verlangt für jeden
# realen (non-`--dry-run`) Aufruf die Neutralisierung.
#
# Block- statt Fragment-Grep (Lesson nothra/tch-gastro-services#114/#255/#261/#265): Die Aufrufe sind
# Multi-Zeilen-Konstrukte mit `\`-Fortsetzung – awk fügt die Fortsetzungszeilen erst zur
# logischen Kommandozeile zusammen und bewertet dann. Ein zeilenweiser Grep würde die
# `env -u`-Zeile und die `bash`-Zeile nie zusammen sehen.
#
# Erkannt wird die Pipeline-Referenz in AUSFÜHRUNGS-Position, nicht ein einzelnes Literal:
# als Dateiname ODER als Pfad-Variable (`$PIPELINE`, `$PIPELINE214` – in dieser Datei bereits
# etablierte Schreibweise), quotiert wie unquotiert, hinter `bash`/`sh` wie direkt ausgeführt.
# Lese-Kontexte (`cp "$PIPELINE" …`, `grep … "$PIPELINE"`, Zuweisung, Kommentar) fallen
# strukturell heraus, weil die Referenz dort nicht in Kommando-Position steht – das ist
# robuster als ein gepflegter Ausschluss-Katalog, der beim nächsten `sed`-Aufruf veraltet.
#
# Reichweite: nur DIREKTE Aufrufe aus dieser Datei. Der transitive Weg (`factory-poll.sh`
# startet `run-pipeline.sh`) ist derzeit kein Leck – die realen `factory-poll.sh`-Aufrufe der
# Suite laufen gegen einen `run-pipeline.sh`-Stub, und `factory-poll.sh` liest `PR_SHEPHERD`/
# `FACTORY_STAGE` selbst nicht. Ändert sich eines von beidem, braucht es einen zweiten Guard.
echo ""
echo "#264 Drift-Guard: reale run-pipeline.sh-Aufrufe in run-tests.sh sind env-isoliert:"

RUN_TESTS_SELF="$CHECKS_DIR/tests/run-tests.sh"
# Datei- und Variablenname stehen nur als Werte hier und gehen per `%s` in die Fixtures –
# so sieht keine Zeile DIESER Datei selbst wie eine Aufrufstelle aus (sonst liest der Guard
# seine eigenen Kontroll-Fixtures als ungehärteten Aufruf und wird falsch rot).
RP_NAME='run-pipeline.sh'
PV_NAME='PIPELINE'

# audit_pipeline_calls <datei> – gibt je realem (non-dry-run) Aufruf eine Zeile
# "<zeile>\t<OK|MISSING>" aus; der Nicht-Vakuitäts-Zähler unten liest beide Zustände mit.
# Exit 1, sobald mindestens ein MISSING dabei ist (fail-closed).
# Verlangt wird die kanonische Flag-Reihenfolge, nicht nur die Semantik: die gleichwertige
# Umkehrung `-u FACTORY_STAGE -u PR_SHEPHERD` gilt als MISSING – bewusst ein Fehlalarm-Risiko
# statt eines Lecks, und es hält die fünf Aufrufstellen auf einer Schreibweise.
audit_pipeline_calls() {
  awk -v rp='run-pipeline[.]sh' -v pv='[$][{]?[A-Za-z_0-9]*PIPELINE[A-Za-z_0-9]*[}]?' '
    BEGIN {
      # <ref> = ein Token, das run-pipeline.sh bezeichnet (Dateiname oder Pfad-Variable).
      ref    = "[\"\047]?[^ \t\"\047;]*(" rp "|" pv ")[\"\047]?"
      # …hinter einem Interpreter: `bash`/`sh` [flags] <ref>
      interp = "(^|[^A-Za-z0-9_.-])(bash|sh)[ \t]+(-[^ \t]+[ \t]+)*" ref
      # …oder in Kommando-Position: Zeilenanfang/Trenner, davor nur Env-Zuweisungen.
      direct = "(^|[;&|(])[ \t]*([A-Za-z_][A-Za-z_0-9]*=[^ \t]*[ \t]+)*" ref "([ \t]|$)"
    }
    { line = $0; sub(/[ \t]+$/, "", line) }
    line ~ /\\$/ { sub(/\\$/, "", line); buf = buf line; next }
    {
      cmd = buf line; buf = ""
      if (cmd ~ /^[ \t]*#/) next
      if (cmd !~ interp && cmd !~ direct) next
      if (cmd ~ /--dry-run/) next
      if (cmd ~ /env -u PR_SHEPHERD -u FACTORY_STAGE/) { print NR "\tOK"; next }
      print NR "\tMISSING"; found = 1
    }
    END { exit(found ? 1 : 0) }
  ' "$1"
}

# Positiv-Kontrollen: jede reale Aufruf-Schreibweise OHNE env -u wird erkannt (Guard nicht
# vacuously grün) – literal, über Pfad-Variable, unquotiert und ohne bash-Präfix.
TMP_DG264="$(mktemp)"
printf 'x=$(cd "$T" && PATH="$T/bin:$PATH" \\\n  bash "$T/scripts/%s" 1 2>&1)\n' "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 1 "$?" "#264 Guard: literaler Aufruf ohne env -u wird erkannt (Positiv-Kontrolle)"

printf 'x=$(bash "$%s" 1 2>&1)\n' "$PV_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 1 "$?" "#264 Guard: Aufruf über die Pfad-Variable wird erkannt (Positiv-Kontrolle)"

printf 'x=$(bash $T/scripts/%s 1 2>&1)\n' "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 1 "$?" "#264 Guard: unquotierter Aufruf wird erkannt (Positiv-Kontrolle)"

printf 'x=$(cd "$T" && "$T/scripts/%s" 78 2>&1)\n' "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 1 "$?" "#264 Guard: direkt ausgeführter Aufruf (ohne bash-Präfix) wird erkannt"

# Negativ-Kontrolle A: derselbe Aufruf MIT env -u (mehrzeilig) → sauber.
printf 'x=$(cd "$T" && PATH="$T/bin:$PATH" \\\n  env -u PR_SHEPHERD -u FACTORY_STAGE \\\n  bash "$T/scripts/%s" 1 2>&1)\n' "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 0 "$?" "#264 Guard: gehärteter Multi-Zeilen-Aufruf gilt als sauber (Negativ-Kontrolle)"

# Negativ-Kontrolle B: auch die Pfad-Variablen-Form gilt gehärtet als sauber (die neue
# Erkennung produziert keinen Dauer-Fehlalarm auf der Schreibweise, die sie zusätzlich fasst).
printf 'x=$(env -u PR_SHEPHERD -u FACTORY_STAGE bash "$%s" 1 2>&1)\n' "$PV_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 0 "$?" "#264 Guard: gehärteter Aufruf über die Pfad-Variable gilt als sauber"

# Negativ-Kontrolle C: Der Dry-Run betritt Phase 7 zwar, bricht dort aber nicht ab (run_skill
# kehrt vor dem skill_file-Check zurück) und ändert nur die Ausgabe; keine Dry-Run-Assertion
# hängt an diesen Zeilen – deshalb bleibt die Ausnahme fail-open, statt 11 Aufrufstellen
# mitzuhärten (nothra/tch-gastro-services#264, Review-Runde-3-Auflage).
printf 'x=$(bash "$T/scripts/%s" 1 --dry-run 2>&1 || true)\n' "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 0 "$?" "#264 Guard: --dry-run-Aufruf ohne env -u ist erlaubt (Negativ-Kontrolle)"

# Negativ-Kontrolle D: Lese-/Kopier-/Zuweisungs-Kontexte sind keine Aufrufstellen. Ohne diese
# Diskriminierung wäre die erweiterte Erkennung auf jeder der ~40 `"$PIPELINE"`-Lesezeilen rot.
printf 'cp "$%s" "$T/scripts/"\ngrep -q load_config "$%s"\n%s="$FACTORY_ROOT/scripts/%s"\n' \
  "$PV_NAME" "$PV_NAME" "$PV_NAME" "$RP_NAME" > "$TMP_DG264"
audit_pipeline_calls "$TMP_DG264" >/dev/null 2>&1
assert_exit 0 "$?" "#264 Guard: cp/grep/Zuweisung auf die Pfad-Variable sind keine Aufrufstellen"
rm -f "$TMP_DG264"

# Nicht-Vakuität: der Guard findet die bekannten realen Aufrufstellen tatsächlich. Untergrenze
# statt exakter Zahl – eine künftige (gehärtete) sechste Stelle soll den Guard nicht rot machen.
dg264_calls="$(audit_pipeline_calls "$RUN_TESTS_SELF" || true)"
dg264_total="$(printf '%s\n' "$dg264_calls" | grep -cE '(OK|MISSING)$' || true)"
assert_true "$([ "$dg264_total" -ge 5 ]; echo $?)" \
  "#264 Guard: findet die realen run-pipeline.sh-Aufrufstellen (>=5 erkannt, kein Leerlauf)"

# Akzeptanzkriterium: keine davon ist ungehärtet.
audit_pipeline_calls "$RUN_TESTS_SELF" >/dev/null 2>&1
assert_exit 0 "$?" "#264 Guard: ALLE realen run-pipeline.sh-Aufrufe in run-tests.sh tragen env -u"

echo ""
echo "#264 K1: Lesson und Index nennen die Härtung als erledigt:"
# ─── nothra/tch-gastro-services#264 K1: Lesson/Index nennen die Härtung als erledigt, nicht als offenen Follow-up ──
# Ohne diese Regressionsabsicherung könnte ein künftiger Edit die Präsens-Korrektur still
# zurückdrehen (gleiches Muster wie nothra/tch-gastro-services#224 AK7 / nothra/tch-gastro-services#240 AK8 oben).
assert_true "$(! grep -qF 'ist als eigenes Issue getrackt, nicht Teil der Task' "$WORKFLOW_LESSON"; echo $?)" \
  "#264: stale 'Follow-up offen'-Aussage aus der PR_SHEPHERD-Lesson entfernt"
grep -qF 'Die Härtung ist in nothra/tch-gastro-services#264 umgesetzt' "$WORKFLOW_LESSON"
assert_true "$?" "#264: Lesson nennt den Erledigt-Stand der Härtung"

echo ""
echo "#212 AK10: Coverage-Temp-Konvention ist dokumentiert (die .gitignore-Muster prüft die Projekt-Suite):"
# AK10: die dokumentierte Konvention benennt den ignorierten Temp-Pfad-Präfix
grep -qF '.coverage-tmp' "$FACTORY_ROOT/docs/factory/guidelines/testing-standards.md"
assert_true "$?" "#212 AK10: testing-standards.md dokumentiert den ignorierten Coverage-Temp-Präfix"

echo ""
echo "#212 AK7: pr-shepherd eskaliert unter Stage 3 (Endzustand der committeten Live-Datei):"
# `.claude/**` ist für den Agenten hard-denied → die Änderung kam via tasks/patch-212.diff (vom
# Menschen angewandt + committet, Patch danach entfernt – Lesson nothra/tch-gastro-services#145). Der Test prüft daher den
# ENDZUSTAND der committeten Live-Datei $SHEPHERD direkt, nicht das transiente Patch-Artefakt
# (Kopplung an patch-212.diff wäre im auslieferbaren Zustand zwangsläufig rot – Review nothra/tch-gastro-services#212).
{ grep -qF 'FACTORY_STAGE=3' "$SHEPHERD" && grep -qF 'niemals eine interaktive Freigabe' "$SHEPHERD"; }
assert_true "$?" "#212 AK7: Stage-3-Blocker → raise-interrupt statt interaktiver Freigabefrage"
grep -qF 'kein autonomes `git rm --cached`' "$SHEPHERD"
assert_true "$?" "#212 AK7: verbietet autonomes 'git rm --cached'"
grep -qF 'PUSH_GATE_BLOCKED' "$SHEPHERD"
assert_true "$?" "#212 AK7: benennt Interrupt-Typ PUSH_GATE_BLOCKED für blockierendes Artefakt"

# ─── nothra/tch-gastro-services#262: Flag-Guard für Commit-Messages (ADR-042) ──────────────────────────
echo ""
echo "#262 commit-msg-check.sh (Flag-Guard, fail-closed):"

CMCHECK="$CHECKS_DIR/commit-msg-check.sh"
INSTALL_HOOKS="$SCRIPTS_DIR/install-hooks.sh"
assert_true "$([[ -f "$CMCHECK" ]]; echo $?)" "#262: scripts/checks/commit-msg-check.sh vorhanden"
assert_true "$([[ -f "$INSTALL_HOOKS" ]]; echo $?)" "#262: scripts/install-hooks.sh vorhanden"

TMP_CM="$(mktemp -d)"

# cm_check <message> → schreibt die Message in eine Datei und ruft das Prüfskript so auf,
# wie Git es tut (Pfad zur Message-Datei als $1). Exit-Code wird durchgereicht.
cm_check() {
  printf '%s' "$1" > "$TMP_CM/msg"
  bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
}

# AK1/AK3 + Fehlerszenario „leere Message": alles außer exakt `--help`/`-h` passiert.
cm_pass_cases=(
  "fix: foo|reguläre Conventional-Commit-Message"
  "-x|'-'-Präfix, aber kein bekanntes Flag (Abgrenzung)"
  "-refactor: aufräumen|'-'-Präfix mit Text (Abgrenzung)"
  "docs: --help im Fließtext erklären|Flag nur als Teilstring einer längeren Message"
  "--help und mehr|Flag mit Zusatztext (kein exakter Treffer)"
  "|leere Message (Leer-Prüfung bleibt bei git/factory-commit – kein Duplikat)"
)
for cm_case in "${cm_pass_cases[@]}"; do
  IFS='|' read -r cm_msg cm_desc <<< "$cm_case"
  cm_check "$cm_msg"
  assert_exit 0 "$?" "#262: commit-msg-check lässt durch – $cm_desc"
done

# AK2: exakt `--help`/`-h` (auch mit umgebendem Whitespace) → fail-closed.
cm_fail_cases=(
  "--help|exaktes --help"
  "-h|exaktes -h"
  "  --help  |--help mit umgebendem Whitespace (getrimmt)"
)
for cm_case in "${cm_fail_cases[@]}"; do
  IFS='|' read -r cm_msg cm_desc <<< "$cm_case"
  cm_check "$cm_msg"
  assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – $cm_desc"
done

# `git commit -m` hängt einen Zeilenumbruch an – der Guard darf daran nicht scheitern.
printf '\n\n-h\n\n' > "$TMP_CM/msg"
bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – -h mit Leerzeilen (getrimmt)"

# Editor-Pfad: Git entfernt die Template-Kommentarzeilen erst NACH dem Hook (`--cleanup`) –
# der Guard muss sie selbst verwerfen, sonst greift er bei `git commit` ohne `-m` überhaupt
# nicht (empirisch mit git 2.50 belegt: der Hook sieht das Template, der Commit entstand).
printf '%s\n' "--help" "" \
  "# Please enter the commit message for your changes. Lines starting" \
  "# with '#' will be ignored, and an empty message aborts the commit." \
  "#" "# On branch feature/262-flag-guard-commit-message" > "$TMP_CM/msg"
bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – --help mit Editor-Template-Kommentaren (Editor-Pfad)"

# Gegenprobe: verworfen werden nur die Kommentarzeilen, nicht der Inhalt.
printf '%s\n' "fix: foo" "" "# Please enter the commit message for your changes." > "$TMP_CM/msg"
bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
assert_exit 0 "$?" "#262: commit-msg-check lässt durch – reguläre Message mit Editor-Template-Kommentaren"

# Ein Flag, das NUR in einer Kommentarzeile steht, ist keine Message (Rest ist leer).
printf '%s\n' "# --help" > "$TMP_CM/msg"
bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
assert_exit 0 "$?" "#262: commit-msg-check lässt durch – '--help' steht nur in einer Kommentarzeile"

# Konfigurierter Kommentar-Präfix (core.commentChar) wird respektiert – und zwar in beide
# Richtungen: mit ';' als Präfix ist eine ';'-Zeile Kommentar und eine '#'-Zeile Inhalt.
CM_CFG_REPO="$TMP_CM/commentchar"
mkdir -p "$CM_CFG_REPO"
git init -q -b main "$CM_CFG_REPO" >/dev/null 2>&1
git -C "$CM_CFG_REPO" config core.commentChar ";"
printf '%s\n' "--help" "; Bitte gib eine Commit-Message ein" > "$CM_CFG_REPO/msg"
( cd "$CM_CFG_REPO" && bash "$CMCHECK" "msg" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – --help mit ';'-Kommentar bei core.commentChar=';'"
printf '%s\n' "--help" "# kein Kommentar, wenn core.commentChar=';'" > "$CM_CFG_REPO/msg"
( cd "$CM_CFG_REPO" && bash "$CMCHECK" "msg" ) >/dev/null 2>&1
assert_exit 0 "$?" "#262: commit-msg-check lässt durch – '#'-Zeile zählt bei core.commentChar=';' als Inhalt (Diskriminierung)"

# core.commentString (mehrzeichiger Präfix, ab git 2.45) – bislang ungetestet: der erste
# Schleifendurchlauf inkl. `break` und die Mehrzeichen-Fähigkeit, der einzige Grund, warum
# `commentString` überhaupt unterstützt wird.
CM_CFG_REPO_STR="$TMP_CM/commentstring"
mkdir -p "$CM_CFG_REPO_STR"
git init -q -b main "$CM_CFG_REPO_STR" >/dev/null 2>&1
git -C "$CM_CFG_REPO_STR" config core.commentString "//"
printf '%s\n' "--help" "// Bitte gib eine Commit-Message ein" > "$CM_CFG_REPO_STR/msg"
( cd "$CM_CFG_REPO_STR" && bash "$CMCHECK" "msg" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – --help mit mehrzeichigem Kommentar bei core.commentString='//'"
printf '%s\n' "--help" "# kein Kommentar, wenn core.commentString='//'" > "$CM_CFG_REPO_STR/msg"
( cd "$CM_CFG_REPO_STR" && bash "$CMCHECK" "msg" ) >/dev/null 2>&1
assert_exit 0 "$?" "#262: commit-msg-check lässt durch – '#'-Zeile zählt bei core.commentString='//' als Inhalt (Diskriminierung)"

# core.commentChar=auto – bislang ungetestet: der `auto`-Zweig (`[ "$configured_prefix" =
# "auto" ] ||`) muss beim Default '#' bleiben, statt den Präfix wörtlich auf 'auto' zu setzen.
# Ohne diesen Test würde ein Entfernen der `auto`-Sonderbehandlung (dokumentierte
# ADR-042-Designentscheidung) lautlos die in Runde 2 geschlossene Editor-Pfad-Lücke reißen.
CM_CFG_REPO_AUTO="$TMP_CM/commentauto"
mkdir -p "$CM_CFG_REPO_AUTO"
git init -q -b main "$CM_CFG_REPO_AUTO" >/dev/null 2>&1
git -C "$CM_CFG_REPO_AUTO" config core.commentChar "auto"
printf '%s\n' "--help" "# Please enter the commit message for your changes." > "$CM_CFG_REPO_AUTO/msg"
( cd "$CM_CFG_REPO_AUTO" && bash "$CMCHECK" "msg" ) >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: commit-msg-check lehnt ab – --help mit '#'-Template bei core.commentChar='auto' (Fallback auf Default, ADR-042)"

printf '%s' "--help" > "$TMP_CM/msg"
cm_out=$(bash "$CMCHECK" "$TMP_CM/msg" 2>&1)
printf '%s' "$cm_out" | grep -qF 'sieht aus wie ein CLI-Flag'
assert_true "$?" "#262: Ablehnung nennt den Grund (Message sieht aus wie ein Flag)"

# Exit-Kontrakt aus dem Skript-Header: 1 = fachliche Ablehnung, 2 = Infrastruktur-Fehler. Ohne
# eigene Assertion bliebe ein Vertauschen der beiden Codes unbemerkt (alle anderen Fälle prüfen
# nur „≠ 0").
printf '%s' "--help" > "$TMP_CM/msg"
bash "$CMCHECK" "$TMP_CM/msg" >/dev/null 2>&1
assert_exit 1 "$?" "#262: fachliche Ablehnung (Flag erkannt) endet mit exit 1"
bash "$CMCHECK" "$TMP_CM/gibt-es-nicht" >/dev/null 2>&1
assert_exit 2 "$?" "#262: Infrastruktur-Fehler (Message-Datei fehlt) endet mit exit 2"

# Fehlerszenario: kein/leeres Argument bzw. unlesbare Datei → fail-closed, kein Durchwinken.
bash "$CMCHECK" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: ohne Argument → exit ≠ 0 (fail-closed)"
bash "$CMCHECK" "" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: leeres Argument → exit ≠ 0 (fail-closed)"
bash "$CMCHECK" "$TMP_CM/gibt-es-nicht" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: nicht existierende Message-Datei → exit ≠ 0 (fail-closed)"
printf '%s' "fix: foo" > "$TMP_CM/unreadable"; chmod 000 "$TMP_CM/unreadable"
if [ ! -r "$TMP_CM/unreadable" ]; then
  bash "$CMCHECK" "$TMP_CM/unreadable" >/dev/null 2>&1
  assert_true "$([ $? -ne 0 ]; echo $?)" "#262: unlesbare Message-Datei → exit ≠ 0 (fail-closed)"
else
  echo "  • #262: unlesbare Message-Datei – übersprungen (Prozess umgeht Dateirechte, z. B. root)"
fi
chmod 644 "$TMP_CM/unreadable"

echo ""
echo "#262 install-hooks.sh (idempotente Hook-Installation, ADR-042):"

# ih_repo <name> → Wegwerf-Repo mit kopiertem Installer + Check-Skript (alle
# Laufzeit-Abhängigkeiten mitkopieren, bash-gotchas §5); gibt den Arbeitsbaum-Pfad aus.
ih_repo() {
  local wt="$TMP_CM/$1"
  mkdir -p "$wt/scripts/checks"
  git init -q -b main "$wt" >/dev/null 2>&1
  git -C "$wt" config user.email t@t
  git -C "$wt" config user.name t
  cp "$INSTALL_HOOKS" "$wt/scripts/"
  cp "$CMCHECK" "$wt/scripts/checks/"
  printf '%s\n' "$wt"
}

WT=$(ih_repo install)
# Veralteter Hook-Stand vor dem Lauf → der Installer muss ihn aktualisieren (Retrofit).
printf '#!/usr/bin/env bash\necho veraltet\n' > "$WT/.git/hooks/pre-push"
ih_out=$(bash "$WT/scripts/install-hooks.sh" 2>&1); ih_rc=$?
assert_exit 0 "$ih_rc" "#262 AK7: install-hooks.sh läuft im git-Repo durch (exit 0)"
printf '%s' "$ih_out" | grep -qF 'vorhandener pre-push Hook wird durch den Factory-Stand ersetzt'
assert_true "$?" "#262: Ersetzen eines abweichenden vorhandenen Hooks wird gemeldet (kein stiller Verlust)"
for hook in pre-commit pre-push commit-msg; do
  [ -x "$WT/.git/hooks/$hook" ]
  assert_true "$?" "#262 AK7: Hook '$hook' installiert und ausführbar"
done
grep -qF 'bash scripts/checks/pre-commit.sh' "$WT/.git/hooks/pre-commit"
assert_true "$?" "#262 AK7: pre-commit-Hook ruft pre-commit.sh auf"
grep -qF 'bash scripts/checks/pre-push.sh' "$WT/.git/hooks/pre-push"
assert_true "$?" "#262 AK7: pre-push-Hook ruft pre-push.sh auf (veralteter Stand überschrieben)"
grep -qF 'veraltet' "$WT/.git/hooks/pre-push"
assert_true "$([ $? -ne 0 ]; echo $?)" "#262 AK7: veralteter Hook-Inhalt bleibt nicht stehen"
{ grep -qF 'scripts/checks/commit-msg-check.sh' "$WT/.git/hooks/commit-msg" &&
  grep -qF 'bash "$CHECK" "$1"' "$WT/.git/hooks/commit-msg"; }
assert_true "$?" "#262 AK7: commit-msg-Hook ruft commit-msg-check.sh mit dem Message-Pfad auf"

# Idempotenz: zweiter Lauf → exit 0, unveränderte Hook-Inhalte, keine Ersetzungs-Warnung.
hooks_before=$(cat "$WT/.git/hooks/pre-commit" "$WT/.git/hooks/pre-push" "$WT/.git/hooks/commit-msg")
ih_out=$(bash "$WT/scripts/install-hooks.sh" 2>&1); ih_rc=$?
assert_exit 0 "$ih_rc" "#262 AK7: wiederholter Aufruf → exit 0 (idempotent)"
printf '%s' "$ih_out" | grep -qF 'wird durch den Factory-Stand ersetzt'
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: identischer Hook-Stand meldet keine Ersetzung (Warnung diskriminiert)"
hooks_after=$(cat "$WT/.git/hooks/pre-commit" "$WT/.git/hooks/pre-push" "$WT/.git/hooks/commit-msg")
[ "$hooks_before" = "$hooks_after" ]
assert_true "$?" "#262 AK7: wiederholter Aufruf verändert die Hook-Inhalte nicht"

# Kein git-Repo → fail-closed (kein stilles „nichts installiert, alles gut").
mkdir -p "$TMP_CM/nogit/scripts"; cp "$INSTALL_HOOKS" "$TMP_CM/nogit/scripts/"
bash "$TMP_CM/nogit/scripts/install-hooks.sh" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: install-hooks.sh ohne git-Repo → exit ≠ 0 (fail-closed)"

# Gesetztes core.hooksPath (z. B. husky): Git führt NUR Hooks aus diesem Verzeichnis aus –
# eine Installation nach .git/hooks wäre wirkungslos. Fail-closed statt Schein-Erfolg.
WT=$(ih_repo hookspath)
git -C "$WT" config core.hooksPath ".husky"
ih_out=$(bash "$WT/scripts/install-hooks.sh" 2>&1); ih_rc=$?
assert_true "$([ $ih_rc -ne 0 ]; echo $?)" "#262: gesetztes core.hooksPath → exit ≠ 0 (fail-closed, keine wirkungslose Installation)"
printf '%s' "$ih_out" | grep -qF 'core.hooksPath'
assert_true "$?" "#262: Abbruch nennt core.hooksPath als Ursache (pfadspezifisches Signal)"
[ -e "$WT/.git/hooks/commit-msg" ]
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: bei gesetztem core.hooksPath wird kein Hook geschrieben"
# Gegenprobe: dieselbe Repo-Anlage OHNE die Option installiert wie gewohnt (die Ablehnung
# hängt an der Option, nicht am Testrepo).
git -C "$WT" config --unset core.hooksPath
bash "$WT/scripts/install-hooks.sh" >/dev/null 2>&1
assert_exit 0 "$?" "#262: ohne core.hooksPath läuft dasselbe Repo durch (Gegenprobe)"
[ -x "$WT/.git/hooks/commit-msg" ]
assert_true "$?" "#262: Gegenprobe installiert den commit-msg-Hook"

# Worktree-Fall (ADR-042-Begründung): Hooks liegen im gemeinsamen git-Verzeichnis und
# gelten damit repo-weit – ein Lauf aus dem Worktree heraus installiert in den Hauptbaum.
WT=$(ih_repo worktreebase)
git -C "$WT" add -A >/dev/null 2>&1
git -C "$WT" commit -q -m "chore: init" >/dev/null 2>&1
git -C "$WT" worktree add -q -b feature/262-probe "$TMP_CM/worktreebase-wt" >/dev/null 2>&1
bash "$TMP_CM/worktreebase-wt/scripts/install-hooks.sh" >/dev/null 2>&1
assert_exit 0 "$?" "#262: install-hooks.sh läuft aus einem Worktree heraus durch"
[ -x "$WT/.git/hooks/commit-msg" ]
assert_true "$?" "#262: aus dem Worktree installierter Hook landet im gemeinsamen .git (gilt repo-weit)"

echo ""
echo "#262 commit-msg-Hook end-to-end (echtes 'git commit' im Wegwerf-Repo):"

# cm_e2e_repo <name> → Repo mit real installierten Hooks. Der pre-commit-Hook wird bewusst
# durch einen No-op ersetzt: nur der commit-msg-Pfad darf über Erfolg/Ablehnung entscheiden
# (pre-commit.sh ruft `pnpm lint` und ist im Wegwerf-Repo gar nicht vorhanden – sonst wäre
# der Test rot aus dem falschen Grund, Lesson nothra/tch-gastro-services#214).
cm_e2e_repo() {
  local wt
  wt=$(ih_repo "$1")
  git -C "$wt" add -A >/dev/null 2>&1
  git -C "$wt" commit -q -m "chore: init" >/dev/null 2>&1
  bash "$wt/scripts/install-hooks.sh" >/dev/null 2>&1
  # Fail-closed: ohne installierten Hook wären die folgenden Erfolgsfälle grün aus dem
  # falschen Grund (nichts würde prüfen). Kein assert_* hier – die Ausgabe dieser Funktion
  # wird per Kommandosubstitution gelesen.
  if [ ! -x "$wt/.git/hooks/commit-msg" ]; then
    echo "cm_e2e_repo: commit-msg-Hook wurde in '$wt' nicht installiert" >&2
    return 1
  fi
  printf '#!/usr/bin/env bash\nexit 0\n' > "$wt/.git/hooks/pre-commit"
  chmod +x "$wt/.git/hooks/pre-commit"
  printf '%s\n' "$wt"
}

WT=$(cm_e2e_repo e2e-regular)
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
git -C "$WT" commit -q -m "fix: foo" >/dev/null 2>&1
assert_exit 0 "$?" "#262 AK1: reguläre Message wird wie bisher committet"
[ "$(git -C "$WT" log --format=%s -1)" = "fix: foo" ]
assert_true "$?" "#262 AK1: Commit trägt die unveränderte Message"

for flag_case in "--help" "-h"; do
  WT=$(cm_e2e_repo "e2e-${flag_case//-/}")
  HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
  echo "x" > "$WT/x.txt"; git -C "$WT" add -A
  cm_out=$(git -C "$WT" commit -q -m "$flag_case" 2>&1); cm_rc=$?
  assert_true "$([ $cm_rc -ne 0 ]; echo $?)" "#262 AK2: 'git commit -m $flag_case' → exit ≠ 0"
  [ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
  assert_true "$?" "#262 AK2: bei '$flag_case' entsteht kein Commit"
  # Pfadspezifisches Signal: die Ablehnung stammt aus dem Flag-Guard, nicht von git selbst.
  printf '%s' "$cm_out" | grep -qF 'sieht aus wie ein CLI-Flag'
  assert_true "$?" "#262 AK2: Ablehnung von '$flag_case' stammt aus dem commit-msg-Guard"
done

# Editor-Pfad end-to-end (`git commit` ohne `-m`): der Editor stellt die Flag-Zeile vor das
# Template, dessen Kommentarzeilen Git erst NACH dem Hook entfernt. Ohne eigenes Verwerfen der
# Kommentarzeilen entstünde hier ein Commit mit der Message '--help'.
WT=$(cm_e2e_repo e2e-editor)
HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "--help" | cat - "$1" > "$1.neu"\nmv "$1.neu" "$1"\n' > "$WT/editor.sh"
chmod +x "$WT/editor.sh"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
cm_out=$(GIT_EDITOR="$WT/editor.sh" git -C "$WT" commit 2>&1); cm_rc=$?
assert_true "$([ $cm_rc -ne 0 ]; echo $?)" "#262 AK2: 'git commit' über den Editor mit --help → exit ≠ 0"
[ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
assert_true "$?" "#262 AK2: über den Editor-Pfad entsteht kein '--help'-Commit"
printf '%s' "$cm_out" | grep -qF 'sieht aus wie ein CLI-Flag'
assert_true "$?" "#262 AK2: Ablehnung auf dem Editor-Pfad stammt aus dem commit-msg-Guard"
# Gegenprobe: eine reguläre Message läuft über denselben Editor-Pfad durch.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "fix: ueber den editor" | cat - "$1" > "$1.neu"\nmv "$1.neu" "$1"\n' > "$WT/editor.sh"
GIT_EDITOR="$WT/editor.sh" git -C "$WT" commit >/dev/null 2>&1
assert_exit 0 "$?" "#262 AK1: reguläre Message über den Editor-Pfad wird committet (Gegenprobe)"
[ "$(git -C "$WT" log --format=%s -1)" = "fix: ueber den editor" ]
assert_true "$?" "#262 AK1: Editor-Commit trägt die unveränderte Message"

# Verbose-Pfad (`git commit -v`/`--verbose`): Git hängt den Diff unterhalb der Scissors-Zeile
# UNPRÄFIGIERT an – ohne den Abbruch an der Scissors-Zeile bliebe der Diff in der Message
# stehen und der Trim-Vergleich griffe nicht mehr (empirisch mit git 2.50 belegt).
WT=$(cm_e2e_repo e2e-verbose)
HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "--help" | cat - "$1" > "$1.neu"\nmv "$1.neu" "$1"\n' > "$WT/editor.sh"
chmod +x "$WT/editor.sh"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
cm_out=$(GIT_EDITOR="$WT/editor.sh" git -C "$WT" commit -v 2>&1); cm_rc=$?
assert_true "$([ $cm_rc -ne 0 ]; echo $?)" "#262: 'git commit -v' mit --help oberhalb des verbose-Diffs → exit ≠ 0"
[ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ]
assert_true "$?" "#262: über den verbose-Pfad entsteht kein '--help'-Commit"
printf '%s' "$cm_out" | grep -qF 'sieht aus wie ein CLI-Flag'
assert_true "$?" "#262: Ablehnung auf dem verbose-Pfad stammt aus dem commit-msg-Guard"

# --cleanup=scissors (ohne -v): die Scissors-Zeile ist selbst kommentar-präfigiert und damit
# schon vor dem Fix unkritisch – Gegenprobe, dass der neue Abbruch diesen Fall nicht bricht.
WT=$(cm_e2e_repo e2e-scissors)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "fix: mit scissors" | cat - "$1" > "$1.neu"\nmv "$1.neu" "$1"\n' > "$WT/editor.sh"
chmod +x "$WT/editor.sh"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
GIT_EDITOR="$WT/editor.sh" git -C "$WT" commit --cleanup=scissors >/dev/null 2>&1
assert_exit 0 "$?" "#262: reguläre Message mit --cleanup=scissors wird committet (Gegenprobe)"
[ "$(git -C "$WT" log --format=%s -1)" = "fix: mit scissors" ]
assert_true "$?" "#262: --cleanup=scissors-Commit trägt die unveränderte Message"

WT=$(cm_e2e_repo e2e-dashx)
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
git -C "$WT" commit -q -m "-x" >/dev/null 2>&1
assert_exit 0 "$?" "#262 AK3: '-x' als Message bleibt erlaubt (kein zu breites Matching)"
[ "$(git -C "$WT" log --format=%s -1)" = "-x" ]
assert_true "$?" "#262 AK3: Commit mit Message '-x' entsteht unverändert"

# Der Hook gilt repo-weit, auch auf Branches ohne das Prüfskript (ältere Feature-Branches,
# `git bisect`, vor dem Merge angelegte Worktrees). Dort darf er nicht JEDEN Commit mit
# „No such file or directory" blockieren → bewusste Fail-open-Ausnahme (ADR-042).
WT=$(cm_e2e_repo e2e-nocheck)
rm -f "$WT/scripts/checks/commit-msg-check.sh"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A
# LC_ALL=C: die Abwesenheits-Prüfung unten sucht die englische git/bash-Meldung – unter einer
# deutschen Locale hieße sie „Datei oder Verzeichnis nicht gefunden" und der Grep ginge ins Leere.
cm_out=$(LC_ALL=C git -C "$WT" commit -q -m "fix: branch ohne pruefskript" 2>&1); cm_rc=$?
assert_exit 0 "$cm_rc" "#262: fehlendes commit-msg-check.sh blockiert den Commit nicht (Fail-open-Ausnahme)"
printf '%s' "$cm_out" | grep -qF 'No such file or directory'
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: kein kryptischer 'No such file'-Fehler auf Branches ohne Prüfskript"
[ "$(git -C "$WT" log --format=%s -1)" = "fix: branch ohne pruefskript" ]
assert_true "$?" "#262: Commit auf einem Branch ohne Prüfskript entsteht regulär"
# Diskriminierung: liegt das Skript wieder vor, greift der Guard unverändert (die Ausnahme
# deckt ausschließlich den Nicht-vorhanden-Fall ab, nicht den Guard selbst).
cp "$CMCHECK" "$WT/scripts/checks/"
echo "y" > "$WT/y.txt"; git -C "$WT" add -A
git -C "$WT" commit -q -m "--help" >/dev/null 2>&1
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: mit wieder vorhandenem Prüfskript lehnt der Hook '--help' weiterhin ab"

rm -rf "$TMP_CM"

echo ""
echo "#262 init-factory.sh delegiert die Hook-Installation (ADR-042):"

# AK8 strukturell: init-factory.sh ist interaktiv (read-Prompts) und nutzt `sed -i ''`
# (BSD-Syntax) – ein vollständiger, echter Bootstrap-Lauf wäre in CI (GNU sed) nicht portabel.
# Geprüft wird deshalb (a) die Delegation an die kanonische Quelle – auf den KONKRETEN Aufruf
# gepinnt, nicht auf den Pfad als Fließtext (der steht auch im Kommentar darüber) – und (b)
# unten mit gestubbtem Installer das reale Aufruf-/Fehlerverhalten.
INIT_FACTORY="$SCRIPTS_DIR/init-factory.sh"
grep -qF 'bash "$FACTORY_DIR/scripts/install-hooks.sh"' "$INIT_FACTORY"
assert_true "$?" "#262 AK8: init-factory.sh ruft scripts/install-hooks.sh auf (konkreter Aufruf, nicht nur Erwähnung)"
# Fail-closed vor dem Negativ-Grep: wäre die Datei unlesbar oder verschoben, lieferte `grep`
# ebenfalls ≠ 0 und die Abwesenheits-Assertion wäre grün aus dem falschen Grund (Lesson nothra/tch-gastro-services#214).
[ -r "$INIT_FACTORY" ]
assert_true "$?" "#262 AK8: init-factory.sh ist lesbar (Vorbedingung des Abwesenheits-Checks)"
grep -qF '.git/hooks' "$INIT_FACTORY"
assert_true "$([ $? -ne 0 ]; echo $?)" "#262 AK8: init-factory.sh schreibt keine Hooks mehr selbst (keine .git/hooks-Referenz)"

# AK8 verhaltensbasiert: echter Lauf mit gestubbtem Installer. Der Stub belegt, dass der
# Aufruf wirklich stattfindet (nicht nur im Quelltext steht), und deckt zugleich ab, dass ein
# fail-closed Abbruch des Installers den Bootstrap nicht als Erfolg beenden lässt.
IF_TMP="$(mktemp -d)"

# if_fixture <name> <exit-code-des-stubs> → Mini-Projektbaum mit kopiertem init-factory.sh.
if_fixture() {
  local root="$IF_TMP/$1"
  mkdir -p "$root/scripts/checks" "$root/docs/factory" "$root/bin"
  cp "$INIT_FACTORY" "$root/scripts/"
  printf '#!/usr/bin/env bash\necho "STUB-INSTALLER LIEF"\nexit %s\n' "$2" > "$root/scripts/install-hooks.sh"
  printf '%s\n' 'Name: {{PROJECT_NAME}}' > "$root/docs/factory/PROJECT-CONTEXT.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/checks/dummy.sh"
  # `sed -i ''` in init-factory.sh ist BSD-Syntax und scheitert unter GNU-sed (CI). Das
  # PROJECT-CONTEXT-Templating ist für diesen Test irrelevant → No-op-`sed` im PATH, damit
  # der Lauf überall bis zum Hook-Schritt kommt.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/sed"
  chmod +x "$root/bin/sed" "$root/scripts/install-hooks.sh"
  printf '%s\n' "$root"
}

# run_init_factory <root> → beantwortet die acht read-Prompts und gibt stdout+stderr aus.
run_init_factory() {
  printf '%s\n' proj "eine beschreibung" webapp team "" typescript next postgres |
    PATH="$1/bin:$PATH" bash "$1/scripts/init-factory.sh" 2>&1
}

IF_ROOT=$(if_fixture initfail 2)
if_out=$(run_init_factory "$IF_ROOT"); if_rc=$?
printf '%s' "$if_out" | grep -qF 'STUB-INSTALLER LIEF'
assert_true "$?" "#262 AK8: init-factory.sh führt scripts/install-hooks.sh wirklich aus (Stub lief)"
assert_true "$([ $if_rc -ne 0 ]; echo $?)" "#262: fail-closed Abbruch des Installers → init-factory.sh endet mit exit ≠ 0"
printf '%s' "$if_out" | grep -qF 'Bootstrap unvollständig'
assert_true "$?" "#262: Abschluss nennt den fehlgeschlagenen Hook-Schritt (pfadspezifisches Signal)"
printf '%s' "$if_out" | grep -qF 'erfolgreich initialisiert'
assert_true "$([ $? -ne 0 ]; echo $?)" "#262: kein Erfolgs-Banner, wenn keine Hooks installiert wurden"

# Gegenprobe: mit erfolgreichem Installer läuft derselbe Bootstrap wie bisher durch.
IF_ROOT=$(if_fixture initok 0)
if_out=$(run_init_factory "$IF_ROOT"); if_rc=$?
assert_exit 0 "$if_rc" "#262: erfolgreicher Installer → init-factory.sh endet mit exit 0 (Gegenprobe)"
printf '%s' "$if_out" | grep -qF 'erfolgreich initialisiert'
assert_true "$?" "#262: Erfolgs-Banner erscheint bei erfolgreicher Hook-Installation"

rm -rf "$IF_TMP"

echo ""
echo "#265 hooks-installed-check.sh (fail-closed Präsenz+Ausführbarkeit, ADR-042):"

HI_CHECK="$CHECKS_DIR/hooks-installed-check.sh"
assert_true "$([[ -f "$HI_CHECK" ]]; echo $?)" "#265: hooks-installed-check.sh vorhanden"
assert_true "$([[ -x "$HI_CHECK" ]]; echo $?)" "#265: hooks-installed-check.sh ausführbar"

TMP_HI="$(mktemp -d)"

# hi_repo <name> → Wegwerf-git-Repo (nur git init, kein Factory-Setup nötig – der Check
# selbst hat keine Laufzeit-Abhängigkeiten außer git). Lokale Identität setzen (wie
# ih_repo() im nothra/tch-gastro-services#262-Abschnitt) – ohne globale Git-Identität in der Ausführungsumgebung
# schlägt der Worktree-Test-Commit sonst mit "empty ident name" fehl (Review-Finding nothra/tch-gastro-services#265).
hi_repo() {
  local wt="$TMP_HI/$1"
  git init -q -b main "$wt" >/dev/null 2>&1
  git -C "$wt" config user.email t@t
  git -C "$wt" config user.name t
  printf '%s\n' "$wt"
}

# install_all_hooks <repo-root> → legt alle drei Factory-Hooks ausführbar an.
install_all_hooks() {
  local wt="$1"
  mkdir -p "$wt/.git/hooks"
  for h in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$wt/.git/hooks/$h"
    chmod +x "$wt/.git/hooks/$h"
  done
}

# GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM=/dev/null isolieren gegen ambientes core.hooksPath
# (z. B. `git config --global core.hooksPath ~/.githooks`, verbreitetes husky-/dotfiles-
# Muster) – ohne Isolation liest `git config --get` in hooks-installed-check.sh auch
# global/system mit, und die Erfolgs-Assertions würden auf einer Entwickler-Maschine mit
# gesetztem globalem core.hooksPath fälschlich rot, obwohl der Code korrekt ist
# (Review-Finding nothra/tch-gastro-services#268 Runde 3; dieselbe Klasse wie nothra/tch-gastro-services#262/#264: ambiente Umgebung leckt in
# die Fixture).
rc_hooks() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null FACTORY_DIR="$1" bash "$HI_CHECK" 2>&1; }

# 1. Alle drei Hooks vorhanden + ausführbar → Erfolg, Push nicht blockiert.
WT=$(hi_repo allok)
install_all_hooks "$WT"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 0 "$rc" "#265 AK1: alle drei Hooks vorhanden+ausführbar → exit 0"

# 2. commit-msg fehlt (nie installiert) → fail-closed, nennt Hook-Namen + Remediation.
WT=$(hi_repo missing-commitmsg)
install_all_hooks "$WT"
rm -f "$WT/.git/hooks/commit-msg"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 1 "$rc" "#265 AK2: fehlender commit-msg-Hook → exit 1 (Push blockiert)"
printf '%s' "$out" | grep -qF 'commit-msg'
assert_true "$?" "#265 AK2: Fehlermeldung nennt den fehlenden Hook (commit-msg)"
printf '%s' "$out" | grep -qF 'bash scripts/install-hooks.sh'
assert_true "$?" "#265 AK2: Fehlermeldung nennt den Remediation-Befehl"

# 3. Hook existiert als Datei, ist aber nicht ausführbar → wie fehlend behandelt.
WT=$(hi_repo not-executable)
install_all_hooks "$WT"
chmod -x "$WT/.git/hooks/pre-push"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 1 "$rc" "#265 AK3: nicht ausführbarer pre-push-Hook → exit 1 (reine Existenz reicht nicht)"
printf '%s' "$out" | grep -qF 'pre-push'
assert_true "$?" "#265 AK3: Fehlermeldung nennt den nicht ausführbaren Hook (pre-push)"

# 3b. Boundary: Hook-Name existiert als VERZEICHNIS statt Datei (keine reguläre Datei).
# Ein Verzeichnis ist per `[ -x ]` fast immer "ausführbar" (durchsuchbar, typ. 755) – ohne
# den `-f`-Test würde ein Verzeichnis fälschlich als installierter Hook durchgehen.
WT=$(hi_repo dir-not-file)
install_all_hooks "$WT"
rm -f "$WT/.git/hooks/pre-commit"
mkdir -p "$WT/.git/hooks/pre-commit"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 1 "$rc" "#265 Boundary: Hook-Name als Verzeichnis (statt Datei) → exit 1 (keine reguläre Datei)"
printf '%s' "$out" | grep -qF 'pre-commit'
assert_true "$?" "#265 Boundary: Fehlermeldung nennt pre-commit, obwohl das Verzeichnis 'ausführbar' ist"

# 4. Läuft aus einem Worktree heraus – Hooks liegen im GEMEINSAMEN .git (nicht worktree-lokal).
WT=$(hi_repo worktreebase)
install_all_hooks "$WT"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A >/dev/null 2>&1
git -C "$WT" commit -q -m "chore: init" >/dev/null 2>&1
git -C "$WT" worktree add -q -b improvement/265-probe "$TMP_HI/worktreebase-wt" >/dev/null 2>&1
out=$(rc_hooks "$TMP_HI/worktreebase-wt"); rc=$?
assert_exit 0 "$rc" "#265 AK4: Check aus einem Worktree heraus findet die Hooks im gemeinsamen .git"

# 5. Mehrere Hooks fehlen gleichzeitig → alle betroffenen Namen werden genannt.
WT=$(hi_repo missing-multi)
install_all_hooks "$WT"
rm -f "$WT/.git/hooks/pre-commit" "$WT/.git/hooks/commit-msg"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 1 "$rc" "#265 AK5: mehrere fehlende Hooks → exit 1"
printf '%s' "$out" | grep -qF 'pre-commit'
assert_true "$?" "#265 AK5: Fehlermeldung nennt pre-commit"
printf '%s' "$out" | grep -qF 'commit-msg'
assert_true "$?" "#265 AK5: Fehlermeldung nennt commit-msg"
printf '%s' "$out" | grep -qF 'pre-push'
assert_true "$([ $? -ne 0 ]; echo $?)" "#265 AK5: pre-push (vorhanden) wird NICHT als fehlend genannt (diskriminierend)"

# 6. .git/hooks-Verzeichnis existiert noch gar nicht (Retrofit nie durchgeführt).
WT=$(hi_repo no-hooks-dir)
rm -rf "$WT/.git/hooks"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 1 "$rc" "#265: fehlendes .git/hooks-Verzeichnis → exit 1, alle drei Hooks gelten als fehlend"
for h in pre-commit pre-push commit-msg; do
  printf '%s' "$out" | grep -qF "$h"
  assert_true "$?" "#265: fehlendes .git/hooks-Verzeichnis → Meldung nennt $h"
done

# 7. Kein Git-Repository → fail-closed (kein stiller Erfolg).
NOGIT="$TMP_HI/nogit"
mkdir -p "$NOGIT"
out=$(FACTORY_DIR="$NOGIT" bash "$HI_CHECK" 2>&1); rc=$?
assert_true "$([ $rc -ne 0 ]; echo $?)" "#265: kein git-Repository → exit ≠ 0 (fail-closed)"

rm -rf "$TMP_HI"

# Struktur: der Check ist im Push-Gate (pre-push.sh) verdrahtet.
grep -q 'hooks-installed-check.sh' "$CHECKS_DIR/pre-push.sh"
assert_true "$?" "#265: pre-push.sh verdrahtet den Git-Hooks-Installiert-Check"

echo ""
echo "#268 hooks-installed-check.sh core.hooksPath (Fail-closed, ADR-042):"

TMP_HI="$(mktemp -d)"

# 1. core.hooksPath gesetzt, Reste im Standardpfad noch vorhanden+ausführbar (Kernszenario
# des Issues) → Check darf trotzdem nicht grün melden, Git ruft diese Dateien nie auf.
WT=$(hi_repo hookspath-with-residue)
install_all_hooks "$WT"
git -C "$WT" config core.hooksPath ".husky"
out=$(rc_hooks "$WT"); rc=$?
assert_true "$([ "$rc" -ne 0 ]; echo $?)" "#268 AK2: core.hooksPath gesetzt + ausführbare Reste im Standardpfad → exit ≠ 0 (statt fälschlich exit 0)"
printf '%s' "$out" | grep -qF 'core.hooksPath'
assert_true "$?" "#268 AK2: Fehlermeldung nennt core.hooksPath als Ursache"

# 2. core.hooksPath gesetzt, Hooks fehlen im Standardpfad vollständig → ebenfalls fail-closed
# (die core.hooksPath-Prüfung greift unabhängig vom Dateizustand). Ohne install_all_hooks
# würde bereits die bestehende Präsenzprüfung (spec-265) exit 1 liefern – erst das
# pfadspezifische Signal + die Abwesenheit der Präsenz-Meldung belegen, dass wirklich der
# neue core.hooksPath-Guard gegriffen hat (Review-Finding nothra/tch-gastro-services#268 Runde 1).
WT=$(hi_repo hookspath-no-residue)
git -C "$WT" config core.hooksPath ".husky"
out=$(rc_hooks "$WT"); rc=$?
assert_true "$([ "$rc" -ne 0 ]; echo $?)" "#268 AK3: core.hooksPath gesetzt + Hooks fehlen im Standardpfad → exit ≠ 0"
printf '%s' "$out" | grep -qF 'core.hooksPath'
assert_true "$?" "#268 AK3: Fehlermeldung nennt core.hooksPath (pfadspezifisches Signal statt Zufallstreffer der Präsenzprüfung)"
printf '%s' "$out" | grep -qF 'Fehlende oder nicht ausführbare Git-Hooks'
assert_true "$([ $? -ne 0 ]; echo $?)" "#268 AK3: die alte Präsenz-Fehlermeldung erscheint NICHT (Guard hat Vorrang, wird vorher erreicht)"

# 3. Fehlermeldung nennt Pfad, Scope/Herkunft und Remediation-Hinweis.
WT=$(hi_repo hookspath-message)
install_all_hooks "$WT"
git -C "$WT" config core.hooksPath ".husky"
out=$(rc_hooks "$WT")
printf '%s' "$out" | grep -qF '.husky'
assert_true "$?" "#268 AK4: Fehlermeldung nennt den konfigurierten Pfad (.husky)"
printf '%s' "$out" | grep -qF 'file:'
assert_true "$?" "#268 AK4: Fehlermeldung nennt die Herkunft/Scope (git config --show-origin)"
printf '%s' "$out" | grep -qF 'git config --unset core.hooksPath'
assert_true "$?" "#268 AK4: Fehlermeldung nennt den konkreten Remediation-Befehl (nicht nur tautologisch 'core.hooksPath')"

# 4. Läuft aus einem Worktree heraus – core.hooksPath liegt im gemeinsamen Git-Verzeichnis,
# der Check muss denselben effektiven Wert lesen wie install-hooks.sh (kein worktree-lokales
# Abweichen).
WT=$(hi_repo hookspath-worktree)
install_all_hooks "$WT"
git -C "$WT" config core.hooksPath ".husky"
echo "x" > "$WT/x.txt"; git -C "$WT" add -A >/dev/null 2>&1
git -C "$WT" commit -q -m "chore: init" >/dev/null 2>&1
git -C "$WT" worktree add -q -b improvement/268-probe "$TMP_HI/hookspath-worktree-wt" >/dev/null 2>&1
out=$(rc_hooks "$TMP_HI/hookspath-worktree-wt"); rc=$?
assert_true "$([ "$rc" -ne 0 ]; echo $?)" "#268 AK5: core.hooksPath aus einem Worktree heraus → derselbe effektive Wert, fail-closed"
# Pfadspezifisches Signal nötig: schlägt `git worktree add` fehl (z. B. Fixture-Fehler),
# existiert der Ziel-Worktree nicht und schon `cd "$ROOT"` scheitert im Skript – exit ≠ 0,
# ohne dass core.hooksPath je gelesen wurde. Erst der '.husky'-Treffer belegt, dass der
# Guard tatsächlich lief (Review-Finding nothra/tch-gastro-services#268 Runde 1).
printf '%s' "$out" | grep -qF '.husky'
assert_true "$?" "#268 AK5: Fehlermeldung nennt den aus dem gemeinsamen Git-Verzeichnis gelesenen Pfad (.husky) statt nur zufällig grün zu sein"

# 5. Leerer core.hooksPath-Wert verhält sich NICHT wie „nicht gesetzt" (empirisch mit
# git 2.50 verifiziert, siehe Skript-Header): Git löst den Hook-Pfad dann auf das
# Arbeitsverzeichnis auf und ruft $GIT_COMMON_DIR/hooks nicht mehr auf. Muss daher
# ebenfalls fail-closed sein – bewusste Abweichung vom ursprünglich angenommenen Vorbild
# install-hooks.sh (Korrektur ggü. Review-Finding nothra/tch-gastro-services#268 Runde 1, spec-268 „Offene Fragen").
WT=$(hi_repo hookspath-empty)
install_all_hooks "$WT"
git -C "$WT" config core.hooksPath ""
out=$(rc_hooks "$WT"); rc=$?
assert_true "$([ "$rc" -ne 0 ]; echo $?)" "#268: leerer core.hooksPath-Wert ist NICHT gleichbedeutend mit 'nicht gesetzt' → exit ≠ 0 (fail-closed)"
printf '%s' "$out" | grep -qF 'core.hooksPath'
assert_true "$?" "#268: Fehlermeldung nennt core.hooksPath auch im Leerstring-Fall"

# 6. Gegenprobe: core.hooksPath NICHT gesetzt, Hooks vorhanden+ausführbar → unverändertes
# Erfolgsverhalten (spec-265 AK1 bleibt bestehen).
WT=$(hi_repo hookspath-unset)
install_all_hooks "$WT"
out=$(rc_hooks "$WT"); rc=$?
assert_exit 0 "$rc" "#268: core.hooksPath nicht gesetzt → unverändert exit 0 (Gegenprobe, spec-265 AK1)"

rm -rf "$TMP_HI"

echo ""
echo "#265 CI-Absicherung: factory-self-test-Job installiert Hooks vor der Self-Test-Suite:"

# CI-Regression (beobachtet in PR zu nothra/tch-gastro-services#265): der nothra/tch-gastro-services#149-Test ruft pre-push.sh ECHT gegen das
# reale FACTORY_DIR auf (kein Fixture-Repo, siehe run_prepush_149 oben) – in einem frischen
# CI-Checkout sind dort NIE Hooks installiert (git hooks laufen in CI ohnehin nie), also
# schlägt Check 5 (hooks-installed-check.sh) dort IMMER fehl und reißt die Format-Gate-Tests
# mit sich (erwartet exit 0, tatsächlich exit 1). Fix: der CI-Job installiert die Hooks vor
# der Self-Test-Suite, genau wie es jeder frische Clone lokal tun müsste (README/CLAUDE.md) –
# damit erfüllt auch der CI-Checkout die Invariante, die Check 5 selbst einfordert.
ci_selftest_block="$(ci_job_block factory-self-test "$CI_FILE")"
assert_true "$([[ -n "$ci_selftest_block" ]]; echo $?)" "#265: factory-self-test-Job-Block ist extrahierbar"

printf '%s' "$ci_selftest_block" | grep -qF 'bash scripts/install-hooks.sh'
assert_true "$?" "#265: factory-self-test-Job installiert die Git-Hooks (bash scripts/install-hooks.sh)"

# Anker auf den echten COMMAND ('run:'-Zeile), nicht auf jede Erwähnung von 'run-tests.sh' –
# eine Prosa-Erwähnung (z. B. in einem Kommentar oberhalb) wäre keine Reihenfolge-Aussage
# über den tatsächlichen Schritt-Aufruf (Lesson nothra/tch-gastro-services#114 "Kommando ≠ Prosa-Erwähnung").
ci_install_line="$(printf '%s\n' "$ci_selftest_block" | grep -n 'run: bash scripts/install-hooks.sh' | head -1 | cut -d: -f1)"
ci_selftest_line="$(printf '%s\n' "$ci_selftest_block" | grep -n 'run: bash scripts/checks/tests/run-tests.sh' | head -1 | cut -d: -f1)"
[ -n "$ci_install_line" ] && [ -n "$ci_selftest_line" ] && [ "$ci_install_line" -lt "$ci_selftest_line" ]
assert_true "$?" "#265: Hook-Installation steht VOR der Self-Test-Suite (Reihenfolge, sonst wirkungslos)"

echo ""
echo "#262 Doku nennt den kanonischen Installationsweg (Lesson #211/#176):"

# Ein neues Gate ist nur wirksam, wenn ein frischer Clone erfährt, dass es zu installieren ist –
# jede Stelle, die die lokale Gate-Landschaft beschreibt, muss den commit-msg-Hook kennen:
# CLAUDE.md + git-workflow.md (Agenten-Regeln), OPERATING.md (Betrieb), CONTRIBUTING.md
# (Einstieg für Menschen). Gesucht wird der Hook als Hook ('`commit-msg`-Hook') – 'commit-msg'
# allein wäre Teilstring von 'commit-msg-check.sh' und damit nicht diskriminierend.
CLAUDE_MD="$FACTORY_ROOT/docs/factory/FACTORY.md"
OPERATING_MD="$FACTORY_ROOT/docs/factory/OPERATING.md"
# (CONTRIBUTING.md und README.md gehören dem Projekt: ihre Prüfung steht in scripts/project/tests/run-tests.sh.)
for doc_file in "$CLAUDE_MD" "$GITWF" "$OPERATING_MD"; do
  [ -r "$doc_file" ]
  assert_true "$?" "#262: $(basename "$doc_file") ist lesbar (Vorbedingung der Doku-Checks)"
  grep -qF 'scripts/install-hooks.sh' "$doc_file"
  assert_true "$?" "#262: $(basename "$doc_file") nennt scripts/install-hooks.sh als Installationsweg"
  grep -qF '`commit-msg`-Hook' "$doc_file"
  assert_true "$?" "#262: $(basename "$doc_file") nennt den commit-msg-Hook als Hook"
done


echo ""
echo "#258 yq-Bereitstellung: Versions-Pin + Checksum-Verifikation:"

INSTALL_YQ="$FACTORY_ROOT/scripts/install-yq.sh"
[ -r "$INSTALL_YQ" ]
assert_true "$?" "#258: scripts/install-yq.sh vorhanden (Vorbedingung der folgenden Checks)"

# Lesbarkeit der Workflow-Dateien als eigene Vorbedingung: der AK1-Guard unten ist ein
# negierter grep über drei Dateien – fehlt eine (Umbenennung), liefert grep Exit 2 und das
# '!' macht daraus ein stilles PASS. Fail-closed heißt hier: Lesbarkeit vorher zusichern
# (Lesson nothra/tch-gastro-services#214 "Fail-closed bei unlesbarer Quelle").
[ -r "$CI_FILE" ] && [ -r "$POLL_YML" ]
assert_true "$?" "#258: factory-ci.yml und factory-poll.yml sind lesbar (Vorbedingung des AK1-Guards)"

# AK1: kein `releases/latest/download/...`-URL mehr – weder in den Workflows noch im Seam.
# Angeankert an der URL-Form, nicht an jeder Erwähnung von "releases/latest": der
# Skript-Header erklärt genau diese alte Form als WHY-Kommentar (Lesson nothra/tch-gastro-services#114).
! grep -q 'releases/latest/download' "$CI_FILE" "$POLL_YML" "$INSTALL_YQ"
assert_true "$?" "#258 AK1: keine releases/latest/download-URL mehr in factory-ci.yml / factory-poll.yml / install-yq.sh"

grep -qE '^YQ_VERSION="v[0-9]+\.[0-9]+\.[0-9]+"$' "$INSTALL_YQ"
assert_true "$?" "#258 AK1: install-yq.sh pinnt eine konkrete yq-Version (YQ_VERSION=\"vX.Y.Z\")"

# AK7 (aus Review-Runde 1): der Erwartungswert darf nicht ausschließlich aus demselben Kanal
# stammen wie das Artefakt. Ohne einen im Repo gepinnten Hash wäre die Zusage des
# Skript-Headers ("ein manipuliertes Release-Asset wird erkannt") unwahr – wer das Binary
# ersetzen kann, ersetzt die daneben liegende checksums-Datei mit.
grep -qE '^YQ_SHA256="[0-9a-f]{64}"$' "$INSTALL_YQ"
assert_true "$?" "#258 AK7: install-yq.sh pinnt den erwarteten SHA-256 im Repo (YQ_SHA256, 64 Hex)"

# …und der Pin ist am PRODUKTIONSAUFRUF verdrahtet. Der Check darüber belegt nur, dass die
# Konstante existiert und formal ein Hash ist; die AK7-Verhaltenstests unten fahren `--verify`
# mit einem selbst mitgegebenen Fixture-Pin und berühren die Verdrahtung nicht. Ein Refactor,
# der als vierten Parameter den aus `checksums` GELESENEN Wert übergibt, macht den
# Pin-Vergleich trivial wahr (published = pinned) – und bliebe ohne diesen Guard lautlos:
# Self-Test grün UND CI grün, weil ein ehrlicher Download zu seinem eigenen Hash passt
# (Lessons nothra/tch-gastro-services#212/#214: Kopplungs-Guard am echten Aufruf, nicht nur Existenz-Grep).
# Anker ist die Aufruf-Zeile am Spaltenanfang, nicht eine Prosa-Erwähnung (Lesson nothra/tch-gastro-services#114).
yq_prod_verify_call="$(grep -n '^verify_sha256 "' "$INSTALL_YQ" | head -1 | cut -d: -f2-)"
printf '%s' "$yq_prod_verify_call" | grep -qE '"\$YQ_SHA256"$'
assert_true "$?" "#258 AK7: der Produktionsaufruf von verify_sha256 übergibt \$YQ_SHA256 als letztes Argument (Pin ist verdrahtet, nicht nur vorhanden)"

# Die Download-URL muss aus $YQ_VERSION gebildet werden – sonst behauptet die Konstante eine
# Version, während ein hartkodiertes Tag in der URL eine andere lädt (beide Guards oben würden
# das passieren lassen; in CI fiele es erst über die Pin-Abweichung auf).
grep -qF 'releases/download/$YQ_VERSION' "$INSTALL_YQ"
assert_true "$?" "#258 AK1: die Download-URL wird aus \$YQ_VERSION gebildet (kein zweites, hartkodiertes Tag)"

# AK4: alle drei betroffenen Jobs rufen denselben Seam auf – und keiner hat noch einen
# eigenen wget+chmod-Block. Job-Block isoliert extrahieren (ci_job_block, Lesson nothra/tch-gastro-services#255).
#
# Der Negativ-Anker prüft auf 'wget|curl' im Block, NICHT auf die alte Zwei-Zeilen-Form
# 'wget.*yq_linux_amd64' (Download-Kommando und URL standen im entfernten Block auf
# getrennten Zeilen – dieses Fragment konnte nie feuern, grep -E ist zeilenweise) und NICHT
# auf 'chmod \+x /usr/local/bin/yq' allein (ein wiedereingefügter Block mit `chmod 0755`
# statt `chmod +x` hätte diese Alternative unbemerkt umgangen). Ein Job, der den Seam
# aufruft, enthält weder 'wget' noch 'curl' im eigenen Block – ein wiedereingefügter
# Download+chmod-Block, gleich welcher chmod-Schreibweise, enthält mindestens eines von
# beiden (Review-Runde-3-Finding, Mutationsbeleg in der Task-Datei).
for yq_job_spec in "config-validation|$CI_FILE" "factory-self-test|$CI_FILE" "factory-poll|$POLL_YML"; do
  IFS='|' read -r yq_job yq_job_file <<< "$yq_job_spec"
  yq_job_block="$(ci_job_block "$yq_job" "$yq_job_file")"
  assert_true "$([[ -n "$yq_job_block" ]]; echo $?)" "#258 AK4: Job-Block '$yq_job' ist extrahierbar"

  printf '%s' "$yq_job_block" | grep -qF 'bash scripts/install-yq.sh'
  assert_true "$?" "#258 AK4: Job '$yq_job' ruft 'bash scripts/install-yq.sh' auf"

  ! printf '%s' "$yq_job_block" | grep -qE 'wget|curl'
  assert_true "$?" "#258 AK4: Job '$yq_job' hat keinen eigenen wget/curl-Download-Block mehr"
done

# Repo-weiter Präsenz-Guard zusätzlich zur Job-Schleife oben: die Schleife kennt nur die drei
# heute betroffenen Jobs – ein künftiger vierter Job mit einem wiedereingefügten
# Download+chmod-Block (auch mit gepinnter URL, CLAUDE.md §Guardrails) fiele ihr nicht auf.
# Repo-weit trägt genau EINE Stelle die Download-URL: scripts/install-yq.sh selbst (verifiziert
# per grep). Taucht dieselbe URL-Form in .github/ auf, hat ein Workflow-Job sie inline kopiert.
! grep -rq 'mikefarah/yq/releases' "$FACTORY_ROOT/.github/"
assert_true "$?" "#258 AK4: keine .github/-Workflow-Datei enthält die yq-Download-URL inline (Seam-Aufruf statt Kopie)"

# Beide umgebauten Workflow-Dateien müssen valides YAML bleiben (nur wo yq da ist, ADR-009).
if [ "$HAS_YQ" = 1 ]; then
  yq '.' "$CI_FILE" >/dev/null 2>&1 && yq '.' "$POLL_YML" >/dev/null 2>&1
  assert_true "$?" "#258: factory-ci.yml und factory-poll.yml bleiben valides YAML (yq-Parse)"
else
  skip_yq "#258: factory-ci.yml / factory-poll.yml bleiben valides YAML"
fi

# AK3 (Reihenfolge im Download-Pfad): das Ausführbar-Bit darf erst NACH der Verifikation
# fallen. Der Fixture-Test unten belegt nur den --verify-Zweig (dort gibt es kein chmod);
# die Reihenfolge im nicht netzwerkfrei testbaren Download-Pfad braucht diesen Anker.
# Angeankert an den echten Aufruf-Zeilen (Spaltenanfang), nicht an einer Prosa-Erwähnung
# im Kommentar (Lesson nothra/tch-gastro-services#114 "Kommando ≠ Prosa-Erwähnung").
yq_verify_line="$(grep -n '^verify_sha256 "' "$INSTALL_YQ" | head -1 | cut -d: -f1)"
yq_chmod_line="$(grep -n '^chmod 0755 "' "$INSTALL_YQ" | head -1 | cut -d: -f1)"
[ -n "$yq_verify_line" ] && [ -n "$yq_chmod_line" ] && [ "$yq_verify_line" -lt "$yq_chmod_line" ]
assert_true "$?" "#258 AK3: verify_sha256-Aufruf steht VOR 'chmod 0755' (sonst wäre die Verifikation wirkungslos)"

# Der Plattform-Guard muss ebenfalls VOR dem ersten Download stehen – ein Guard nach dem
# Laden würde das Herunterladen nicht mehr verhindern (gleicher Anker-Grundsatz, Lesson nothra/tch-gastro-services#114).
yq_guard_line="$(grep -n '^require_linux_amd64$' "$INSTALL_YQ" | head -1 | cut -d: -f1)"
yq_fetch_line="$(grep -n '^fetch "' "$INSTALL_YQ" | head -1 | cut -d: -f1)"
[ -n "$yq_guard_line" ] && [ -n "$yq_fetch_line" ] && [ "$yq_guard_line" -lt "$yq_fetch_line" ]
assert_true "$?" "#258: require_linux_amd64 steht VOR dem ersten Download (fetch)"

# ── Verifikationslogik gegen lokale Fixtures (AK2/AK3/AK5/AK6/AK7, netzwerkfrei) ──
# Fixture-Binary ist bewusst LEER: SHA-256 der leeren Eingabe ist ein öffentlich bekannter
# Testvektor, damit der Erwartungswert unten ein Literal bleibt (testing-standards: kein
# Soll-Wert, der aus dem Objekt-under-Test abgeleitet wird) – ohne Hash-Werkzeug beim
# Testschreiben. Schlägt der Positiv-Fall fehl, ist entweder die Hash-Berechnung oder die
# Spaltenauswahl im Seam defekt.
YQ_EMPTY_SHA256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# yq_fixture <verzeichnis> [sha256-position] – legt eine INTAKTE Fixture-Familie im echten
# Release-Format an: `checksums_hashes_order` (ein Algorithmus-Name pro Zeile) + `checksums`
# (Feld 1 = Dateiname, danach die Hashes in genau dieser Reihenfolge).
# <sha256-position> ist die Order-Zeile, in der `SHA-256` steht (Default 3 = Feld 4). Der
# Parameter existiert, weil yq die Reihenfolge pro Release rotiert: mit nur EINER getesteten
# Position wäre eine hartkodierte Spaltennummer nicht von der korrekten Rechnung
# `$((algo_line + 1))` zu unterscheiden (Diskriminierungs-Kontrolle, Lesson nothra/tch-gastro-services#172).
# Die Nachbarzeilen `yq_linux_386` und `yq_linux_amd64.tar.gz` tragen in der SHA-256-Spalte
# absichtlich falsche Werte (Kontrolle gegen Zeilenauswahl per Präfix/erstem Treffer statt
# exaktem Dateinamen-Vergleich).
# hex64 <zeichen> – 64-stelliger Hex-Füllwert aus einem Zeichen (Platzhalter-Hash in Fixtures).
# Nur hier gebraucht (yq_fixture + zwei Fehlerszenarien unten) – deshalb lokal bei den
# nothra/tch-gastro-services#258-Fixtures definiert statt bei den generischen Helfern am Dateikopf (Review-Runde-2-Nitpick;
# ci_job_block bleibt oben, weil es drei Nutzer über die Datei verteilt hat).
hex64() {
  local i out=""
  for ((i = 0; i < 64; i++)); do out+="$1"; done
  printf '%s' "$out"
}

yq_fixture() {
  local dir="$1" sha256_pos="${2:-3}"
  local -a fillers=(BLAKE2B-512 SHA-384 SHA-512 MD5)
  local -a algos=() row_target=() row_decoy=()
  local pos filler_idx=0
  for ((pos = 1; pos <= 4; pos++)); do
    if [ "$pos" -eq "$sha256_pos" ]; then
      algos+=("SHA-256")
      row_target+=("$YQ_EMPTY_SHA256")
      row_decoy+=("$(hex64 d)")
    else
      algos+=("${fillers[$filler_idx]}")
      filler_idx=$((filler_idx + 1))
      row_target+=("$(hex64 a)")
      row_decoy+=("$(hex64 a)")
    fi
  done
  mkdir -p "$dir"
  : > "$dir/yq_linux_amd64"
  printf '%s\n' "${algos[@]}" > "$dir/checksums_hashes_order"
  {
    printf 'yq_linux_386 %s\n' "${row_decoy[*]}"
    printf 'yq_linux_amd64.tar.gz %s\n' "${row_decoy[*]}"
    printf 'yq_linux_amd64 %s\n' "${row_target[*]}"
  } > "$dir/checksums"
}

# run_verify <verzeichnis> [gepinnter-hash] – ruft den netzwerkfreien --verify-Zweig auf.
# Der Pin ist ein Parameter (kein globaler Zugriff im Seam), damit der Repo-Pin des
# Produktionspfads und der Fixture-Pin des Tests dieselbe Codebahn nehmen.
# Netzwerk-Werkzeuge sind per PATH-Shadowing durch ein immer fehlschlagendes Stub ersetzt:
# würde der Zweig doch etwas laden, sagt der Stub das laut. "Ohne Netzwerkzugriff" (AK5) ist
# damit deterministisch belegt statt behauptet (Idiom analog dem gh-Shadowing weiter oben);
# geshadowed wird nur wget/curl – awk/grep/sha256sum bleiben erreichbar.
run_verify() {
  local dir="$1" pinned="${2:-$YQ_EMPTY_SHA256}"
  PATH="$YQ_NONETBIN:$PATH" bash "$INSTALL_YQ" --verify \
    "$dir/yq_linux_amd64" "$dir/checksums" "$dir/checksums_hashes_order" "$pinned" 2>&1
}

YQTMP="$(mktemp -d)"

YQ_NONETBIN="$YQTMP/nonetbin"
mkdir -p "$YQ_NONETBIN"
for yq_stub in wget curl; do
  printf '#!/bin/sh\necho "NETZWERK-STUB: $0 wurde aufgerufen" >&2\nexit 99\n' > "$YQ_NONETBIN/$yq_stub"
  chmod +x "$YQ_NONETBIN/$yq_stub"
done

# AK5 (Positiv): passender Hash → Erfolg, ohne Netzwerk, ohne Ausführbar-Bit.
yq_fixture "$YQTMP/ok"
yq_ok_out="$(run_verify "$YQTMP/ok")"; yq_rc=$?
assert_exit 0 "$yq_rc" "#258 AK5: --verify gegen Fixture mit korrektem Hash → exit 0 (ohne Netzwerkzugriff)"
printf '%s' "$yq_ok_out" | grep -qF 'verifiziert'
assert_true "$?" "#258 AK5: Erfolgsfall meldet die Verifikation explizit"
! printf '%s' "$yq_ok_out" | grep -qF 'NETZWERK-STUB'
assert_true "$?" "#258 AK5: --verify ruft weder wget noch curl auf (Netzwerkfreiheit belegt, nicht behauptet)"
[ ! -x "$YQTMP/ok/yq_linux_amd64" ]
assert_true "$?" "#258 AK3: --verify setzt selbst im Erfolgsfall kein Ausführbar-Bit (Installation ist ein eigener Schritt)"

# Spaltenherleitung mit einer ZWEITEN Order-Position: SHA-256 auf Zeile 1 (= Feld 2). Eine
# hartkodierte Spaltennummer fällt erst durch diesen Gegenfall auf, weil die Default-Fixture
# SHA-256 fix auf Zeile 3 legt – und genau diese Reihenfolge rotiert yq pro Release.
yq_fixture "$YQTMP/algo-first" 1
yq_first_out="$(run_verify "$YQTMP/algo-first")"; yq_rc=$?
assert_exit 0 "$yq_rc" "#258 AK2: SHA-256 auf Order-Zeile 1 (= Feld 2) wird korrekt hergeleitet"
printf '%s' "$yq_first_out" | grep -qF 'verifiziert'
assert_true "$?" "#258 AK2: rotierte Spaltenordnung meldet Erfolg (keine feste Spaltennummer im Seam)"

# AK6 (Negativ, eigener Testfall): genau EIN Defekt – die Binary ist korrupt/manipuliert,
# `checksums` und Pin bleiben intakt. Damit kommt der Fehlschlag ausschließlich aus dem
# Berechnung-gegen-Pin-Vergleich und die Meldung ist pfadspezifisch prüfbar (Lesson nothra/tch-gastro-services#214).
yq_fixture "$YQTMP/mismatch"
printf 'manipulierte binary' > "$YQTMP/mismatch/yq_linux_amd64"
yq_bad_out="$(run_verify "$YQTMP/mismatch")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258 AK6: --verify gegen manipulierte Binary → exit ≠ 0 (fail-closed)"
printf '%s' "$yq_bad_out" | grep -qF 'Checksum-Mismatch'
assert_true "$?" "#258 AK6: Mismatch-Meldung benennt den Checksum-Mismatch"
[ ! -x "$YQTMP/mismatch/yq_linux_amd64" ]
assert_true "$?" "#258 AK3: Mismatch lässt die Binary nicht-ausführbar (kein chmod im Fehlerfall)"

# AK7 (Negativ): der veröffentlichte Wert weicht vom Repo-Pin ab – genau das Szenario
# "Release-Asset unter demselben Tag ersetzt", das eine Prüfung nur gegen die mitgeladene
# checksums-Datei NICHT sehen könnte. Nur dieser eine Defekt ist gesetzt (Binary und
# Order-Datei bleiben intakt), der Pfad ist also isoliert und trägt eine eigene Meldung.
yq_fixture "$YQTMP/pin-drift"
yq_pin_out="$(run_verify "$YQTMP/pin-drift" "$(hex64 e)")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258 AK7: veröffentlichter Hash ≠ Repo-Pin → exit ≠ 0 (fail-closed)"
printf '%s' "$yq_pin_out" | grep -qF 'Pin-Abweichung'
assert_true "$?" "#258 AK7: Meldung benennt die Abweichung vom gepinnten Hash (nicht als Checksum-Mismatch getarnt)"

# Fehlerszenario: kein checksums-Eintrag für yq_linux_amd64 (Format-Drift eines Releases).
yq_fixture "$YQTMP/no-entry"
grep -v '^yq_linux_amd64 ' "$YQTMP/no-entry/checksums" > "$YQTMP/no-entry/checksums.new"
mv "$YQTMP/no-entry/checksums.new" "$YQTMP/no-entry/checksums"
yq_noentry_out="$(run_verify "$YQTMP/no-entry")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: fehlender checksums-Eintrag → exit ≠ 0 (kein leiser Erfolg)"
printf '%s' "$yq_noentry_out" | grep -qF 'keinen Eintrag'
assert_true "$?" "#258: Meldung benennt den fehlenden checksums-Eintrag"

# Fehlerszenario: keine SHA-256-Zeile in checksums_hashes_order (rotierende Spaltenordnung).
# Anker ist das pfadspezifische Fragment, NICHT der bloße Algorithmusname "SHA-256": der steht
# auch in der generischen Format-Drift-Meldung und in der Erfolgsmeldung – ein Test darauf
# könnte nicht zwischen "eigener Guard greift" und "irgendein Fallback greift" unterscheiden
# (Lesson nothra/tch-gastro-services#214, Review-Runde-1-Finding).
yq_fixture "$YQTMP/no-algo"
printf 'BLAKE2B-512\nSHA-384\nSHA-512\n' > "$YQTMP/no-algo/checksums_hashes_order"
yq_noalgo_out="$(run_verify "$YQTMP/no-algo")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: fehlende SHA-256-Zeile in checksums_hashes_order → exit ≠ 0"
printf '%s' "$yq_noalgo_out" | grep -qF "keine 'SHA-256'-Zeile"
assert_true "$?" "#258: Meldung benennt genau die fehlende SHA-256-Zeile (pfadspezifischer Anker)"

# Fehlerszenario: Zielzeile vorhanden, aber die SHA-256-Spalte fehlt (verkürzte Zeile) –
# ein leerer Erwartungswert darf nicht als „verifiziert" durchgehen.
yq_fixture "$YQTMP/short-row"
grep -v '^yq_linux_amd64 ' "$YQTMP/short-row/checksums" > "$YQTMP/short-row/checksums.new"
printf 'yq_linux_amd64 %s\n' "$(hex64 a)" >> "$YQTMP/short-row/checksums.new"
mv "$YQTMP/short-row/checksums.new" "$YQTMP/short-row/checksums"
yq_short_out="$(run_verify "$YQTMP/short-row")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: fehlende SHA-256-Spalte in der Zielzeile → exit ≠ 0"
printf '%s' "$yq_short_out" | grep -qF 'Format-Drift'
assert_true "$?" "#258: Meldung benennt die Format-Drift statt leise zu verifizieren"

# Fehlerszenario: nicht lesbare Eingabedatei (abgebrochener Download).
yq_fixture "$YQTMP/unreadable"
rm -f "$YQTMP/unreadable/checksums"
yq_unreadable_out="$(run_verify "$YQTMP/unreadable")"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: nicht lesbare checksums-Datei → exit ≠ 0 (fail-closed)"
printf '%s' "$yq_unreadable_out" | grep -qF 'nicht lesbar'
assert_true "$?" "#258: Meldung benennt die nicht lesbare Datei"

# ── Argument-Dispatch: fail-closed statt fail-open in den Installationspfad ──
# Alle folgenden Aufrufe laufen mit dem Netzwerk-Stub im PATH. Grund: fällt der Dispatch auf
# eine einzelne `--verify`-Bedingung zurück, landet JEDER dieser Aufrufe im Download-Pfad und
# überschriebe /usr/local/bin/yq. Mit dem Stub bricht so eine Regression am Download ab statt
# die lokale yq-Installation zu ersetzen – und die pfadspezifische Meldung unterscheidet
# "Dispatch hat abgelehnt" von "Stub hat abgebrochen" (Lesson nothra/tch-gastro-services#214).
yq_dispatch() {
  PATH="$YQ_NONETBIN:$PATH" bash "$INSTALL_YQ" "$@" 2>&1
}

yq_help_out="$(yq_dispatch --help)"; yq_rc=$?
assert_exit 0 "$yq_rc" "#258: --help → exit 0 (Usage statt Installation)"
printf '%s' "$yq_help_out" | grep -qF 'Verwendung:'
assert_true "$?" "#258: --help gibt die Usage aus"
! printf '%s' "$yq_help_out" | grep -qF 'NETZWERK-STUB'
assert_true "$?" "#258: --help lädt nichts herunter (kein fail-open in den Installationspfad)"

yq_typo_out="$(yq_dispatch --verfiy "$YQTMP/ok/yq_linux_amd64")"; yq_rc=$?
assert_exit 2 "$yq_rc" "#258: unbekanntes Argument (Tippfehler --verfiy) → exit 2 statt Installation"
printf '%s' "$yq_typo_out" | grep -qF 'Unbekanntes Argument'
assert_true "$?" "#258: unbekanntes Argument wird als solches benannt (pfadspezifisch)"
! printf '%s' "$yq_typo_out" | grep -qF 'NETZWERK-STUB'
assert_true "$?" "#258: unbekanntes Argument löst keinen Download aus (fail-closed)"

# Aufruf-Fehler: --verify ohne die vollständigen vier Argumente darf nicht als Erfolg durchgehen –
# und benennt wie jeder andere Fehlerpfad, was fehlt (nicht nur nackte Usage).
yq_argc_out="$(yq_dispatch --verify "$YQTMP/ok/yq_linux_amd64")"; yq_rc=$?
assert_exit 2 "$yq_rc" "#258: --verify mit unvollständigen Argumenten → exit 2 (Aufruf-Fehler)"
printf '%s' "$yq_argc_out" | grep -qF 'braucht vier Argumente'
assert_true "$?" "#258: unvollständige --verify-Argumente werden pfadspezifisch benannt"

# ── Plattform-Guard: der gepinnte Hash gilt für genau EIN Artefakt (yq_linux_amd64) ──
# `uname` wird per PATH-Shadowing verstellt, damit der Guard auf JEDER Testmaschine (macOS wie
# Linux-CI) deterministisch feuert – netzwerkfrei, weil er vor dem Download liegt. Der
# wget/curl-Stub bleibt daneben im PATH: fehlt der Guard, bricht der Lauf am Stub ab, statt ein
# funktionierendes /usr/local/bin/yq mit einem Fremdplattform-Binary zu überschreiben.
yq_uname_stub() {
  local dir="$1" os="$2" arch="$3"
  mkdir -p "$dir"
  cp "$YQ_NONETBIN/wget" "$dir/wget"
  cp "$YQ_NONETBIN/curl" "$dir/curl"
  printf '#!/bin/sh\ncase "$1" in\n  -s) echo %s ;;\n  -m) echo %s ;;\nesac\n' "$os" "$arch" > "$dir/uname"
  chmod +x "$dir/uname"
}

yq_uname_stub "$YQTMP/darwin" Darwin arm64
yq_os_out="$(PATH="$YQTMP/darwin:$PATH" bash "$INSTALL_YQ" 2>&1)"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: Nicht-Linux-System → Installation bricht ab (exit ≠ 0)"
printf '%s' "$yq_os_out" | grep -qF 'Darwin'
assert_true "$?" "#258: Abbruch nennt das gemeldete Betriebssystem (OS-Guard greift, nicht der Netzwerk-Stub)"
! printf '%s' "$yq_os_out" | grep -qF 'NETZWERK-STUB'
assert_true "$?" "#258: OS-Guard greift VOR dem Download (nichts wurde geladen, nichts überschrieben)"

yq_uname_stub "$YQTMP/arm" Linux aarch64
yq_arch_out="$(PATH="$YQTMP/arm:$PATH" bash "$INSTALL_YQ" 2>&1)"; yq_rc=$?
assert_true "$([[ $yq_rc -ne 0 ]]; echo $?)" "#258: Linux auf falscher Architektur → Installation bricht ab (exit ≠ 0)"
printf '%s' "$yq_arch_out" | grep -qF 'aarch64'
assert_true "$?" "#258: Abbruch nennt die gemeldete Architektur (eigener Fehlerpfad, nicht der OS-Pfad)"
! printf '%s' "$yq_arch_out" | grep -qF 'NETZWERK-STUB'
assert_true "$?" "#258: Architektur-Guard greift VOR dem Download (nichts wurde geladen)"

rm -rf "$YQTMP"

echo ""
echo "#258 Doku nennt den kanonischen yq-Bereitstellungsweg (Lesson #211/#176):"

# Die Single-Source-Aussage stand bisher nur im Skript-Header – und Skript-Header werden nicht
# in den Agenten-Kontext geladen. Ohne Regel in GELADENER Doku entsteht der nächste kopierte
# wget-Block genauso wie der, der zu nothra/tch-gastro-services#258 geführt hat. Vorbild ist install-hooks.sh: dieselbe
# Regel steht dort in CLAUDE.md UND OPERATING.md (ADR-042).
for yq_doc in "$FACTORY_ROOT/docs/factory/FACTORY.md" "$FACTORY_ROOT/docs/factory/OPERATING.md"; do
  [ -r "$yq_doc" ]
  assert_true "$?" "#258: $(basename "$yq_doc") ist lesbar (Vorbedingung des Doku-Checks)"
  grep -qF 'scripts/install-yq.sh' "$yq_doc"
  assert_true "$?" "#258: $(basename "$yq_doc") nennt 'scripts/install-yq.sh' als kanonischen yq-Bereitstellungsweg"
done

# ─── Task 286: Kleinfunde-Schwelle statt unbedingter autonomer Issue-Anlage (ADR-043) ──
echo ""
echo "Task 286: Schwellen-Tabelle + Sammeldatei statt unbedingter Issue-Anlage:"

# Die Mehrwort-Content-Checks unten laufen über flat_286()/assert_contains_286() (Definition
# bei den übrigen Assert-Helpern am Dateikopf): Prosa-Aussagen werden zeilenumbruch-tolerant
# geprüft, nicht gegen die aktuelle Zeilenbreite.
KLEINFUNDE="$FACTORY_ROOT/docs/factory/kleinfunde.md"

# (0) Verweis-Ziel existiert: sonst zeigen die Skill-Verweise auf kleinfunde.md ins Leere,
# ohne dass ein Guard das bemerkt (dangling reference, analog zum nothra/tch-gastro-services#155-ADR-029-Muster).
assert_true "$([[ -f "$KLEINFUNDE" ]]; echo $?)" \
  "#286: docs/factory/kleinfunde.md ist im Repo vorhanden (Verweis-Ziel nicht dangling)"

# Schema-Kontrakt lebt in der Datei selbst (ADR-043 Decision 4): Überschrift ohne laufende
# Nummer, Felder Wo/Was/Fix/Herkunft. Kein "### <Ziffer> ·"-Eintrag mehr im Bestand.
kleinfunde_flat_286="$(flat_286 "$KLEINFUNDE")"
assert_contains_286 "$kleinfunde_flat_286" 'ohne laufende Nummer' \
  "#286: kleinfunde.md dokumentiert das Schema 'Überschrift ohne laufende Nummer'"
assert_true "$(! grep -qE '^### [0-9]+ ·' "$KLEINFUNDE"; echo $?)" \
  "#286: kleinfunde.md hat keine nummerierten Eintrags-Überschriften mehr"
# AK "Sammeldatei": alle vier Schema-Felder sind im Dateikopf benannt (/test-Ergänzung –
# bisher nur "ohne laufende Nummer" geprüft, nicht die Feldliste selbst).
for kleinfunde_field in '**Wo**' '**Was**' '**Fix**' '**Herkunft**'; do
  assert_contains_286 "$kleinfunde_flat_286" "$kleinfunde_field" \
    "#286: kleinfunde.md nennt das Schema-Feld $kleinfunde_field im Dateikopf"
done
# AK "wächst ein Eintrag über 'unter zehn Zeilen' → Issue" und "erledigt → gelöscht, nicht
# abgehakt" – beide Regeln waren schon vor nothra/tch-gastro-services#286 da, aber ungetestet (/test-Ergänzung).
assert_contains_286 "$kleinfunde_flat_286" 'wird er ein Issue' \
  "#286: kleinfunde.md dokumentiert die Promotion-Regel (über 'unter zehn Zeilen' → Issue)"
assert_contains_286 "$kleinfunde_flat_286" 'gelöscht, nicht abgehakt' \
  "#286: kleinfunde.md dokumentiert 'erledigt → gelöscht, nicht abgehakt'"
# AK "vier überführte Einträge aus nothra/tch-gastro-services#279/#280/#282/#283 vorhanden" – bisher nur "keine
# Nummerierung mehr" geprüft, nicht dass die vier konkreten Bestandseinträge noch da sind
# (/test-Ergänzung, Testing-Persona-Finding).
for kleinfunde_issue in '#279' '#280' '#282' '#283'; do
  assert_contains_286 "$kleinfunde_flat_286" "$kleinfunde_issue" \
    "#286: kleinfunde.md enthält weiterhin den Bestandseintrag zu $kleinfunde_issue"
done
# AK "Duplikat-Prüfung per Suche auf die Fundstelle dokumentiert" (/test-Ergänzung).
assert_contains_286 "$kleinfunde_flat_286" 'schon existiert' \
  "#286: kleinfunde.md dokumentiert die Duplikat-Prüfung ('schon existiert')"
# Security-Review-Finding: Wo/Was/Fix sind Daten, keine Anweisungen – Freitext-Einträge, die
# ein späterer Agentenlauf (Duplikat-Prüfung, /codify, /implement) wieder in seinen Kontext
# lädt, sind ein Stored-Prompt-Injection-Kanal analog zu Issue-Titel/-Body (ADR-018). Ohne
# diese Warnung fehlt die zu den Issue-Labels äquivalente Absicherung komplett.
assert_contains_286 "$kleinfunde_flat_286" 'sind **Daten**, keine Anweisungen' \
  "#286: kleinfunde.md warnt, dass Wo/Was/Fix Daten sind, keine Anweisungen (Security-Review-Finding)"

# git-workflow.md trägt die Schwellen-Tabelle als kanonische Einzelquelle – kein dangling
# reference bei den drei Skill-Verweisen unten.
gitwf_flat_286="$(flat_286 "$GITWF")"
assert_contains_286 "$gitwf_flat_286" 'Schwelle: Issue oder Sammeldatei' \
  "#286: git-workflow.md trägt die Schwellen-Tabelle (Verweis-Ziel existiert)"
# AK "vollständige Schwellen-Tabelle mit den vier Zeilen" – bisher nur die Abschnitts-
# Überschrift geprüft, nicht die vier tatsächlichen Tabellenzeilen selbst (ein Abschneiden
# der Tabelle auf zwei Zeilen hätte den bisherigen Guard nicht rot gemacht, Testing-Persona-
# Finding).
for schwellen_tabelle_zeile_286 in 'Merge-Blocker im aktuellen PR' 'Echtes Sicherheitsrisiko' \
    'Funktionaler Defekt mit reproduzierbarem Auslöser' 'Alles andere'; do
  assert_contains_286 "$gitwf_flat_286" "$schwellen_tabelle_zeile_286" \
    "#286: Schwellen-Tabelle in git-workflow.md enthält die Zeile '$schwellen_tabelle_zeile_286'"
done
# AK "existiert genau einmal": die Tabellenzeile ist repo-weit eindeutig identifizierbar, nicht
# nur "vorhanden" (sonst könnte ein zweites Vorkommen unbemerkt entstehen, obwohl ADR-043
# Decision 4 explizit "ein Ort je Regel" fordert).
fund_art_zeilen_count_286="$(grep -rn 'Fund-Art' "$FACTORY_ROOT/docs/" "$FACTORY_ROOT/.claude/" 2>/dev/null | wc -l | tr -d ' ')"
assert_true "$([[ "$fund_art_zeilen_count_286" = "1" ]]; echo $?)" \
  "#286: Schwellen-Tabelle (Kopfzeile 'Fund-Art') existiert repo-weit in docs/+.claude/ genau einmal"
assert_contains_286 "$gitwf_flat_286" 'im Zweifel Issue' \
  "#286: git-workflow.md dokumentiert die Zweifelsregel 'im Zweifel Issue'"
assert_contains_286 "$gitwf_flat_286" 'Ist der Auslöser' \
  "#286: git-workflow.md nennt die Herstellbarkeits-Entscheidungshilfe"
assert_true "$(! printf '%s' "$gitwf_flat_286" | grep -qF 'ebenso legen die Skills'; echo $?)" \
  "#286: git-workflow.md beschreibt die Skill-Anlage nicht mehr als unbedingt ('ebenso legen die Skills')"

# Je Skill-Doku: Präsenz (verweist auf Sammeldatei + Schwellen-Tabelle) UND Abwesenheit (die
# alte unbedingte Anweisungszeile ist verschwunden). Anker sind echte, im jeweiligen
# Wortlaut vor nothra/tch-gastro-services#286 einmalig vorkommende Anweisungssätze – kein Kommando-Fragment (Lesson
# factory-workflow.md "Reihenfolge-/Präsenz-Guards": Anker an der echten Zeile, nicht an
# einem Fragment oder einer nie feuernden Alternative).
# Kein 'declare -A' (macOS-Bash 3.2 kennt keine assoziativen Arrays, clean-code.md
# "Portabilität in Gate-/Shell-Skripten") – Zuordnung Skill → alte Anweisungszeile per case.
old_unconditional_line_286() {
  case "$1" in
    review) printf '%s' 'statt es nur zu vermerken' ;;
    security-review) printf '%s' 'damit es auffindbar bleibt' ;;
    codify) printf '%s' 'statt es nur im Report zu vermerken' ;;
    # Fail-closed statt stillem Leerstring: ein Leerstring wäre als grep-F-Pattern ein
    # Match auf JEDE Zeile (Review-Runde-1-Finding) – ein unbekannter Skill-Key soll den
    # Anker sichtbar verfehlen, nicht versehentlich alles matchen.
    *) printf '%s' '__UNKNOWN_SKILL_KEY_286__' ;;
  esac
}
for sk in codify review security-review; do
  skf="$FACTORY_ROOT/.claude/commands/$sk.md"
  skf_flat_286="$(flat_286 "$skf")"

  assert_contains_286 "$skf_flat_286" 'kleinfunde.md' \
    "#286: /$sk-Skill-Doku verweist auf docs/factory/kleinfunde.md"
  assert_contains_286 "$skf_flat_286" 'Schwellen-Tabelle in' \
    "#286: /$sk-Skill-Doku verweist auf die Schwellen-Tabelle in git-workflow.md"

  # AK "Klassifikations-Anweisung steht VOR dem create_issue_idempotent-Aufruf" (die zentrale
  # Reihenfolge-Anforderung der ganzen Task – bisher nur inhaltlich, nie an der Position
  # geprüft, Lesson factory-workflow.md "Reihenfolge-/Präsenz-Guards"). Anker ist die echte
  # Aufrufzeile am Spaltenanfang (Lesson nothra/tch-gastro-services#114), nicht eine Prosa-Erwähnung.
  class_line_286="$(grep -n 'Schwellen-Tabelle in' "$skf" | head -1 | cut -d: -f1)"
  call_line_286="$(grep -n '^create_issue_idempotent ' "$skf" | head -1 | cut -d: -f1)"
  assert_true "$([ -n "$class_line_286" ] && [ -n "$call_line_286" ] \
      && [ "$class_line_286" -lt "$call_line_286" ]; echo $?)" \
    "#286: /$sk-Skill-Doku: Klassifikations-Anweisung (Zeile $class_line_286) steht vor dem create_issue_idempotent-Aufruf (Zeile $call_line_286)"

  # AK "kritisches Finding im Scope bleibt Merge-Blocker" gilt laut Spec nur für /review und
  # /security-review (nicht /codify, das keinen PR-Diff-Scope hat) – Testing-Persona-Finding.
  # AK "funktionaler Defekt mit reproduzierbarem Auslöser" gilt für /review und /codify, nicht
  # /security-review (dessen Schwelle-A ausschließlich Sicherheitsrisiko/Zweifelsfall ist).
  case "$sk" in
    review)
      assert_contains_286 "$skf_flat_286" 'Findings **im** Scope bleiben' \
        "#286: /$sk-Skill-Doku: kritische Findings im Scope bleiben Merge-Blocker (nicht Issue/Sammeldatei)"
      assert_contains_286 "$skf_flat_286" 'funktionaler Defekt mit reproduzierbarem Auslöser' \
        "#286: /$sk-Skill-Doku nennt 'funktionaler Defekt mit reproduzierbarem Auslöser' als Issue-Fall (Schritt A)"
      ;;
    security-review)
      assert_contains_286 "$skf_flat_286" 'Kritische Findings im Scope** blockieren weiterhin den Merge' \
        "#286: /$sk-Skill-Doku: kritische Findings im Scope bleiben Merge-Blocker (nicht Issue/Sammeldatei)"
      assert_contains_286 "$skf_flat_286" '"security"' \
        "#286: /$sk-Skill-Doku trägt weiterhin das Aspekt-Label 'security' am create_issue_idempotent-Aufruf"
      ;;
    codify)
      assert_contains_286 "$skf_flat_286" 'funktionaler Defekt mit reproduzierbarem Auslöser' \
        "#286: /$sk-Skill-Doku nennt 'funktionaler Defekt mit reproduzierbarem Auslöser' als Issue-Fall (Schritt A)"
      ;;
  esac

  old_line="$(old_unconditional_line_286 "$sk")"
  assert_true "$(! grep -qF "$old_line" "$skf"; echo $?)" \
    "#286: /$sk-Skill-Doku enthält die alte unbedingte Anweisung ('$old_line') nicht mehr"

  # Mutationsbeleg: NICHT nur derselbe grep-Aufruf isoliert (das bewiese nur Quoting,
  # Review-Runde-2-Finding), sondern DERSELBE Assert-Ausdruck aus Zeile oben, gegen eine
  # Fixture, die die alte Formulierung zurückdreht – der MUSS dort mit "1" (rot) auswerten,
  # sonst wäre der Abwesenheits-Guard vakuos (AK: "per Mutation belegt, dass ein
  # Zurückdrehen ... den Test rot macht").
  mut_286="$(mktemp)"
  cp "$skf" "$mut_286"
  printf '\n%s\n' "$old_line" >> "$mut_286"
  mut_286_result="$(! grep -qF "$old_line" "$mut_286"; echo $?)"
  assert_true "$([[ "$mut_286_result" = "1" ]]; echo $?)" \
    "#286: Mutationsbeleg /$sk – derselbe Assert-Ausdruck wird auf der zurückgedrehten Fixture rot (liefert '1')"
  rm -f "$mut_286"
done

# Negativ-Kontrolle für den Reihenfolge-Guard oben: eine Fixture mit VERTAUSCHTER Reihenfolge
# (Aufruf zuerst, Klassifikations-Erwähnung danach) muss die Prüfung tatsächlich verfehlen –
# sonst wäre der Guard vakuos (kein Fall, in dem er je rot würde).
mut_order_286="$(mktemp)"
printf 'create_issue_idempotent "x" "y" enhancement\nSchwellen-Tabelle in git-workflow.md\n' > "$mut_order_286"
mut_order_class_286="$(grep -n 'Schwellen-Tabelle in' "$mut_order_286" | head -1 | cut -d: -f1)"
mut_order_call_286="$(grep -n '^create_issue_idempotent ' "$mut_order_286" | head -1 | cut -d: -f1)"
assert_true "$(! { [ -n "$mut_order_class_286" ] && [ -n "$mut_order_call_286" ] \
    && [ "$mut_order_class_286" -lt "$mut_order_call_286" ]; }; echo $?)" \
  "#286: Mutationsbeleg Reihenfolge-Guard – vertauschte Fixture (Aufruf vor Klassifikation) lässt den Ordering-Check fehlschlagen"
rm -f "$mut_order_286"

# ADR-018 §5 nennt die Schwelle und verweist auf ADR-043, statt die Tabelle zu kopieren.
ADR018="$FACTORY_ROOT/docs/factory/adr/018-central-issue-seam.md"
grep -qF 'ADR-043' "$ADR018"
assert_true "$?" "#286: ADR-018 verweist auf ADR-043 (Einschränkung von §5)"
assert_true "$(! grep -qE '\| Fund-Art \|' "$ADR018"; echo $?)" \
  "#286: ADR-018 kopiert die Schwellen-Tabelle nicht (bleibt allein in git-workflow.md)"

# ADR-043 ist beim Implementieren von Proposed auf Accepted geflippt (Lesson factory-workflow.md).
# Erste nicht-leere Zeile nach der '## Status'-Überschrift, statt 'head -n -1' (GNU-Extension,
# auf BSD/macOS-head nicht verfügbar – clean-code.md "Portabilität in Gate-/Shell-Skripten").
ADR043="$FACTORY_ROOT/docs/factory/adr/043-schwelle-fuer-autonome-issue-anlage.md"
adr043_status_line="$(awk '/^## Status/{found=1; next} found && NF {print; exit}' "$ADR043")"
assert_true "$([[ "$adr043_status_line" = "Accepted" ]]; echo $?)" "#286: ADR-043 Status ist auf 'Accepted' geflippt"

# ─── nothra/tch-gastro-services#291/#337: Dependency-Security-Floors ───────────────────────────────────
# Entfällt im Factory-Repo: es hat kein Lockfile, kein package.json und keine npm-Abhängigkeiten.

# ─── nothra/tch-gastro-services#267/#322: Session-Empfehlung vs. Worktree-Pflicht (Doku-Präzisierung) ──
echo ""
echo "#267/#322 Session-Empfehlung vs. Worktree-Pflicht (git-workflow.md/CLAUDE.md/OPERATING.md/start-work.sh):"

GW_267="$CHECKS_DIR/../../docs/factory/guidelines/git-workflow.md"
CLAUDE_MD_267="$CHECKS_DIR/../../docs/factory/FACTORY.md"
OPERATING_MD_267="$CHECKS_DIR/../../docs/factory/OPERATING.md"
OLD_PHRASE_267="Jede neue Task in einer neuen Claude-Session starten"

gw_flat_267=$(flat_286 "$GW_267")

# AK1: der Abschnitt trennt Pflicht (Worktree) von Empfehlung (Session) und nennt das fehlende Gate
assert_contains_286 "$gw_flat_267" "Eigener Worktree je Task ist Pflicht" \
  "AK1: git-workflow.md nennt den Worktree explizit als Pflicht"
assert_contains_286 "$gw_flat_267" "Neue Claude-Session ist Empfehlung" \
  "AK1: git-workflow.md nennt die Session explizit als Empfehlung"
assert_contains_286 "$gw_flat_267" "kein technisches Gate" \
  "AK1: git-workflow.md benennt das Fehlen eines technischen Gates für die Session-Empfehlung"
# Mutation (Negativ-Kontrolle): die alte, unqualifizierte Fassung erfüllt den Gate-Check nicht –
# belegt, dass der Guard nicht durch jede beliebige Session-Erwähnung grün wird.
assert_absent "$OLD_PHRASE_267" "kein technisches Gate" \
  "AK1 (Mutation): die alte, unqualifizierte Session-Zeile erfüllt den Gate-Guard nicht"

# AK2 (nothra/tch-gastro-services#322): start-work.sh + /requirements (ggf. /architecture) in derselben, noch
# task-freien Session ist jetzt der dokumentierte REGELFALL (zuvor Ausnahme); die
# Session-Empfehlung selbst ist explizit an den nachfolgenden /implement-Schritt gebunden.
# Grenze (keine Folge-Task in derselben Session) bleibt unverändert.
assert_contains_286 "$gw_flat_267" "in derselben, noch task-freien Session laufen" \
  "AK2: git-workflow.md nennt start-work.sh + /requirements (ggf. /architecture) in derselben Session"
assert_contains_286 "$gw_flat_267" "**Regelfall:**" \
  "AK2: git-workflow.md formuliert diesen Ablauf als Regelfall, nicht mehr als Ausnahme"
assert_absent "$gw_flat_267" "Zulässige Ausnahme:" \
  "AK2: git-workflow.md nennt den Ablauf nicht mehr als Ausnahme"
assert_contains_286 "$gw_flat_267" "Für den nachfolgenden \`/implement\`-Schritt" \
  "AK2: die Session-Empfehlung ist explizit an den /implement-Schritt gebunden"
assert_contains_286 "$gw_flat_267" "Grenze:" \
  "AK2: git-workflow.md benennt explizit eine Grenze"
assert_contains_286 "$gw_flat_267" "die nächste Task in derselben Session beginnen" \
  "AK2: git-workflow.md nennt die Grenze (keine Folge-Task in derselben Session)"
assert_absent "$OLD_PHRASE_267" "noch task-freien Session" \
  "AK2 (Mutation): die alte Fassung kennt weder Regelfall noch /implement-Bindung"

# F3: die Worktree-Pflicht bleibt unverändert unverhandelbar (Negativ-Richtung von AK1)
assert_contains_286 "$gw_flat_267" "Parallele Sessions: eigener Worktree (nicht verhandelbar)" \
  "F3: die Worktree-Pflicht bleibt als 'nicht verhandelbar' übertitelt"

# AK3 (nothra/tch-gastro-services#322): CLAUDE.md bindet die Empfehlung an den /implement-Schritt und verweist weiterhin
# auf git-workflow.md als kanonische Quelle.
claude_flat_267=$(flat_286 "$CLAUDE_MD_267")
assert_contains_286 "$claude_flat_267" "Empfehlung (keine Pflicht): Für den \`/implement\`-Schritt einer Task eine neue Claude-Session öffnen" \
  "AK3: FACTORY.md bindet die Guardrail-Empfehlung explizit an den /implement-Schritt"
assert_contains_286 "$claude_flat_267" "Kanonische Quelle für Regelfall und Grenze:" \
  "AK3: FACTORY.md verweist auf eine kanonische Quelle für Regelfall/Grenze"
assert_contains_286 "$claude_flat_267" "guidelines/git-workflow.md" \
  "AK3: der Verweis zeigt auf git-workflow.md"
assert_absent "$claude_flat_267" "$OLD_PHRASE_267" \
  "AK3: die alte, generische (nicht an /implement gebundene) Formulierung steht nicht mehr in FACTORY.md"
assert_absent "Jede neue Task in einer neuen Claude-Session starten. start-work.sh erinnert daran." \
  "Kanonische Quelle" \
  "AK3 (Mutation): die alte Guardrail-Zeile ohne Quellverweis erfüllt den Guard nicht"

# AK4: OPERATING.md widerspruchsfrei zu git-workflow.md/Abschnitt 1.1 (Empfehlung statt Pflicht)
operating_flat_267=$(flat_286 "$OPERATING_MD_267")
assert_contains_286 "$operating_flat_267" "Empfohlen: eine Task = eine Claude-Session" \
  "AK4: Abschnitt 2 formuliert die Session-Regel als Empfehlung"
assert_contains_286 "$operating_flat_267" "kein technisches Gate" \
  "AK4: Abschnitt 2 nennt explizit das Fehlen eines technischen Gates"
assert_absent "**Eine Task = eine Claude-Session.**" "kein technisches Gate" \
  "AK4 (Mutation): die alte imperative Fassung erfüllt den Guard nicht"

# AK7 (nothra/tch-gastro-services#322): die nothra/tch-gastro-services#267-Fassung der Session-Empfehlung (generisch statt an /implement gebunden)
# ist jetzt überholt und darf in keiner der vier betroffenen Dateien mehr vorkommen. Array statt
# space-getrennter String: der Worktree-Pfad dieses Repos enthält selbst Leerzeichen
# ("Mein Projekt.worktrees/…"), unquoted Word-Splitting zerrisse die Pfade.
ak7_files_267=("$GW_267" "$CLAUDE_MD_267" "$OPERATING_MD_267" "$SW")
for ak7_f in "${ak7_files_267[@]}"; do
  assert_absent "$(flat_286 "$ak7_f")" "$OLD_PHRASE_267" \
    "AK7: ${ak7_f##*/} enthält die #267-Fassung der Session-Empfehlung nicht mehr"
done
# Positivkontrolle (frische Wegwerf-Fixture, kein bereits vorhandener Mutant – Lesson nothra/tch-gastro-services#284):
# belegt, dass das Muster selbst funktionsfähig ist und eine Regression tatsächlich fände.
AK7_MUT_DOC_322=$(mktemp)
printf -- '- **Empfehlung (keine Pflicht): %s.**\n' "$OLD_PHRASE_267" > "$AK7_MUT_DOC_322"
assert_contains_286 "$(flat_286 "$AK7_MUT_DOC_322")" "$OLD_PHRASE_267" \
  "AK7 (Mutation): die Wegwerf-Fixture mit der alten Formulierung würde den Abwesenheits-Guard reißen lassen"

# ─── nothra/tch-gastro-services#310: Report-Guard honoriert nur einen frischen Verdict (Spec-310) ──────
# Der Guard in run_skill() wertete einen non-zero Exit als Erfolg, sobald die Report-Datei
# IRGENDEINEN gültigen Verdict enthielt – auch einen aus einer früheren Review-Iteration
# desselben Laufs (nothra/tch-gastro-services#310, Task 308) oder aus einem früheren Pipeline-Lauf (nothra/tch-gastro-services#91). Der Fix
# vergleicht einen Fingerprint der Report-Datei von VOR dem ersten Versuch des Aufrufs.
echo ""
echo "#310 report_fingerprint (Frische-Fingerprint der Report-Datei):"

RV_LIB310="$SCRIPTS_DIR/lib/report-verdict.sh"
TMP_FP310="$(mktemp -d)"; mkdir -p "$TMP_FP310/tasks"
# fp310 <skill> <task_id> – report_fingerprint aus der gesourcten Lib (tasks_dir = 3. Arg).
fp310() { bash -c 'source "$1"; report_fingerprint "$2" "$3" "$4"' _ "$RV_LIB310" "$1" "$2" "$TMP_FP310/tasks"; }
# rf310 <skill> <task_id> – report_file aus derselben Lib (AK9: eine Skill→Datei-Zuordnung).
rf310() { bash -c 'source "$1"; report_file "$2" "$3" "$4"' _ "$RV_LIB310" "$1" "$2" "$TMP_FP310/tasks"; }

# AK9: die Zuordnung Skill → Report-Datei kommt aus der Lib, nicht aus run-pipeline.sh.
assert_true "$([ "$(rf310 review 310)" = "$TMP_FP310/tasks/review-310.md" ]; echo $?)" \
  "#310 AK9: report_file(review) liefert tasks/review-<id>.md"
assert_true "$([ "$(rf310 security-review 310)" = "$TMP_FP310/tasks/security-310.md" ]; echo $?)" \
  "#310 AK9: report_file(security-review) liefert tasks/security-<id>.md"
assert_true "$([ -z "$(rf310 implement 310)" ]; echo $?)" \
  "#310 AK9: report_file(implement) liefert leer (kein report-erzeugendes Skill)"

# is_report_skill (nothra/tch-gastro-services#312 Review-Nitpick): benanntes Prädikat statt `[ -n "$(report_file …)" ]` an
# der Verzweigungsstelle in run_skill(). Beide Richtungen, damit es diskriminiert.
irs312() { bash -c 'source "$1"; is_report_skill "$2" "$3" "$4"' _ "$RV_LIB310" "$1" "$2" "$TMP_FP310/tasks"; }
assert_true "$(irs312 review 310; echo $?)" \
  "#312: is_report_skill(review) → wahr"
assert_true "$(irs312 security-review 310; echo $?)" \
  "#312: is_report_skill(security-review) → wahr"
assert_true "$(! irs312 implement 310; echo $?)" \
  "#312: is_report_skill(implement) → falsch (Diskriminierung in der Gegenrichtung)"

# AK3-Grundlage: „Datei fehlt" ist ein eigener Wert – sonst wäre der Übergang fehlt → vorhanden
# keine erkennbare Veränderung und ein neu geschriebener Report gälte als stale.
fp310_absent="$(fp310 review 310)"
assert_true "$([ -n "$fp310_absent" ]; echo $?)" \
  "#310: fehlende Report-Datei liefert einen Marker (nicht leer)"
printf '## Empfehlung\nNEEDS_REWORK\n' > "$TMP_FP310/tasks/review-310.md"
fp310_first="$(fp310 review 310)"
assert_true "$([ "$fp310_first" != "$fp310_absent" ]; echo $?)" \
  "#310 AK3: Übergang fehlt → vorhanden ändert den Fingerprint"

# Stabil bei unverändertem Inhalt (kein Zeitstempel/mtime) – sonst gälte jeder Report als frisch.
assert_true "$([ "$(fp310 review 310)" = "$fp310_first" ]; echo $?)" \
  "#310 AK1: unveränderte Datei liefert denselben Fingerprint (stale erkennbar)"

# Verdict inhaltlich identisch, Text neu → frisch (Fehlerszenario der Spec: die Iteration zählt).
printf '## Empfehlung\nNEEDS_REWORK\nneuer Text, gleicher Verdict\n' > "$TMP_FP310/tasks/review-310.md"
assert_true "$([ "$(fp310 review 310)" != "$fp310_first" ]; echo $?)" \
  "#310: geänderter Report-Text ändert den Fingerprint (auch bei gleichem Verdict)"

# AK5/AK9: security-review liest ausschließlich die eigene Datei (keine Kreuz-Wirkung).
printf '## Ergebnis\nPASSED\n' > "$TMP_FP310/tasks/security-310.md"
fp310_sec="$(fp310 security-review 310)"
printf '## Empfehlung\nAPPROVED\n' > "$TMP_FP310/tasks/review-310.md"
assert_true "$([ "$(fp310 security-review 310)" = "$fp310_sec" ]; echo $?)" \
  "#310 AK5: Änderung an review-<id>.md lässt den security-Fingerprint unberührt"

# AK10: nicht report-erzeugende Skills haben keinen Report – konstanter Wert, unabhängig
# von vorhandenen Report-Dateien (der Guard greift für sie ohnehin nie).
fp310_impl="$(fp310 implement 310)"
printf '## Empfehlung\nAPPROVED\nnoch eine Änderung\n' > "$TMP_FP310/tasks/review-310.md"
assert_true "$([ "$(fp310 implement 310)" = "$fp310_impl" ]; echo $?)" \
  "#310 AK10: Fingerprint eines nicht report-erzeugenden Skills ist von Report-Dateien unabhängig"

# AK8: die Prüfung liest nur – der Inhalt bleibt byte-identisch.
fp310_before_read="$(cksum < "$TMP_FP310/tasks/review-310.md")"
fp310 review 310 >/dev/null
assert_true "$([ "$(cksum < "$TMP_FP310/tasks/review-310.md")" = "$fp310_before_read" ]; echo $?)" \
  "#310 AK8: report_fingerprint verändert die Report-Datei nicht"

# UNREADABLE-Zweig (Fehlerszenario der Spec: „Fingerprint nicht ermittelbar → fail-closed").
# Deterministisch und ohne chmod-/Root-Abhängigkeit über ein PATH ohne `cksum`: die Datei
# bleibt lesbar, nur das Werkzeug fehlt.
fp310_nocksum() {
  bash -c 'source "$1"; PATH=/nonexistent-dir report_fingerprint "$2" "$3" "$4"' \
    _ "$RV_LIB310" "$1" "$2" "$TMP_FP310/tasks"
}
fp310_unreadable="$(fp310_nocksum review 310)"
assert_true "$([ "$fp310_unreadable" = "UNREADABLE" ]; echo $?)" \
  "#310: nicht ermittelbare Prüfsumme liefert den UNREADABLE-Marker statt eines leeren Werts"
# Erst diese Aussage macht den Zweig wertvoll: bleibt der Lesefehler bestehen, sind Vorher und
# Nachher gleich → stale → Fehlversuch, nie ein stiller Erfolg.
assert_true "$([ "$(fp310_nocksum review 310)" = "$fp310_unreadable" ]; echo $?)" \
  "#310: fortbestehender Lesefehler liefert zweimal denselben Fingerprint (stale, kein Erfolg)"
# Und der Marker kollidiert nicht mit einer echten Prüfsumme – sonst könnte ein Lesefehler wie
# ein unveränderter Inhalt aussehen (oder umgekehrt).
assert_true "$([ "$fp310_unreadable" != "$(fp310 review 310)" ]; echo $?)" \
  "#310: UNREADABLE ist von der echten Prüfsumme derselben Datei unterscheidbar"

# W1 (Log-Hygiene): der Lesefehler selbst darf nicht ins Pipeline-Log bluten. Nur als
# Nicht-root sinnvoll – root liest eine Datei mit Modus 000 trotzdem.
if [ "$(id -u)" != 0 ]; then
  printf '## Empfehlung\nAPPROVED\n' > "$TMP_FP310/tasks/review-320.md"
  chmod 000 "$TMP_FP310/tasks/review-320.md"
  # fp310_stderr <lib> – stdout verworfen, nur stderr des Aufrufs eingesammelt.
  fp310_stderr() {
    bash -c 'source "$1"; report_fingerprint review 320 "$2" >/dev/null' \
      _ "$1" "$TMP_FP310/tasks" 2>&1
  }
  assert_true "$([ -z "$(fp310_stderr "$RV_LIB310")" ]; echo $?)" \
    "#310: unlesbare Report-Datei erzeugt keine Fehlermeldung auf stderr (Log-Hygiene)"
  assert_true "$([ "$(bash -c 'source "$1"; report_fingerprint review 320 "$2"' \
    _ "$RV_LIB310" "$TMP_FP310/tasks" 2>/dev/null)" = "UNREADABLE" ]; echo $?)" \
    "#310: unlesbare Report-Datei bleibt trotzdem fail-closed (UNREADABLE)"
  # Mutationsbeleg: dieselbe stderr-Assertion gegen eine Lib mit getauschter
  # Redirection-Reihenfolge (Eingabe-Umleitung vor der stderr-Umleitung).
  sed 's#.*checksum="$(cksum.*#  checksum="$(cksum < "$file" 2>/dev/null)" || checksum=""#' \
    "$RV_LIB310" > "$TMP_FP310/mutant-lib.sh"
  cmp -s "$RV_LIB310" "$TMP_FP310/mutant-lib.sh"
  assert_true "$([ $? -ne 0 ]; echo $?)" \
    "#310 W1: Mutation greift wirklich (Redirection-Reihenfolge getauscht)"
  assert_true "$(! [ -z "$(fp310_stderr "$TMP_FP310/mutant-lib.sh")" ]; echo $?)" \
    "#310 W1 (Mutation): getauschte Reihenfolge lässt den Lesefehler ins Log – der Check oben ist kausal"
  chmod 644 "$TMP_FP310/tasks/review-320.md"
else
  echo "  • #310 W1: Log-Hygiene bei unlesbarer Report-Datei – übersprungen (root liest Modus 000)"
fi

rm -rf "$TMP_FP310"

# AK9 (Kopplungs-Guard, beide Seiten – Lesson testing.md „je Seite ein eigener Negativtest"):
# Positiv-Seite = pipeline_summary() zieht seine Report-Pfade wirklich aus dem Helper (Anker ist
# die exakte Aufrufzeile, kein Kommando-Fragment, Lesson nothra/tch-gastro-services#114); Negativ-Seite = das Pfadmuster
# steht nicht zusätzlich in run-pipeline.sh, sonst driften Guard, Frische-Prüfung und Summary
# wieder auseinander. Der Negativ-Check deckt auch die Schreibvarianten ohne Klammern und mit
# GROSS-Variable ab – das exakte Literal allein ließe ein wiedereingeführtes
# `tasks/review-$task_id.md` durch.
assert_true "$(grep -qF 'review_file="$(report_file review "$task_id")"' "$PIPELINE"; echo $?)" \
  "#310 AK9: pipeline_summary() holt den review-Report-Pfad über report_file"
assert_true "$(grep -qF 'security_file="$(report_file security-review "$task_id")"' "$PIPELINE"; echo $?)" \
  "#310 AK9: pipeline_summary() holt den security-Report-Pfad über report_file"
assert_true "$(! grep -Eq 'tasks/(review|security)-[$][{]?(task_id|TASK_ID)[}]?[.]md' "$PIPELINE"; echo $?)" \
  "#310 AK9: run-pipeline.sh baut keinen Report-Pfad selbst (auch nicht in Variantenschreibweise)"

# AK7 (Snapshot-Zeitpunkt): Der Fingerprint wird EINMAL VOR dem ersten Versuch erhoben – die
# Zuweisung steht also oberhalb der Retry-Schleife, nicht in ihr. Die E2E-Tests unten pinnen
# die beiden anderen Hälften von AK7 behavioral (AK2: vor dem claude-Aufruf, sonst gälte nie
# etwas als frisch; AK1: pro run_skill-Aufruf neu, sonst würde Iteration 1 die Iteration 2
# durchwinken); nur „vor der Schleife statt je Versuch" ist rein positionell. Verglichen werden
# Zeilennummern zweier exakter Zeilen, keine zwei isolierten Präsenz-Checks (Lesson nothra/tch-gastro-services#286).
ak7_snapshot_line_310() { grep -n 'report_fingerprint_before=' "$1" | head -1 | cut -d: -f1; }
ak7_loop_line_310()     { grep -n 'for attempt in 1 2 3; do' "$1" | head -1 | cut -d: -f1; }
assert_true "$([ "$(ak7_snapshot_line_310 "$PIPELINE")" -lt "$(ak7_loop_line_310 "$PIPELINE")" ]; echo $?)" \
  "#310 AK7: Fingerprint-Snapshot steht vor der Retry-Schleife (einmal pro run_skill-Aufruf)"

# Mutationsbeleg zu AK7: dieselbe Zeilennummern-Assertion gegen eine run-pipeline.sh, in der die
# Zuweisung IN die Schleife gewandert ist (= je Versuch neu erhoben). Ohne ihn belegte der Check
# oben nur, dass beide Zeilen existieren.
TMP_AK7_310="$(mktemp -d)"
awk '/report_fingerprint_before=/ { snapshot = $0; next }
     { print }
     /for attempt in 1 2 3; do/ && snapshot { print snapshot; snapshot = "" }' \
  "$PIPELINE" > "$TMP_AK7_310/mutant.sh"
assert_true "$([ "$(ak7_snapshot_line_310 "$TMP_AK7_310/mutant.sh")" -gt "$(ak7_loop_line_310 "$TMP_AK7_310/mutant.sh")" ]; echo $?)" \
  "#310 AK7: Mutation greift wirklich (Snapshot-Zuweisung in die Schleife verschoben)"
assert_true "$(! [ "$(ak7_snapshot_line_310 "$TMP_AK7_310/mutant.sh")" -lt "$(ak7_loop_line_310 "$TMP_AK7_310/mutant.sh")" ]; echo $?)" \
  "#310 AK7 (Mutation): per-Versuch erhobener Snapshot macht die Positions-Assertion rot"
rm -rf "$TMP_AK7_310"

echo ""
echo "#310 E2E: Report-Guard honoriert nur einen im Aufruf entstandenen Verdict:"

# scaffold_310 <dir> <task_id> – Wegwerf-Repo mit der ECHTEN run-pipeline.sh, Skill-Mocks und
# no-op-`sleep` (der Retry-Backoff aus run_skill würde die Suite sonst 30 s pro Fehl-Lauf
# blockieren). Die Skill-Dateien tragen einen SKILL-<name>-Marker: daran erkennt der
# `claude`-Stub im Prompt, welches Skill gerade läuft ('SKILL-review' ist kein Teilstring von
# 'SKILL-security-review'). Der Aufrufer legt danach Report-Dateien + Stub an und committet.
#
# Die Repo-Kopie selbst kommt aus `_mk_pipe_repo` (oben, nothra/tch-gastro-services#197-Block) – dort steht die
# kanonische Liste der Dateien, die run-pipeline.sh zum Starten braucht; hier wird nur die
# Differenz ergänzt (Interrupt-Pfad, Skill-Mocks, Task-Datei, sleep-Stub). Kein paralleler
# Zweitaufbau derselben Struktur (Lesson testing.md, nothra/tch-gastro-services#240/#267).
# Abhängigkeit: `_mk_pipe_repo` wird im `if [ "$HAS_YQ" = 1 ]`-Zweig definiert – wie alle
# Aufrufstellen von scaffold_310 unten.
scaffold_310() {
  local dir="$1" task_id="$2" s
  _mk_pipe_repo "$dir"
  mkdir -p "$dir/.claude/commands" "$dir/bin"
  cp "$CHECKS_DIR/interrupt-check.sh" "$dir/scripts/checks/"
  cp "$SCRIPTS_DIR/raise-interrupt.sh" "$dir/scripts/"
  for s in implement review test refactor security-review codify; do
    printf '# SKILL-%s mock\n' "$s" > "$dir/.claude/commands/$s.md"
  done
  printf '# Task %s: report-guard\n' "$task_id" > "$dir/tasks/task-${task_id}-guard.md"
  printf '#!/bin/sh\nexit 0\n' > "$dir/bin/sleep"; chmod +x "$dir/bin/sleep"
  # gh immer fehlschlagen lassen (nothra/tch-gastro-services#314-Nitpick, Review-Runde-1-Finding): run_310() setzt
  # "$dir/bin" vor den Rest von PATH, damit reicht ein Stub, um den ambienten System-`gh`
  # zu überschatten. Ohne ihn hinge der EXIT-Trap-Aufruf von `metrics.sh --quiet --publish`
  # (ADR-045) an der lokalen gh-Installation/-Authentifizierung – heute folgenlos, weil der
  # Bare-Remote dieser Wegwerf-Repos keinen bekannten GitHub-Host hat (gh scheitert sofort),
  # aber eine unausgesprochene Umgebungsannahme statt einer deterministischen Fixture.
  printf '#!/bin/sh\nexit 1\n' > "$dir/bin/gh"; chmod +x "$dir/bin/gh"
}

# commit_310 <dir> – Wegwerf-Repo committen (preflight_checks verlangt einen sauberen Baum).
# Explizite git-Identität: ohne sie schlägt der Commit in einer identitätslosen Umgebung
# fehl (Lesson testing.md, nothra/tch-gastro-services#265).
commit_310() {
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t add . >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m init
}

# run_310 <dir> <task_id> – echter Pipeline-Lauf im Wegwerf-Repo; Ausgabe in OUT_310,
# Exit-Code in RC_310 (Globals, weil eine Command Substitution den Exit-Code verschluckt).
# env -u: siehe nothra/tch-gastro-services#264 – kein Testblock entscheidet aus der Env der aufrufenden Shell.
run_310() {
  local dir="$1" task_id="$2"
  OUT_310=$(cd "$dir" && PATH="$dir/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
    env -u PR_SHEPHERD -u FACTORY_STAGE \
    bash "$dir/scripts/run-pipeline.sh" "$task_id" 2>&1); RC_310=$?
}

STALE_MSG_310='stammt aus einem früheren Aufruf'
FRESH_MSG_310='Turn-Limit toleriert'

# Anker der Guard-Bedingung in run_skill(). Immer die VOLLE Zeile, nie ein Kommando-Fragment
# (Lesson factory-workflow.md, nothra/tch-gastro-services#114): `report_fingerprint "$skill" "$task_id"` allein stünde
# auch in der Snapshot-Zeile oberhalb der Retry-Schleife, `stop_if_interrupted "$task_id"`
# dreimal im Skript. Seit nothra/tch-gastro-services#312 stehen beide Teilbedingungen in der Hilfsfunktion
# report_is_fresh_and_valid(), die BEIDE Rückkehrpfade auswerten – die Mutationsbelege des
# nothra/tch-gastro-services#310- und des nothra/tch-gastro-services#312-Blocks hängen an denselben Zeilen, darum eine gemeinsame Definition
# statt zweier gleichlautender Literale.
FRESH_CMP_PIPE='[ "$(report_fingerprint "$skill" "$task_id")" != "$fingerprint_before" ]'
VERDICT_CHK_PIPE='[ -n "$(report_verdict "$skill" "$task_id")" ] || return 1'
GUARD_CALL_PIPE='report_is_fresh_and_valid "$skill" "$task_id" "$report_fingerprint_before"'
IC_CALL_PIPE='stop_if_interrupted "$task_id"'

if [ "$HAS_YQ" = 1 ]; then
  # ── AK1/AK6/AK7 (Kern nothra/tch-gastro-services#310): Verdict aus Review-Iteration 1, Iteration 2 reißt das
  # Turn-Limit, ohne den Report zu berühren. Der Stub schreibt den Report genau beim
  # ERSTEN review-Aufruf (danach existiert die Datei → exit 1 ohne Schreiben) – damit ist
  # die Iteration-1-Datei die divergenzerzeugende Aktion (Lesson nothra/tch-gastro-services#253) und der Fingerprint
  # muss pro run_skill-Aufruf neu erhoben werden, nicht einmal pro Pipeline-Lauf (AK7).
  TMP_A310="$(mktemp -d)"
  scaffold_310 "$TMP_A310" 310
  cat > "$TMP_A310/bin/claude" <<'STUB_A310'
#!/bin/sh
case "$*" in
  *SKILL-review*)
    [ -f "$PWD/tasks/review-310.md" ] && exit 1
    printf '## Empfehlung\nNEEDS_REWORK\nIteration 1\n' > "$PWD/tasks/review-310.md"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB_A310
  chmod +x "$TMP_A310/bin/claude"
  commit_310 "$TMP_A310"
  run_310 "$TMP_A310" 310
  assert_exit 1 "$RC_310" \
    "#310 AK1/AK6: stale Verdict aus Iteration 1 → exit 1 nach 3 Versuchen (kein Circuit-Breaker-2)"
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#310 AK6: Abbruch über den bestehenden Retry-Pfad (failed after 3 attempts)"
  assert_contains_286 "$OUT_310" "$STALE_MSG_310" \
    "#310 AK1: Meldung benennt den stale Verdict als Grund"
  assert_absent "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK1: stale Verdict wird NICHT als fertiger Report toleriert"
  assert_absent "$OUT_310" "Circuit Breaker ausgelöst" \
    "#310 AK6: der Circuit Breaker wird nicht mehr durch Scheinerfolge hochgezählt"

  # ── AK11 (Mutationsbeleg): dieselben Assert-Ausdrücke gegen eine run-pipeline.sh, in der
  # NUR der Frische-Vergleich entfernt ist. Erwartung: der stale Verdict gilt wieder als
  # Erfolg, die Iteration zählt und der Circuit Breaker bricht mit exit 2 ab – exakt die
  # Symptomatik aus Task 308. Ohne diesen Beleg wäre der Test oben auch aus dem falschen
  # Grund grün (z. B. wenn der Stub gar keinen Verdict schreibt).
  TMP_M310="$(mktemp -d)"
  scaffold_310 "$TMP_M310" 310
  awk -v cmp="$FRESH_CMP_PIPE" 'index($0, cmp) > 0 { print "  true"; next } { print }' \
    "$PIPELINE" > "$TMP_M310/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$FRESH_CMP_PIPE" "$TMP_M310/scripts/run-pipeline.sh")" -eq 0 ]; echo $?)" \
    "#310 AK11: Mutation greift wirklich (Frische-Vergleich aus der Guard-Bedingung entfernt)"
  cp "$TMP_A310/bin/claude" "$TMP_M310/bin/claude"
  commit_310 "$TMP_M310"
  run_310 "$TMP_M310" 310
  assert_exit 2 "$RC_310" \
    "#310 AK11 (Mutation): ohne Frische-Vergleich zählt der Scheinerfolg → Circuit Breaker (exit 2)"
  assert_contains_286 "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK11 (Mutation): ohne Frische-Vergleich gilt der stale Verdict als fertiger Report"
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#310 AK11 (Mutation): ohne Frische-Vergleich kein Fehlversuch – der Test oben ist kausal"
  rm -rf "$TMP_M310"
  rm -rf "$TMP_A310"

  # ── AK2 (Regression ADR-019 §4): Report im Aufruf neu geschrieben, DANACH non-zero
  # (Turn-Limit) → weiterhin Erfolg, die Pipeline arbeitet mit dem Verdict weiter.
  TMP_B310="$(mktemp -d)"
  scaffold_310 "$TMP_B310" 311
  printf '## Empfehlung\nNEEDS_REWORK\nalte Iteration\n' > "$TMP_B310/tasks/review-311.md"
  cat > "$TMP_B310/bin/claude" <<'STUB_B310'
#!/bin/sh
case "$*" in
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/review-311.md"
    exit 1 ;;
  *) exit 0 ;;
esac
STUB_B310
  chmod +x "$TMP_B310/bin/claude"
  commit_310 "$TMP_B310"
  run_310 "$TMP_B310" 311
  assert_contains_286 "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK2: frisch geschriebener Report + Turn-Limit bleibt Erfolg"
  assert_absent "$OUT_310" "$STALE_MSG_310" \
    "#310 AK2: kein Stale-Verdikt bei verändertem Report"
  assert_contains_286 "$OUT_310" "Phase 3" \
    "#310 AK2: die Pipeline arbeitet mit dem frischen Verdict weiter (Phase 3 erreicht)"
  rm -rf "$TMP_B310"

  # ── AK3 (Neuanlage): vorher KEINE Report-Datei, im Aufruf geschrieben → frisch.
  # Identischer Stub wie AK2, nur ohne vorbestehende Datei – der Übergang „fehlt →
  # vorhanden" ist die einzige Änderung an der Ausgangslage.
  TMP_C310="$(mktemp -d)"
  scaffold_310 "$TMP_C310" 312
  cat > "$TMP_C310/bin/claude" <<'STUB_C310'
#!/bin/sh
case "$*" in
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nerstmals geschrieben\n' > "$PWD/tasks/review-312.md"
    exit 1 ;;
  *) exit 0 ;;
esac
STUB_C310
  chmod +x "$TMP_C310/bin/claude"
  commit_310 "$TMP_C310"
  run_310 "$TMP_C310" 312
  assert_contains_286 "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK3: zuvor fehlende, im Aufruf neu geschriebene Report-Datei zählt als frisch"
  assert_contains_286 "$OUT_310" "Phase 3" \
    "#310 AK3: die Pipeline arbeitet mit dem neuen Verdict weiter"
  rm -rf "$TMP_C310"

  # ── AK4/AK8 (nothra/tch-gastro-services#91, Re-Lauf): committeter Report aus einem früheren Lauf, erster Versuch
  # scheitert sofort ohne die Datei zu berühren → Fehlversuch statt fail-open. AK8 hängt an
  # genau diesem Fall: hier schreibt niemand, der Report muss byte-identisch bleiben.
  TMP_D310="$(mktemp -d)"
  scaffold_310 "$TMP_D310" 313
  printf '## Empfehlung\nAPPROVED\naus einem früheren Pipeline-Lauf\n' > "$TMP_D310/tasks/review-313.md"
  cat > "$TMP_D310/bin/claude" <<'STUB_D310'
#!/bin/sh
case "$*" in
  *SKILL-review*) exit 1 ;;
  *) exit 0 ;;
esac
STUB_D310
  chmod +x "$TMP_D310/bin/claude"
  commit_310 "$TMP_D310"
  cksum_d310_before="$(cksum < "$TMP_D310/tasks/review-313.md")"
  run_310 "$TMP_D310" 313
  assert_exit 1 "$RC_310" "#310 AK4: committeter Report aus früherem Lauf → Fehlversuch (exit 1)"
  # Pfadspezifisches Signal, nicht nur der Exit-Code: ohne die Frische-Prüfung liefe die
  # Pipeline weiter und scheiterte erst an der Endzustands-Verifikation – ebenfalls exit 1.
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#310 AK4: Abbruch im Retry-Pfad von run_skill (nicht erst am Pipeline-Ende)"
  assert_absent "$OUT_310" "Phase 3" \
    "#310 AK4: die Pipeline verlässt den Review-Loop nicht mit dem alten Verdict"
  assert_contains_286 "$OUT_310" "$STALE_MSG_310" "#310 AK4: Meldung benennt den früheren Aufruf"
  assert_absent "$OUT_310" "$FRESH_MSG_310" "#310 AK4: kein fail-open beim Re-Lauf"
  assert_true "$([ "$(cksum < "$TMP_D310/tasks/review-313.md")" = "$cksum_d310_before" ]; echo $?)" \
    "#310 AK8: Report-Datei bleibt inhaltlich unverändert (kein rm/Truncate)"
  assert_true "$([ -z "$(git -C "$TMP_D310" status --porcelain -- tasks/review-313.md)" ]; echo $?)" \
    "#310 AK8: die Prüfung verändert den git status der Report-Datei nicht"
  rm -rf "$TMP_D310"

  # ── AK5 (security-review identisch): review läuft regulär durch (exit 0), das
  # Security-Gate trifft auf einen committeten PASSED aus einem früheren Aufruf.
  TMP_E310="$(mktemp -d)"
  scaffold_310 "$TMP_E310" 314
  printf '## Empfehlung\nAPPROVED\n' > "$TMP_E310/tasks/review-314.md"
  printf '## Ergebnis\nPASSED\naus einem früheren Aufruf\n' > "$TMP_E310/tasks/security-314.md"
  cat > "$TMP_E310/bin/claude" <<'STUB_E310'
#!/bin/sh
case "$*" in
  *SKILL-security-review*) exit 1 ;;
  *) exit 0 ;;
esac
STUB_E310
  chmod +x "$TMP_E310/bin/claude"
  commit_310 "$TMP_E310"
  run_310 "$TMP_E310" 314
  assert_exit 1 "$RC_310" "#310 AK5: stale PASSED im security-Report → Fehlversuch (exit 1)"
  # Wie bei AK4: der Exit-Code allein unterscheidet den Guard nicht von einem späteren
  # Abbruch – 'failed after 3 attempts' und das nie erreichte Phase 6 tun es.
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#310 AK5: Abbruch im Retry-Pfad von run_skill (security-review)"
  assert_absent "$OUT_310" "Phase 6" \
    "#310 AK5: Codify wird mit dem alten Security-Verdict nicht erreicht"
  assert_contains_286 "$OUT_310" "$STALE_MSG_310" \
    "#310 AK5: Meldung benennt den stale Security-Verdict"
  assert_absent "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK5: alter PASSED wird nicht als Ergebnis dieses Laufs gewertet"
  rm -rf "$TMP_E310"

  # ── AK10 (andere Skills unberührt): `implement` scheitert, obwohl ein gültiger Review-Report
  # vorliegt → unverändert Fehlversuch → exit 1, ohne Guard-Meldung in beide Richtungen.
  TMP_F310="$(mktemp -d)"
  scaffold_310 "$TMP_F310" 315
  printf '## Empfehlung\nAPPROVED\n' > "$TMP_F310/tasks/review-315.md"
  cat > "$TMP_F310/bin/claude" <<'STUB_F310'
#!/bin/sh
case "$*" in
  *SKILL-implement*) exit 1 ;;
  *) exit 0 ;;
esac
STUB_F310
  chmod +x "$TMP_F310/bin/claude"
  commit_310 "$TMP_F310"
  run_310 "$TMP_F310" 315
  assert_exit 1 "$RC_310" "#310 AK10: nicht report-erzeugendes Skill → Verhalten unverändert (exit 1)"
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#310 AK10: Abbruch weiterhin über den Retry-Pfad"
  assert_absent "$OUT_310" "$FRESH_MSG_310" \
    "#310 AK10: vorhandener Review-Report macht /implement nicht erfolgreich"
  assert_absent "$OUT_310" "$STALE_MSG_310" \
    "#310 AK10: keine Guard-Meldung für nicht report-erzeugende Skills"
  rm -rf "$TMP_F310"

  # ── Interrupt-Stopp im Stale-Zweig (nothra/tch-gastro-services#310 Review-Runde-2-Nitpick): Ein Aufruf, der einen
  # Interrupt signalisiert UND danach non-zero endet, wurde vor nothra/tch-gastro-services#310 über den (damals
  # erfolgreichen) Verdict-Zweig sofort gestoppt. Ohne `interrupt-check.sh` im neuen
  # Stale-Zweig folgten stattdessen zwei weitere Heavy-Versuche desselben Skills, und der
  # Blocker-Eintrag in der Task-Datei entfiel. Divergenzerzeugende Aktion ist der echte
  # `raise-interrupt.sh`-Aufruf im Stub – kein nachgebautes Sentinel.
  TMP_G310="$(mktemp -d)"
  scaffold_310 "$TMP_G310" 316
  printf '## Empfehlung\nAPPROVED\naus einem früheren Aufruf\n' > "$TMP_G310/tasks/review-316.md"
  cat > "$TMP_G310/bin/claude" <<'STUB_G310'
#!/bin/sh
case "$*" in
  *SKILL-review*)
    bash "$PWD/scripts/raise-interrupt.sh" 316 ADR "Trigger-Kategorie 1: Testfall" >/dev/null
    exit 1 ;;
  *) exit 0 ;;
esac
STUB_G310
  chmod +x "$TMP_G310/bin/claude"
  commit_310 "$TMP_G310"
  run_310 "$TMP_G310" 316
  assert_exit 1 "$RC_310" \
    "#310 Interrupt/Stale: signalisierter Interrupt stoppt die Pipeline (exit 1)"
  assert_contains_286 "$OUT_310" "[INTERRUPT] ADR: Trigger-Kategorie 1: Testfall" \
    "#310 Interrupt/Stale: der Interrupt wird auch im Stale-Zweig erkannt"
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#310 Interrupt/Stale: kein Weiterlaufen über zwei zusätzliche Heavy-Versuche"
  assert_true "$(grep -qF 'Pipeline pausiert – ADR: Trigger-Kategorie 1: Testfall' \
    "$TMP_G310/tasks/task-316-guard.md"; echo $?)" \
    "#310 Interrupt/Stale: Blocker-Eintrag landet in der Task-Datei"

  # ── Mutationsbeleg dazu: dieselben Assert-Ausdrücke gegen eine run-pipeline.sh, in der NUR
  # der Stop-bei-Interrupt-Aufruf des Stale-Zweigs fehlt (awk löscht die erste solche Zeile
  # NACH der Stale-Meldung – die beiden Erfolgs-Zweige bleiben unberührt). Seit /refactor steht
  # der Aufruf über die Helper-Funktion stop_if_interrupted() (Dedup der zuvor dreifachen
  # Aufrufzeile, nothra/tch-gastro-services#310 Review-Runde-3-Nitpick).
  # Anker ist die exakte AUFRUF-Zeile ($IC_CALL_PIPE), nicht der Funktionsname: gegen ein
  # Fragment gematcht erwischte die Mutation zuerst die Erwähnung im WHY-Kommentar darüber
  # und ließ den echten Aufruf stehen (Lesson factory-workflow.md, nothra/tch-gastro-services#114 – „Kommando ≠
  # Prosa-Erwähnung").
  TMP_H310="$(mktemp -d)"
  scaffold_310 "$TMP_H310" 316
  awk -v call="$IC_CALL_PIPE" '
       /stammt aus einem früheren Aufruf/ { seen = 1 }
       seen && index($0, call) > 0 { seen = 0; next }
       { print }' "$PIPELINE" > "$TMP_H310/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$IC_CALL_PIPE" "$TMP_H310/scripts/run-pipeline.sh")" \
    -eq "$(($(grep -cF -- "$IC_CALL_PIPE" "$PIPELINE") - 1))" ]; echo $?)" \
    "#310 Interrupt/Stale: Mutation greift wirklich (genau ein interrupt-check-Aufruf entfernt)"
  printf '## Empfehlung\nAPPROVED\naus einem früheren Aufruf\n' > "$TMP_H310/tasks/review-316.md"
  cp "$TMP_G310/bin/claude" "$TMP_H310/bin/claude"
  commit_310 "$TMP_H310"
  run_310 "$TMP_H310" 316
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#310 Interrupt/Stale (Mutation): ohne den Aufruf laufen alle drei Versuche – der Check oben ist kausal"
  assert_absent "$OUT_310" "[INTERRUPT] ADR: Trigger-Kategorie 1: Testfall" \
    "#310 Interrupt/Stale (Mutation): ohne den Aufruf bleibt der Interrupt unbemerkt"
  rm -rf "$TMP_H310"
  rm -rf "$TMP_G310"
else
  skip_yq "#310 E2E: Report-Guard Frische-Prüfung (AK1–AK6, AK8, AK10, AK11, Interrupt/Stale)"
fi

# ─── nothra/tch-gastro-services#310 AK12: Doku-Nachzug (ADR-019 §4 + Lesson-Absätze nothra/tch-gastro-services#91/#310) ──────────
echo ""
echo "#310 AK12: ADR-019 §4 und die Lesson-Absätze beschreiben die Frische-Bedingung:"

ADR019_310="$FACTORY_ROOT/docs/factory/adr/019-stage3-commit-seam-report-guard.md"
adr019_flat_310=$(flat_286 "$ADR019_310")
assert_contains_286 "$adr019_flat_310" "seit dem Beginn dieses Skill-Aufrufs verändert" \
  "#310 AK12: ADR-019 §4 nennt die Frische-Bedingung des Guards"
assert_contains_286 "$adr019_flat_310" "report_fingerprint" \
  "#310 AK12: ADR-019 §4 nennt den Fingerprint-Helper namentlich"

workflow_flat_310=$(flat_286 "$WORKFLOW_LESSON")
assert_contains_286 "$workflow_flat_310" "In nothra/tch-gastro-services#310 umgesetzt" \
  "#310 AK12: Lesson nennt den Erledigt-Stand des Report-Guard-Fixes"
assert_absent "$workflow_flat_310" "Bis dahin: Pipeline-Re-Läufe" \
  "#310 AK12: die Übergangsanweisung 'bis dahin manuell prüfen' ist aufgelöst"
assert_absent "$workflow_flat_310" "muss also **zusätzlich** vor jedem Schleifendurchlauf greifen" \
  "#310 AK12: die Within-Run-Regel steht nicht mehr als offene Forderung"

# ─── nothra/tch-gastro-services#312: Frische-Prüfung auch auf dem Exit-0-Rückkehrpfad (Spec-312) ───────
# nothra/tch-gastro-services#310 hat die Frische-Prüfung nur in den non-zero-Zweig von run_skill() gelegt. Endete
# `claude --print` mit Exit 0, kehrte run_skill() mit `return 0` zurück, ohne den erhobenen
# Fingerprint je anzusehen – Phase 2 las danach einen stehengebliebenen APPROVED und verließ
# den Review-Loop, ohne dass in diesem Lauf ein Review stattfand (dieselbe fail-open-Richtung
# wie nothra/tch-gastro-services#91/#310, nur über den Erfolgs- statt den Fehlerpfad). Der Fix wertet beide
# Rückkehrpfade gegen dieselbe Bedingung aus und verlangt zusätzlich einen eindeutigen
# Verdict; das Security-Gate in Phase 5 ist auf „nur PASSED passiert" umgedreht.
echo ""
echo "#312 Struktur: eine Bedingung, ein Ort (AK9):"

# Die Zeilen-Anker der Guard-Bedingung ($FRESH_CMP_PIPE / $VERDICT_CHK_PIPE / $GUARD_CALL_PIPE /
# $IC_CALL_PIPE) stehen gemeinsam mit STALE_MSG_310/FRESH_MSG_310 oben – nothra/tch-gastro-services#310 und nothra/tch-gastro-services#312 mutieren
# dieselben Zeilen, deshalb genau eine Definition.
GATE_CMP_312='if [ "$SECURITY_VERDICT" != "PASSED" ]; then'

assert_true "$([ "$(grep -cF -- "$FRESH_CMP_PIPE" "$PIPELINE")" -eq 1 ]; echo $?)" \
  "#312 AK9: der Frische-Vergleich steht genau einmal im Skript (gemeinsame Hilfsfunktion)"
assert_true "$([ "$(grep -cF -- "$VERDICT_CHK_PIPE" "$PIPELINE")" -eq 1 ]; echo $?)" \
  "#312 AK9: die Verdict-Gültigkeitsprüfung steht genau einmal im Skript"
assert_true "$([ "$(grep -cF -- "$GUARD_CALL_PIPE" "$PIPELINE")" -eq 1 ]; echo $?)" \
  "#312 AK9: beide Rückkehrpfade werten dieselbe Hilfsfunktion mit demselben Snapshot aus"
assert_true "$([ "$(grep -c 'report_fingerprint_before=' "$PIPELINE")" -eq 1 ]; echo $?)" \
  "#312 AK9: nur EIN Fingerprint-Snapshot pro run_skill-Aufruf (kein zweiter im Exit-0-Zweig)"
assert_true "$(! grep -q 'report_fingerprint_now' "$PIPELINE"; echo $?)" \
  "#312 AK9: keine zweite Schreibweise der Bedingung im non-zero-Zweig mehr"
# AK9 („kein Report-Pfad in run-pipeline.sh"): der Report-Guard verzweigt über das benannte
# Prädikat aus der Lib. Zweite Assertion in der Gegenrichtung – die frühere Schreibweise
# `[ -n "$(report_file …)" ]` las sich wie eine Datei-Existenz-Prüfung (nothra/tch-gastro-services#312 Review-Nitpick).
assert_true "$(grep -qF -- 'if is_report_skill "$skill" "$task_id"; then' "$PIPELINE"; echo $?)" \
  "#312 AK9: run_skill() verzweigt über is_report_skill aus der Lib"
assert_true "$(! grep -qF -- '[ -n "$(report_file "$skill" "$task_id")" ]' "$PIPELINE"; echo $?)" \
  "#312 AK9: keine als Existenz-Prüfung lesbare report_file-Verzweigung mehr"
# Die Erfolgsmeldung materialisiert den Verdict einmal im Rumpf von run_skill(), statt ihn per
# eingebetteter Command Substitution im Meldungstext neu zu lesen (nothra/tch-gastro-services#312 Review-Runde-1-Nitpick
# N1). Gezählt werden die report_verdict-Aufrufe IM per awk extrahierten Rumpf von run_skill() –
# ein Abwesenheits-Guard auf das Fragment `Verdict '$(report_verdict` koppelte Meldungstext und
# Code-Konstrukt: eine umformulierte Meldung mit erneut eingebetteter Command Substitution wäre
# grün geblieben (Fragment-Falle aus Lesson factory-workflow.md, nothra/tch-gastro-services#114, in der
# Abwesenheits-Richtung; nothra/tch-gastro-services#312 Review-Runde-2-Nitpick). Die Zählung ist in beide Richtungen
# fail-closed für diesen Rumpf-Ausschnitt: eine zu kurze Extraktion liefert 0 Treffer, eine über
# das Funktionsende hinausreichende mehr als einen. Sie ist blind für report_is_fresh_and_valid()
# außerhalb von run_skill() – die liest den Verdict für die Bedingung separat noch einmal, macht
# zwei report_verdict-Aufrufe pro Versuch insgesamt (nothra/tch-gastro-services#312 Review-Runde-3-Finding W1).
run_skill_body_312() { awk '/^run_skill\(\) \{/ { inside = 1 } inside { print } inside && /^\}/ { exit }' "$1"; }
runskill_body_312="$(run_skill_body_312 "$PIPELINE")"
assert_true "$(printf '%s\n' "$runskill_body_312" | grep -qF 'for attempt in 1 2 3; do'; echo $?)" \
  "#312: die Rumpf-Extraktion trifft wirklich run_skill() (Retry-Schleife enthalten)"
assert_true "$([ "$(printf '%s\n' "$runskill_body_312" | grep -c 'report_verdict')" -eq 1 ]; echo $?)" \
  "#312: run_skill() materialisiert den Verdict im eigenen Rumpf genau einmal (keine zweite Command Substitution im Meldungstext; report_is_fresh_and_valid() liest ihn separat)"

# AK5 (Reihenfolge): Die Interrupt-Prüfung des Exit-0-Pfads steht VOR der Frische-/
# Verdict-Auswertung – verglichen werden Zeilennummern zweier exakter Zeilen, keine zwei
# isolierten Präsenz-Checks (Lesson testing.md, nothra/tch-gastro-services#286). Den Verhaltensbeweis samt Mutation
# liefert der E2E-Block unten.
ic_first_line_312() { grep -nF -- "$IC_CALL_PIPE" "$1" | head -1 | cut -d: -f1; }
guard_line_312()    { grep -nF -- "$GUARD_CALL_PIPE" "$1" | head -1 | cut -d: -f1; }
assert_true "$([ "$(ic_first_line_312 "$PIPELINE")" -lt "$(guard_line_312 "$PIPELINE")" ]; echo $?)" \
  "#312 AK5: die Interrupt-Prüfung des Exit-0-Pfads läuft vor der Frische-/Verdict-Prüfung"

echo ""
echo "#312 AK8/AK12: Security-Gate ist fail-closed gegen PASSED:"

assert_true "$(grep -qF -- "$GATE_CMP_312" "$PIPELINE"; echo $?)" \
  "#312 AK8: das Gate vergleicht gegen PASSED (blockiert alles andere), nicht nur gegen NEEDS_FIXES"
# Mutationsbeleg zum Anker: dieselbe grep-Assertion gegen eine run-pipeline.sh mit der alten
# NEEDS_FIXES-Polarität. Ohne ihn belegte der Check oben nur, dass die Zeile existiert.
TMP_GATE_312="$(mktemp -d)"
sed 's/\[ "\$SECURITY_VERDICT" != "PASSED" \]/[ "$SECURITY_VERDICT" = "NEEDS_FIXES" ]/' \
  "$PIPELINE" > "$TMP_GATE_312/mutant.sh"
cmp -s "$PIPELINE" "$TMP_GATE_312/mutant.sh"
assert_true "$([ $? -ne 0 ]; echo $?)" \
  "#312 AK12: Mutation greift wirklich (Gate auf die alte NEEDS_FIXES-Polarität zurückgedreht)"
assert_true "$(! grep -qF -- "$GATE_CMP_312" "$TMP_GATE_312/mutant.sh"; echo $?)" \
  "#312 AK12 (Mutation): die alte Polarität macht den Anker oben rot – er ist kausal"
rm -rf "$TMP_GATE_312"

echo ""
echo "#312 E2E: Exit 0 mit stale oder verdictlosem Report ist kein Erfolg:"

NOVERDICT_MSG_312='kein eindeutiger Verdict aus diesem Aufruf'
SEC_GATE_MSG_312='Kritische Security-Findings müssen manuell behoben werden'

if [ "$HAS_YQ" = 1 ]; then
  # ── AK1/AK6/AK7/AK10 (Kern): committeter APPROVED aus einem früheren Pipeline-Lauf,
  # /review endet mit EXIT 0, ohne den Report zu berühren. Vor dem Fix verließ die Pipeline
  # damit den Review-Loop, ohne dass in diesem Lauf ein Review stattfand.
  # Der Stub bedient zusätzlich security-review – nicht für diesen Lauf (er stirbt in Phase 2),
  # sondern damit der Mutant unten nicht an einer ZWEITEN Ursache scheitert und der
  # Beleg dadurch aus dem falschen Grund grün würde (Lesson testing.md, nothra/tch-gastro-services#214).
  TMP_A312="$(mktemp -d)"
  scaffold_310 "$TMP_A312" 330
  printf '## Empfehlung\nAPPROVED\naus einem früheren Pipeline-Lauf\n' > "$TMP_A312/tasks/review-330.md"
  cat > "$TMP_A312/bin/claude" <<'STUB_A312'
#!/bin/sh
case "$*" in
  *SKILL-security-review*)
    printf '## Ergebnis\nPASSED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/security-330.md" ;;
esac
exit 0
STUB_A312
  chmod +x "$TMP_A312/bin/claude"
  commit_310 "$TMP_A312"
  run_310 "$TMP_A312" 330
  assert_exit 1 "$RC_310" "#312 AK1: Exit 0 + stale APPROVED → Fehlversuch (exit 1)"
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#312 AK6: Abbruch über den bestehenden Retry-Pfad (drei Versuche)"
  assert_absent "$OUT_310" "Circuit Breaker ausgelöst" \
    "#312 AK6: kein Circuit-Breaker-Abbruch (exit 2) für den Exit-0-Fehlversuch"
  assert_contains_286 "$OUT_310" "$STALE_MSG_310" \
    "#312 AK1: die Meldung benennt den stale Verdict als Grund"
  assert_absent "$OUT_310" "Review bestanden" \
    "#312 AK1: der Review-Loop wird nicht mit dem alten APPROVED verlassen"
  assert_absent "$OUT_310" "Phase 3" \
    "#312 AK1: die Pipeline arbeitet nicht mit dem stale Verdict weiter"
  assert_absent "$OUT_310" "$FRESH_MSG_310" \
    "#312 AK10: der Exit-0-Fehlversuch wird nicht als tolerierte Turn-Limit-Lage gemeldet"
  assert_contains_286 "$OUT_310" "Phase 2" \
    "#312 AK7: /implement bleibt mit Exit 0 erfolgreich, obwohl ein stale Report vorliegt"

  # ── AK11 (Mutationsbeleg zu AK1): dieselben Assert-Ausdrücke gegen eine run-pipeline.sh,
  # in der NUR der Frische-Vergleich der Hilfsfunktion entfernt ist (durch `true` ersetzt,
  # damit die Verdict-Prüfung als einzige Bedingung übrig bleibt).
  TMP_MA312="$(mktemp -d)"
  scaffold_310 "$TMP_MA312" 330
  awk -v cmp="$FRESH_CMP_PIPE" 'index($0, cmp) > 0 { print "  true"; next } { print }' \
    "$PIPELINE" > "$TMP_MA312/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$FRESH_CMP_PIPE" "$TMP_MA312/scripts/run-pipeline.sh")" -eq 0 ]; echo $?)" \
    "#312 AK11: Mutation greift wirklich (Frische-Vergleich aus der Hilfsfunktion entfernt)"
  printf '## Empfehlung\nAPPROVED\naus einem früheren Pipeline-Lauf\n' > "$TMP_MA312/tasks/review-330.md"
  cp "$TMP_A312/bin/claude" "$TMP_MA312/bin/claude"
  commit_310 "$TMP_MA312"
  run_310 "$TMP_MA312" 330
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#312 AK11 (Mutation): ohne Frische-Vergleich gilt der Exit-0-Aufruf wieder als Erfolg"
  assert_absent "$OUT_310" "$STALE_MSG_310" \
    "#312 AK11 (Mutation): ohne Frische-Vergleich entfällt die Stale-Meldung – der Check oben ist kausal"
  assert_contains_286 "$OUT_310" "Phase 3" \
    "#312 AK11 (Mutation): ohne Frische-Vergleich verlässt die Pipeline den Review-Loop mit dem alten APPROVED"
  rm -rf "$TMP_MA312" "$TMP_A312"

  # ── AK2/AK7/AK8 (Regression Erfolgs-Pfad): review und security-review schreiben ihren
  # Report IM Aufruf und enden mit Exit 0 → weiterhin Erfolg. Divergenzerzeugende Ausgangslage
  # sind die vorbestehenden Reports mit dem GEGENTEILIGEN Verdict (Lesson testing.md, nothra/tch-gastro-services#253):
  # ohne sie könnte der Lauf auch aus einer stehengebliebenen Datei grün sein.
  TMP_B312="$(mktemp -d)"
  scaffold_310 "$TMP_B312" 331
  printf '## Empfehlung\nNEEDS_REWORK\naus einem früheren Lauf\n' > "$TMP_B312/tasks/review-331.md"
  printf '## Ergebnis\nNEEDS_FIXES\naus einem früheren Lauf\n' > "$TMP_B312/tasks/security-331.md"
  cat > "$TMP_B312/bin/claude" <<'STUB_B312'
#!/bin/sh
case "$*" in
  *SKILL-security-review*)
    printf '## Ergebnis\nPASSED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/security-331.md" ;;
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/review-331.md" ;;
esac
exit 0
STUB_B312
  chmod +x "$TMP_B312/bin/claude"
  commit_310 "$TMP_B312"
  run_310 "$TMP_B312" 331
  assert_contains_286 "$OUT_310" "Review bestanden" \
    "#312 AK2: im Aufruf geschriebener Report + Exit 0 bleibt Erfolg (Review-Loop verlassen)"
  assert_absent "$OUT_310" "$STALE_MSG_310" \
    "#312 AK2: kein Stale-Verdikt bei verändertem Report"
  assert_absent "$OUT_310" "$FRESH_MSG_310" \
    "#312 AK10: die Exit-0-Erfolgsmeldung bleibt von der Turn-Limit-Toleranz unterscheidbar"
  assert_contains_286 "$OUT_310" "Phase 4" \
    "#312 AK7: test/refactor laufen mit Exit 0 unverändert durch"
  assert_contains_286 "$OUT_310" "Phase 6" \
    "#312 AK8: ein eindeutiges PASSED passiert das umgedrehte Security-Gate"
  assert_absent "$OUT_310" "$SEC_GATE_MSG_312" \
    "#312 AK8: das Gate blockiert bei eindeutigem PASSED nicht"
  rm -rf "$TMP_B312"

  # ── AK12 (zweite erreichbare Gate-Richtung): /security-review schreibt IM Aufruf einen
  # Report mit eindeutigem NEEDS_FIXES → run_skill() gilt als Erfolg (frisch UND gültig),
  # das UNMUTIERTE Gate blockiert danach mit exit 1. Der Polaritätswechsel darf genau diesen
  # Fall nicht verändern (Spec-312, Fehlerszenarien) – belegt war bisher nur die
  # PASSED-Richtung (TMP_B312) und der leere Verdict am mutierten Skript.
  # Divergenzerzeugende Ausgangslage wie in TMP_B312: der vorbestehende Report trägt den
  # GEGENTEILIGEN Verdict (Lesson testing.md, nothra/tch-gastro-services#253) – ohne ihn könnte der Lauf auch aus einer
  # stehengebliebenen Datei blockieren, statt aus dem in diesem Aufruf geschriebenen Verdict.
  TMP_F312="$(mktemp -d)"
  scaffold_310 "$TMP_F312" 335
  printf '## Ergebnis\nPASSED\naus einem früheren Lauf\n' > "$TMP_F312/tasks/security-335.md"
  cat > "$TMP_F312/bin/claude" <<'STUB_F312'
#!/bin/sh
case "$*" in
  *SKILL-security-review*)
    printf '## Ergebnis\nNEEDS_FIXES\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/security-335.md" ;;
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/review-335.md" ;;
esac
exit 0
STUB_F312
  chmod +x "$TMP_F312/bin/claude"
  commit_310 "$TMP_F312"
  run_310 "$TMP_F312" 335
  assert_exit 1 "$RC_310" \
    "#312 AK12: frischer, eindeutiger NEEDS_FIXES blockiert am Gate (exit 1)"
  assert_contains_286 "$OUT_310" "$SEC_GATE_MSG_312" \
    "#312 AK12: die Security-Meldung benennt den Grund des Abbruchs"
  assert_contains_286 "$OUT_310" "Security Review: NEEDS_FIXES" \
    "#312 AK12: die Meldung nennt den gelesenen Verdict (nicht 'kein eindeutiger Verdict')"
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#312 AK12: der Abbruch kommt vom Gate, nicht aus dem Retry-Pfad von run_skill"
  assert_absent "$OUT_310" "Phase 6" \
    "#312 AK12: mit NEEDS_FIXES wird Codify nicht erreicht"

  # ── Mutationsbeleg zu AK12: dieselben Assert-Ausdrücke gegen eine run-pipeline.sh, in der
  # NUR die Gate-Bedingung nie zutrifft (`if false`). RED-vor-GREEN ist hier nicht möglich –
  # das Verhalten existiert bereits, es fehlte die Abdeckung –, deshalb tritt die Mutation an
  # seine Stelle: ohne das Gate läuft derselbe Lauf bis Phase 6 durch.
  # Ersetzt statt gelöscht (wie beim AK5-Mutanten): eine Löschung ließe `then`/`fi` ohne
  # Bedingung zurück und belegte nur einen Syntaxfehler.
  TMP_MF312="$(mktemp -d)"
  scaffold_310 "$TMP_MF312" 335
  awk -v cmp="$GATE_CMP_312" 'index($0, cmp) > 0 { print "  if false; then"; next } { print }' \
    "$PIPELINE" > "$TMP_MF312/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$GATE_CMP_312" "$TMP_MF312/scripts/run-pipeline.sh")" -eq 0 ]; echo $?)" \
    "#312 AK12: Mutation greift wirklich (Gate-Bedingung auf 'if false' gedreht)"
  printf '## Ergebnis\nPASSED\naus einem früheren Lauf\n' > "$TMP_MF312/tasks/security-335.md"
  cp "$TMP_F312/bin/claude" "$TMP_MF312/bin/claude"
  commit_310 "$TMP_MF312"
  run_310 "$TMP_MF312" 335
  assert_absent "$OUT_310" "$SEC_GATE_MSG_312" \
    "#312 AK12 (Mutation): ohne greifendes Gate entfällt die Meldung – der Check oben ist kausal"
  assert_absent "$OUT_310" "Security Review: NEEDS_FIXES" \
    "#312 AK12 (Mutation): ohne greifendes Gate wird der Verdict nicht als Abbruchgrund gemeldet"
  assert_contains_286 "$OUT_310" "Phase 6" \
    "#312 AK12 (Mutation): ohne greifendes Gate läuft die Pipeline mit NEEDS_FIXES weiter"
  rm -rf "$TMP_MF312" "$TMP_F312"

  # ── AK3 (gültiger Verdict verlangt): /security-review schreibt IM Aufruf einen Report,
  # dessen erste Zeile unter dem Anker beide Tokens nennt → mehrdeutig → kein Verdict.
  # Frisch allein genügt nicht; sonst passierte der leere Verdict das Security-Gate.
  TMP_C312="$(mktemp -d)"
  scaffold_310 "$TMP_C312" 332
  cat > "$TMP_C312/bin/claude" <<'STUB_C312'
#!/bin/sh
case "$*" in
  *SKILL-security-review*)
    printf '## Ergebnis\nPASSED oder NEEDS_FIXES - unklar\n' > "$PWD/tasks/security-332.md" ;;
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/review-332.md" ;;
esac
exit 0
STUB_C312
  chmod +x "$TMP_C312/bin/claude"
  commit_310 "$TMP_C312"
  run_310 "$TMP_C312" 332
  assert_exit 1 "$RC_310" \
    "#312 AK3: frisch geschriebener Report ohne eindeutigen Verdict → Fehlversuch (exit 1)"
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#312 AK3: Abbruch im Retry-Pfad von run_skill (nicht erst am Security-Gate)"
  assert_contains_286 "$OUT_310" "$NOVERDICT_MSG_312" \
    "#312 AK3: die Meldung benennt den fehlenden eindeutigen Verdict"
  assert_absent "$OUT_310" "Phase 6" \
    "#312 AK3: das Security-Gate wird nicht mit leerem Verdict passiert"

  # ── Mutationsbeleg zu AK3 – zugleich der Verhaltensbeweis für die durch AK3 unerreichbar
  # gewordene dritte Gate-Richtung (AK12): ohne die Verdict-Gültigkeitsprüfung passiert der
  # leere Verdict run_skill wieder und erreicht das Gate. Das umgedrehte Gate blockiert ihn
  # dort fail-closed – die alte NEEDS_FIXES-Polarität hätte ihn durchgewunken.
  TMP_MC312="$(mktemp -d)"
  scaffold_310 "$TMP_MC312" 332
  awk -v chk="$VERDICT_CHK_PIPE" 'index($0, chk) > 0 { next } { print }' \
    "$PIPELINE" > "$TMP_MC312/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$VERDICT_CHK_PIPE" "$TMP_MC312/scripts/run-pipeline.sh")" -eq 0 ]; echo $?)" \
    "#312 AK3: Mutation greift wirklich (Verdict-Gültigkeitsprüfung entfernt)"
  cp "$TMP_C312/bin/claude" "$TMP_MC312/bin/claude"
  commit_310 "$TMP_MC312"
  run_310 "$TMP_MC312" 332
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#312 AK3 (Mutation): ohne die Gültigkeitsprüfung ist der leere Verdict wieder ein Erfolg"
  assert_absent "$OUT_310" "$NOVERDICT_MSG_312" \
    "#312 AK3 (Mutation): ohne die Gültigkeitsprüfung entfällt die Meldung – der Check oben ist kausal"
  assert_exit 1 "$RC_310" \
    "#312 AK12: leerer Verdict am Security-Gate blockiert fail-closed (exit 1)"
  assert_contains_286 "$OUT_310" "$SEC_GATE_MSG_312" \
    "#312 AK12: die dritte Gate-Richtung (kein eindeutiges PASSED) blockiert behavioral"
  assert_absent "$OUT_310" "Phase 6" \
    "#312 AK12: mit unklarem Verdict wird Codify nicht erreicht"
  rm -rf "$TMP_MC312" "$TMP_C312"

  # ── AK4 (security-review stale): committeter PASSED aus einem früheren Aufruf,
  # /security-review endet mit Exit 0, ohne die Datei zu berühren. Gleiche Richtung wie AK1,
  # andere Report-Datei – und nicht-destruktiv wie in nothra/tch-gastro-services#310.
  TMP_D312="$(mktemp -d)"
  scaffold_310 "$TMP_D312" 333
  printf '## Ergebnis\nPASSED\naus einem früheren Aufruf\n' > "$TMP_D312/tasks/security-333.md"
  cat > "$TMP_D312/bin/claude" <<'STUB_D312'
#!/bin/sh
case "$*" in
  *SKILL-security-review*) : ;;
  *SKILL-review*)
    printf '## Empfehlung\nAPPROVED\nin diesem Aufruf geschrieben\n' > "$PWD/tasks/review-333.md" ;;
esac
exit 0
STUB_D312
  chmod +x "$TMP_D312/bin/claude"
  commit_310 "$TMP_D312"
  cksum_d312_before="$(cksum < "$TMP_D312/tasks/security-333.md")"
  run_310 "$TMP_D312" 333
  assert_exit 1 "$RC_310" "#312 AK4: Exit 0 + stale PASSED → Fehlversuch (exit 1)"
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#312 AK4: Abbruch im Retry-Pfad von run_skill (security-review)"
  assert_contains_286 "$OUT_310" "$STALE_MSG_310" \
    "#312 AK4: die Meldung benennt den stale Security-Verdict"
  assert_absent "$OUT_310" "Phase 6" \
    "#312 AK4: der alte PASSED wird nicht als Ergebnis dieses Laufs gewertet"
  assert_true "$([ "$(cksum < "$TMP_D312/tasks/security-333.md")" = "$cksum_d312_before" ]; echo $?)" \
    "#312 AK4: die Prüfung bleibt nicht-destruktiv (Report inhaltlich unverändert)"
  rm -rf "$TMP_D312"

  # ── AK5 (Interrupt hat Vorrang): Der Versuch signalisiert einen Interrupt und endet mit
  # Exit 0, ohne einen gültigen Verdict zu hinterlassen. Zielfall ist bewusst der
  # „kein Verdict"-Zweig: nur er hat keinen eigenen interrupt-check (der Stale-Zweig hat
  # seit nothra/tch-gastro-services#310 einen), also kann allein die neue Exit-0-Prüfung ihn stoppen – der Testpfad
  # ist damit auf den Zielpfad isoliert (Lesson testing.md, nothra/tch-gastro-services#214).
  TMP_E312="$(mktemp -d)"
  scaffold_310 "$TMP_E312" 334
  cat > "$TMP_E312/bin/claude" <<'STUB_E312'
#!/bin/sh
case "$*" in
  *SKILL-review*)
    bash "$PWD/scripts/raise-interrupt.sh" 334 ADR "Trigger-Kategorie 1: Exit-0-Testfall" >/dev/null
    printf '## Empfehlung\nunklar\n' > "$PWD/tasks/review-334.md" ;;
esac
exit 0
STUB_E312
  chmod +x "$TMP_E312/bin/claude"
  commit_310 "$TMP_E312"
  run_310 "$TMP_E312" 334
  assert_exit 1 "$RC_310" "#312 AK5: signalisierter Interrupt bei Exit 0 stoppt die Pipeline (exit 1)"
  assert_contains_286 "$OUT_310" "[INTERRUPT] ADR: Trigger-Kategorie 1: Exit-0-Testfall" \
    "#312 AK5: der Interrupt wird vor der Frische-/Verdict-Prüfung erkannt"
  assert_absent "$OUT_310" "failed after 3 attempts" \
    "#312 AK5: kein Retry über zwei weitere Heavy-Versuche"
  assert_true "$(grep -qF 'Pipeline pausiert – ADR: Trigger-Kategorie 1: Exit-0-Testfall' \
    "$TMP_E312/tasks/task-334-guard.md"; echo $?)" \
    "#312 AK5: Blocker-Eintrag landet in der Task-Datei"

  # ── Mutationsbeleg zu AK5: dieselben Assert-Ausdrücke gegen eine run-pipeline.sh, in der
  # NUR der Exit-0-Interrupt-Check fehlt. Er ist der ERSTE der drei Aufrufe im Skript; dass
  # die Mutation genau ihn trifft, belegt die Positions-Assertion (der erste verbliebene
  # Aufruf steht danach hinter dem Guard-Aufruf), nicht nur die Anzahl.
  # Ersetzt statt gelöscht: der Aufruf ist der einzige Rumpf seines `if` – eine Löschung
  # ergäbe `if …; then` + `fi` und damit einen Syntaxfehler, der den Lauf schon vor der
  # Zielstelle beendet (die Mutation belegte dann nur Parsing, nicht Kausalität).
  TMP_ME312="$(mktemp -d)"
  scaffold_310 "$TMP_ME312" 334
  awk -v call="$IC_CALL_PIPE" \
    'removed != 1 && index($0, call) > 0 { removed = 1; print "      :"; next } { print }' \
    "$PIPELINE" > "$TMP_ME312/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -cF -- "$IC_CALL_PIPE" "$TMP_ME312/scripts/run-pipeline.sh")" \
    -eq "$(($(grep -cF -- "$IC_CALL_PIPE" "$PIPELINE") - 1))" ]; echo $?)" \
    "#312 AK5: Mutation greift wirklich (genau ein interrupt-check-Aufruf entfernt)"
  assert_true "$([ "$(ic_first_line_312 "$TMP_ME312/scripts/run-pipeline.sh")" \
    -gt "$(guard_line_312 "$TMP_ME312/scripts/run-pipeline.sh")" ]; echo $?)" \
    "#312 AK5: Mutation trifft den Exit-0-Check (erster verbliebener Aufruf liegt hinter dem Guard)"
  cp "$TMP_E312/bin/claude" "$TMP_ME312/bin/claude"
  commit_310 "$TMP_ME312"
  run_310 "$TMP_ME312" 334
  assert_contains_286 "$OUT_310" "failed after 3 attempts" \
    "#312 AK5 (Mutation): ohne den Exit-0-Check laufen alle drei Versuche – der Check oben ist kausal"
  assert_absent "$OUT_310" "[INTERRUPT] ADR: Trigger-Kategorie 1: Exit-0-Testfall" \
    "#312 AK5 (Mutation): ohne den Exit-0-Check bleibt der Interrupt unbemerkt"
  rm -rf "$TMP_ME312" "$TMP_E312"
else
  skip_yq "#312 E2E: Exit-0-Frischeprüfung (AK1–AK8, AK10–AK12)"
fi

# ─── nothra/tch-gastro-services#312 AK13: Doku-Nachzug (ADR-019 §4 + Report-Guard-Lesson) ──────────────
echo ""
echo "#312 AK13: ADR-019 §4 und die Lesson beschreiben die symmetrische Bedingung:"

adr019_flat_312=$(flat_286 "$ADR019_310")
assert_contains_286 "$adr019_flat_312" "auf beiden Rückkehrpfaden" \
  "#312 AK13: ADR-019 §4 beschreibt die Bedingung symmetrisch (Exit 0 und non-zero)"
assert_contains_286 "$adr019_flat_312" "einen eindeutigen Verdict trägt" \
  "#312 AK13: ADR-019 §4 nennt die verlangte Verdict-Gültigkeit"
assert_contains_286 "$adr019_flat_312" "passiert nur ein eindeutiges" \
  "#312 AK13: ADR-019 §4 nennt die neue Gate-Polarität in Phase 5"

workflow_flat_312=$(flat_286 "$WORKFLOW_LESSON")
assert_contains_286 "$workflow_flat_312" "In nothra/tch-gastro-services#312 auf den Exit-0-Pfad ausgeweitet" \
  "#312 AK13: Lesson nennt den Erledigt-Stand der Exit-0-Ausweitung"
assert_contains_286 "$workflow_flat_312" "auf allen Rückkehrpfaden, nicht nur im Fehlerpfad" \
  "#312 AK13: die Lesson-Regel ist um alle Rückkehrpfade geschärft"

# Dieselbe Prosa steht an zwei weiteren Orten, die der erste Sweep übersehen hatte (nothra/tch-gastro-services#312
# Review-Runde-1-Findings): im Modul-Header der Lib – der Datei, die jeder Nutzer der drei
# Funktionen zuerst liest – und in OPERATING.md, das CLAUDE.md als kanonische Quelle des
# prozeduralen Ablaufs benennt. Beide beschrieben weiter die alte, einseitige Mechanik.
rvlib_flat_312=$(flat_286 "$RV_LIB310")
assert_contains_286 "$rvlib_flat_312" "auf BEIDEN Rückkehrpfaden" \
  "#312 AK13: der Lib-Modul-Header beschreibt die Bedingung symmetrisch"
assert_contains_286 "$rvlib_flat_312" "VIER Funktionen" \
  "#312: der zähl-nennende Modul-Header ist beim Hinzufügen von is_report_skill mitgepflegt"

operating_flat_312=$(flat_286 "$OPERATING_MD")
assert_contains_286 "$operating_flat_312" 'nur ein eindeutiges `PASSED`' \
  "#312 AK13: OPERATING.md nennt die neue Gate-Polarität in der Eigenschaften-Liste"
assert_contains_286 "$operating_flat_312" 'ein fehlender oder mehrdeutiger Verdict stoppt genauso' \
  "#312 AK13: OPERATING.md §4.2 nennt den fehlenden/mehrdeutigen Verdict als Stopp-Grund"

# ─── Task 314 (ADR-045): Prozess-Messung real betreiben ──────────────────────
# metrics.sh läuft als Abschluss-Schritt jedes run-pipeline.sh-Laufs (EXIT-Trap, fail-open,
# genau ein Aufrufort) und veröffentlicht optional (--publish) an $GITHUB_STEP_SUMMARY und
# als Kommentar an FACTORY_METRICS_ISSUE. Zwei Test-Gruppen: (A) echte metrics.sh --publish-
# Läufe (AK4-AK10, AK14), (B) echte run-pipeline.sh-Läufe gegen ein Wegwerf-Repo (AK1/AK2/AK3/
# AK11/AK15) – kein Wiring-Grep (AK13).
echo ""
echo "Task 314 (ADR-045): metrics.sh --publish (echte Läufe):"

TMP_314M="$(mktemp -d)"; mkdir -p "$TMP_314M/tasks" "$TMP_314M/bin"

# AK14 (Exit-Code-Fix): vor dem Fix war die letzte Skriptzeile der Wahrheitswert des
# QUIET-Tests und das Skript lief ohne `set -e` – --quiet endete darum mit Exit 1, obwohl der
# Report korrekt geschrieben wurde. Jetzt fest verdrahtet: Exit 0 bei Erfolg.
FACTORY_DIR="$TMP_314M" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet >/dev/null 2>&1
assert_exit 0 "$?" "#314 AK14: metrics.sh --quiet endet mit Exit 0 (vorher: Exit 1)"

# AK5: ohne $GITHUB_STEP_SUMMARY kein Schreibversuch, Lauf bleibt fehlerfrei (--publish gesetzt).
m5_out=$(cd "$TMP_314M" && env -u GITHUB_STEP_SUMMARY -u FACTORY_METRICS_ISSUE \
  FACTORY_DIR="$TMP_314M" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); m5_rc=$?
assert_exit 0 "$m5_rc" "#314 AK5: --publish ohne \$GITHUB_STEP_SUMMARY bleibt fehlerfrei"
assert_absent "$m5_out" 'GITHUB_STEP_SUMMARY angehängt' "#314 AK5: kein Schreibversuch ohne \$GITHUB_STEP_SUMMARY"

# AK4: $GITHUB_STEP_SUMMARY gesetzt und schreibbar -> vollständiger Report-Inhalt angehängt
# (nicht überschrieben – Datei enthält vorher schon einen Marker).
SUMMARY_314="$TMP_314M/summary.md"; printf 'vorher\n' > "$SUMMARY_314"
env -u FACTORY_METRICS_ISSUE FACTORY_DIR="$TMP_314M" GITHUB_STEP_SUMMARY="$SUMMARY_314" \
  bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish >/dev/null 2>&1
assert_exit 0 "$?" "#314 AK4: --publish mit schreibbarem \$GITHUB_STEP_SUMMARY endet mit Exit 0"
grep -qF 'vorher' "$SUMMARY_314" 2>/dev/null
assert_true "$?" "#314 AK4: bestehender Summary-Inhalt bleibt erhalten (angehängt, nicht überschrieben)"
grep -qF '# Factory-Metriken' "$SUMMARY_314" 2>/dev/null
assert_true "$?" "#314 AK4: vollständiger Report-Inhalt steht in \$GITHUB_STEP_SUMMARY"
report_314="$TMP_314M/tasks/metrics-$(date +%Y-%m-%d).md"
diff -q "$report_314" <(tail -n +2 "$SUMMARY_314") >/dev/null 2>&1
assert_true "$?" "#314 AK4: angehängter Teil entspricht 1:1 der Report-Datei"

# Fehlerszenario: $GITHUB_STEP_SUMMARY zeigt auf einen nicht schreibbaren Pfad -> Hinweis,
# kein Abbruch.
UNWRITABLE_314="$TMP_314M/no-such-dir/summary.md"
uw_out=$(env -u FACTORY_METRICS_ISSUE FACTORY_DIR="$TMP_314M" GITHUB_STEP_SUMMARY="$UNWRITABLE_314" \
  bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); uw_rc=$?
assert_exit 0 "$uw_rc" "#314: nicht schreibbares \$GITHUB_STEP_SUMMARY bricht den Lauf nicht ab"
assert_contains_286 "$uw_out" "nicht schreibbar" "#314: nicht schreibbares \$GITHUB_STEP_SUMMARY wird ausgewiesen"

# Fake-gh (loggt Aufrufe) für AK6/AK7/AK8/AK9 – Muster wie TMP_W2 oben.
GHLOG_314="$TMP_314M/gh.log"
cat > "$TMP_314M/bin/gh" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "issue comment") printf '%s\n' "\$*" >> "$GHLOG_314"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP_314M/bin/gh"

# AK7 (kein Ziel -> kein Raten): FACTORY_METRICS_ISSUE nicht gesetzt -> kein gh-Aufruf, Grund
# benannt, kein Ausweichen auf irgendeine andere Nummer.
: > "$GHLOG_314"
ak7_out=$(cd "$TMP_314M" && PATH="$TMP_314M/bin:$PATH" env -u FACTORY_METRICS_ISSUE -u GITHUB_STEP_SUMMARY \
  FACTORY_DIR="$TMP_314M" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); ak7_rc=$?
assert_exit 0 "$ak7_rc" "#314 AK7: metrics.sh --publish ohne FACTORY_METRICS_ISSUE endet mit Exit 0"
assert_true "$([ ! -s "$GHLOG_314" ]; echo $?)" "#314 AK7: kein gh-Aufruf ohne FACTORY_METRICS_ISSUE"
assert_contains_286 "$ak7_out" "FACTORY_METRICS_ISSUE nicht gesetzt" "#314 AK7: übersprungener Schritt wird benannt"

# AK8 (Wert als Daten, fail-closed): nicht-numerischer Wert -> abgelehnt, kein gh-Aufruf.
: > "$GHLOG_314"
ak8_out=$(cd "$TMP_314M" && PATH="$TMP_314M/bin:$PATH" env -u GITHUB_STEP_SUMMARY \
  FACTORY_DIR="$TMP_314M" FACTORY_METRICS_ISSUE="12x" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); ak8_rc=$?
assert_exit 0 "$ak8_rc" "#314 AK8: nicht-numerischer FACTORY_METRICS_ISSUE bricht den Lauf nicht ab"
assert_true "$([ ! -s "$GHLOG_314" ]; echo $?)" "#314 AK8: kein gh-Aufruf bei nicht-numerischem Wert"
assert_contains_286 "$ak8_out" "keine Zahl ('12x')" "#314 AK8: Ablehnungsgrund nennt den abgelehnten Wert"
# Typischer Stolperstein: ein CLI-Flag statt einer Zahl – Config-/nutzerkontrollierte Werte
# als Daten behandeln (clean-code.md), nie als gh-Option.
: > "$GHLOG_314"
env -u GITHUB_STEP_SUMMARY FACTORY_DIR="$TMP_314M" FACTORY_METRICS_ISSUE="--repo" \
  bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish >/dev/null 2>&1
assert_true "$([ ! -s "$GHLOG_314" ]; echo $?)" "#314 AK8: '--repo' wird als Daten behandelt, nicht als gh-Option"

# AK9 (gh nicht verfügbar): FACTORY_METRICS_ISSUE gesetzt, aber kein gh im PATH.
: > "$GHLOG_314"
ak9_out=$(cd "$TMP_314M" && PATH="/usr/bin:/bin" env -u GITHUB_STEP_SUMMARY \
  FACTORY_DIR="$TMP_314M" FACTORY_METRICS_ISSUE="42" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); ak9_rc=$?
assert_exit 0 "$ak9_rc" "#314 AK9: fehlendes gh bricht den Lauf nicht ab (local-first)"
assert_contains_286 "$ak9_out" "gh nicht verfügbar" "#314 AK9: Kommentar-Übersprung wird ausgewiesen"

# AK6 (Kommentar-Weg): FACTORY_METRICS_ISSUE gesetzt, gh verfügbar+authentifiziert -> Kommentar
# an GENAU diese Issue, Body über --body-file (nicht als Argument-String).
: > "$GHLOG_314"
ak6_out=$(cd "$TMP_314M" && PATH="$TMP_314M/bin:$PATH" env -u GITHUB_STEP_SUMMARY \
  FACTORY_DIR="$TMP_314M" FACTORY_METRICS_ISSUE="42" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); ak6_rc=$?
assert_exit 0 "$ak6_rc" "#314 AK6: erfolgreicher Kommentar-Weg endet mit Exit 0"
assert_true "$([ -s "$GHLOG_314" ]; echo $?)" "#314 AK6: gh issue comment wurde aufgerufen"
grep -qF -- 'issue comment 42' "$GHLOG_314" 2>/dev/null
assert_true "$?" "#314 AK6: Kommentar geht an die konfigurierte Issue-Nummer (42)"
grep -qF -- '--body-file' "$GHLOG_314" 2>/dev/null
assert_true "$?" "#314: Body wird über --body-file übergeben, nicht als Argument-String"
assert_contains_286 "$ak6_out" "Issue #42 gepostet" "#314 AK6: Erfolg wird ausgewiesen"

# Fehlerszenario (Spec-314): `gh issue comment` selbst schlägt fehl (Netzwerk, fehlendes Recht,
# gelöschte Issue) – gh ist verfügbar+authentifiziert (anders als AK9), aber der Kommentar-
# Aufruf scheitert. Hinweis, kein Abbruch, Report-Datei bleibt unverändert erhalten.
cat > "$TMP_314M/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue comment") exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP_314M/bin/gh"
report_before_314=$(cat "$report_314" 2>/dev/null)
ghfail_out=$(cd "$TMP_314M" && PATH="$TMP_314M/bin:$PATH" env -u GITHUB_STEP_SUMMARY \
  FACTORY_DIR="$TMP_314M" FACTORY_METRICS_ISSUE="42" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet --publish 2>&1); ghfail_rc=$?
assert_exit 0 "$ghfail_rc" "#314: fehlschlagender gh-issue-comment-Aufruf bricht den Lauf nicht ab"
assert_contains_286 "$ghfail_out" "Issue-Kommentar an #42 fehlgeschlagen" "#314: Fehlschlag wird ausgewiesen"
assert_true "$([ "$(cat "$report_314" 2>/dev/null)" = "$report_before_314" ]; echo $?)" \
  "#314: Report-Datei bleibt bei fehlschlagendem Kommentar-Versuch unverändert erhalten"

# AK10 (manuell, gleiche Wege): ohne --publish bleibt das heutige Verhalten unverändert - kein
# gh-/Summary-Versuch, auch wenn beide Ziele gesetzt sind. AK4-AK9 selbst laufen oben bereits
# über denselben Code-Pfad, den auch der manuelle Aufruf nutzt (eine Implementierung, ADR-045).
: > "$GHLOG_314"
FACTORY_DIR="$TMP_314M" GITHUB_STEP_SUMMARY="$UNWRITABLE_314" FACTORY_METRICS_ISSUE="42" \
  PATH="$TMP_314M/bin:$PATH" bash "$SCRIPTS_DIR/metrics.sh" --no-api --quiet >/dev/null 2>&1
assert_true "$([ ! -s "$GHLOG_314" ]; echo $?)" "#314 AK10: ohne --publish kein gh-Aufruf trotz gesetztem FACTORY_METRICS_ISSUE"

rm -rf "$TMP_314M"

if [ "$HAS_YQ" = 1 ]; then
  echo ""
  echo "Task 314 (ADR-045) E2E: Prozess-Metriken-Trap in run-pipeline.sh (echte Läufe):"

  # Reihenfolge-Guard (ADR-045 Implementierungs-Hinweis): der Trap muss NACH preflight_checks
  # registriert sein – Positionsvergleich der beiden echten Zeilen, kein Präsenz-Grep (Lesson
  # factory-workflow.md, "Reihenfolge-/Präsenz-Guards: Kommando ≠ Prosa-Erwähnung").
  preflight_call_line_314=$(grep -n '^preflight_checks$' "$PIPELINE" | head -1 | cut -d: -f1)
  trap_line_314=$(grep -n 'trap measure_process_metrics_on_exit EXIT' "$PIPELINE" | head -1 | cut -d: -f1)
  assert_true "$([ -n "$preflight_call_line_314" ] && [ -n "$trap_line_314" ] && [ "$trap_line_314" -gt "$preflight_call_line_314" ]; echo $?)" \
    "#314: Trap-Registrierung steht NACH dem preflight_checks-Aufruf"

  # commit_314_pushed <dir> <origin> – wie commit_310 (oben, nothra/tch-gastro-services#310-Block), zusätzlich MIT
  # gepushtem origin-Remote: die Endzustands-Verifikation (ADR-040) verlangt "sauber, gepusht"
  # für ein grünes Ende – ohne Remote bräche AK1/AK3 schon dort ab, nicht an der Messung.
  commit_314_pushed() {
    local dir="$1" origin="$2" br
    git init --bare -q "$origin"
    commit_310 "$dir"
    br="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
    git -C "$dir" remote add origin "$origin"
    git -C "$dir" push -q origin "$br"
  }

  run_314() {
    local dir="$1" task_id="$2"; shift 2
    OUT_314=$(cd "$dir" && PATH="$dir/bin:$PATH" \
      FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
      env -u PR_SHEPHERD -u FACTORY_STAGE -u FACTORY_METRICS_ISSUE -u GITHUB_STEP_SUMMARY \
      bash "$dir/scripts/run-pipeline.sh" "$task_id" "$@" 2>&1); RC_314=$?
  }

  # ── AK1: regulärer, grüner Lauf -> Messabschnitt erscheint GENAU einmal, Erfolg bleibt.
  TMP_314A="$(mktemp -d)"; TMP_314A_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_314A" 900
  cat > "$TMP_314A/bin/claude" <<'STUB_314A'
#!/bin/sh
case "$*" in
  *SKILL-security-review*) printf '## Ergebnis\nPASSED\n' > "$PWD/tasks/security-900.md" ;;
  *SKILL-review*)          printf '## Empfehlung\nAPPROVED\n' > "$PWD/tasks/review-900.md" ;;
esac
exit 0
STUB_314A
  chmod +x "$TMP_314A/bin/claude"
  commit_314_pushed "$TMP_314A" "$TMP_314A_ORIGIN"
  run_314 "$TMP_314A" 900
  assert_exit 0 "$RC_314" "#314 AK1: regulärer Lauf endet weiterhin mit Exit 0"
  ak1_count=$(printf '%s' "$OUT_314" | grep -c '→ Prozess-Metriken erheben')
  assert_true "$([ "$ak1_count" -eq 1 ]; echo $?)" "#314 AK1: Messung läuft genau einmal (ein erkennbarer Messabschnitt)"
  assert_contains_286 "$OUT_314" "Prozess-Metriken erhoben" "#314 AK1: der Lauf gibt einen erkennbaren Erfolg der Messung aus"
  assert_contains_286 "$OUT_314" "Pipeline erfolgreich abgeschlossen" "#314 AK1: der reguläre Erfolg bleibt unberührt"
  rm -rf "$TMP_314A" "$TMP_314A_ORIGIN"

  # ── AK2: Abbruch (implement scheitert dreimal) -> Messung läuft trotzdem GENAU einmal,
  # ursprünglicher Exit-Code (1, aus dem bestehenden "failed after 3 attempts"-Pfad) bleibt.
  TMP_314B="$(mktemp -d)"
  scaffold_310 "$TMP_314B" 901
  printf '#!/bin/sh\nexit 1\n' > "$TMP_314B/bin/claude"; chmod +x "$TMP_314B/bin/claude"
  commit_310 "$TMP_314B"
  run_314 "$TMP_314B" 901
  assert_exit 1 "$RC_314" "#314 AK2: ursprünglicher Exit-Code (1) bleibt nach dem abgebrochenen Lauf erhalten"
  assert_contains_286 "$OUT_314" "failed after 3 attempts" "#314 AK2: der Abbruch selbst läuft wie zuvor (Retry-Pfad unverändert)"
  ak2_count=$(printf '%s' "$OUT_314" | grep -c '→ Prozess-Metriken erheben')
  assert_true "$([ "$ak2_count" -eq 1 ]; echo $?)" "#314 AK2: Messung läuft auch bei Abbruch genau einmal"
  rm -rf "$TMP_314B"

  # ── AK2 (Mutationsbeleg): OHNE die Trap-Registrierung läuft dieselbe Abbruch-Fixture ohne
  # Messabschnitt – belegt, dass der Test oben wirklich die Trap-Mechanik prüft (Lesson
  # testing.md, Mutationsbeleg-Pflicht bei Positivbelegen), nicht nur den vorbestehenden
  # Retry-Pfad aus nothra/tch-gastro-services#310/#312.
  TMP_314B2="$(mktemp -d)"
  scaffold_310 "$TMP_314B2" 901
  awk '/^trap measure_process_metrics_on_exit EXIT$/{next} {print}' "$PIPELINE" > "$TMP_314B2/scripts/run-pipeline.sh"
  assert_true "$([ "$(grep -c 'trap measure_process_metrics_on_exit EXIT' "$TMP_314B2/scripts/run-pipeline.sh")" -eq 0 ]; echo $?)" \
    "#314 AK2: Mutation greift wirklich (Trap-Registrierung entfernt)"
  printf '#!/bin/sh\nexit 1\n' > "$TMP_314B2/bin/claude"; chmod +x "$TMP_314B2/bin/claude"
  commit_310 "$TMP_314B2"
  run_314 "$TMP_314B2" 901
  assert_exit 1 "$RC_314" "#314 AK2 (Mutation): Abbruch-Exit-Code bleibt unabhängig von der Trap-Mechanik (1)"
  assert_absent "$OUT_314" "Prozess-Metriken erheben" "#314 AK2 (Mutation): ohne Trap läuft KEINE Messung – der Test oben ist kausal"
  rm -rf "$TMP_314B2"

  # ── AK3 (fail-open): metrics.sh fehlt -> ein ansonsten grüner Lauf bleibt Exit 0, Hinweis
  # auf die übersprungene Messung erscheint.
  TMP_314C="$(mktemp -d)"; TMP_314C_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_314C" 902
  rm -f "$TMP_314C/scripts/metrics.sh"
  cat > "$TMP_314C/bin/claude" <<'STUB_314C'
#!/bin/sh
case "$*" in
  *SKILL-security-review*) printf '## Ergebnis\nPASSED\n' > "$PWD/tasks/security-902.md" ;;
  *SKILL-review*)          printf '## Empfehlung\nAPPROVED\n' > "$PWD/tasks/review-902.md" ;;
esac
exit 0
STUB_314C
  chmod +x "$TMP_314C/bin/claude"
  commit_314_pushed "$TMP_314C" "$TMP_314C_ORIGIN"
  run_314 "$TMP_314C" 902
  assert_exit 0 "$RC_314" "#314 AK3: fehlendes metrics.sh färbt einen grünen Lauf nicht rot (fail-open)"
  assert_contains_286 "$OUT_314" "übersprungen (fail-open)" "#314 AK3: die übersprungene Messung wird ausgewiesen"
  assert_contains_286 "$OUT_314" "Pipeline erfolgreich abgeschlossen" "#314 AK3: der reguläre Erfolg bleibt trotz fehlgeschlagener Messung erhalten"
  rm -rf "$TMP_314C" "$TMP_314C_ORIGIN"

  # ── AK11 (dry-run): nichts wird veröffentlicht, übersprungene Messung wird ausgewiesen.
  TMP_314D="$(mktemp -d)"
  _mk_pipe_repo "$TMP_314D"
  echo "# Task 903: dry" > "$TMP_314D/tasks/task-903-dry.md"
  git -C "$TMP_314D" init -q
  git -C "$TMP_314D" config user.email t@t; git -C "$TMP_314D" config user.name t
  git -C "$TMP_314D" add . >/dev/null 2>&1; git -C "$TMP_314D" commit -q -m init
  dryrun_out_314=$(cd "$TMP_314D" && bash "$TMP_314D/scripts/run-pipeline.sh" 903 --dry-run 2>&1)
  assert_contains_286 "$dryrun_out_314" "[DRY-RUN] Prozess-Metriken übersprungen" "#314 AK11: --dry-run weist die übersprungene Messung aus"
  assert_absent "$dryrun_out_314" "Prozess-Metriken erhoben" "#314 AK11: --dry-run misst/veröffentlicht nicht wirklich"
  rm -rf "$TMP_314D"

  # ── AK15: factory-poll.yml gewährt die zwei zusätzlichen Read-Scopes für die API-Kennzahlen.
  poll_permission_guard "$POLL_YML" 'pull-requests: read'
  assert_true "$?" "#314 AK15: factory-poll.yml gewährt pull-requests: read (Lead-Time)"
  poll_permission_guard "$POLL_YML" 'actions: read'
  assert_true "$?" "#314 AK15: factory-poll.yml gewährt actions: read (CI-Quote)"
else
  skip_yq "#314 E2E: Prozess-Metriken-Trap in run-pipeline.sh"
fi

# ─── nothra/tch-gastro-services#314 AK12: Doku ohne Drift (CLAUDE.md, daily-metrics.md, OPERATING.md) ──────────────────
echo ""
echo "#314 AK12: Doku beschreibt die Messung als Bestandteil jedes Pipeline-Laufs:"

claude_md_flat_314=$(flat_286 "$CLAUDE_MD")
assert_contains_286 "$claude_md_flat_314" 'läuft automatisch als Abschluss-Schritt' \
  "#314 AK12: FACTORY.md beschreibt die Messung als automatischen Pipeline-Bestandteil"
assert_contains_286 "$claude_md_flat_314" 'FACTORY_METRICS_ISSUE' \
  "#314 AK12: FACTORY.md nennt FACTORY_METRICS_ISSUE als Veröffentlichungs-Ziel"

DAILY_METRICS_MD="$FACTORY_ROOT/.claude/commands/daily-metrics.md"
daily_metrics_flat_314=$(flat_286 "$DAILY_METRICS_MD")
assert_contains_286 "$daily_metrics_flat_314" 'Läuft bereits automatisch (ADR-045' \
  "#314 AK12: daily-metrics.md nennt sich nicht länger als ausschließlich manuellen Weg"
assert_contains_286 "$daily_metrics_flat_314" 'metrics.sh --publish' \
  "#314 AK12: daily-metrics.md beschreibt den --publish-Schalter"

operating_flat_314=$(flat_286 "$OPERATING_MD")
assert_contains_286 "$operating_flat_314" 'Läuft automatisch (ADR-045' \
  "#314 AK12: OPERATING.md §5.2 beschreibt die Messung als automatischen Pipeline-Bestandteil"
assert_contains_286 "$operating_flat_314" 'pull-requests: read' \
  "#314 AK12: OPERATING.md nennt den erweiterten factory-poll.yml-Scope (AK15)"

# ─── nothra/tch-gastro-services#315: Aspekt-Label factory-pipeline ─────────────────────────────────────
# Entfällt im Factory-Repo: das Label trennt in adoptierenden Projekten „Werkzeug vs. Produkt"; im
# Factory-Repo ist alles Factory-Arbeit (labels.aspects_extra ist leer, siehe PROJECT-CONTEXT.md).

# ─── nothra/tch-gastro-services#319: Deckel für den @import-Dauerkontext (ADR-047 §4) ──────────────────
echo ""
echo "#319 @import-Kontext-Deckel (ADR-047):"

IMPORT_CHECK="$CHECKS_DIR/import-context-limit-check.sh"
assert_true "$([[ -f "$IMPORT_CHECK" ]]; echo $?)" "#319: import-context-limit-check.sh vorhanden"

# Der Realstand-Test (Deckel gegen den ECHTEN Repo-Stand) lebt nicht hier: die Größe des
# Konsumenten-Kontexts ist Projekt-QS, keine Factory-Funktionsprüfung (Factory-Issue #32,
# Realstand in scripts/project/tests/run-tests.sh). Diese Suite prüft das Deckel-Verhalten
# ausschließlich gegen Fixtures; der Guard „#28 AK6" bewacht, dass kein Aufruf gegen die echte Wurzel zurückkehrt.

# Grenze UND Herleitungs-Basis aus dem Skript lesen, statt sie im Test zu duplizieren – sonst
# driften beide, und ein Bump der Konstante bliebe unbemerkt grün.
IC_LIMIT_319="$(sed -n 's/^MAX_IMPORT_LINES=\([0-9]*\).*/\1/p' "$IMPORT_CHECK" | head -1)"
IC_BASIS_319="$(sed -n 's/^# = \([0-9]*\) Zeilen.*/\1/p' "$IMPORT_CHECK" | head -1)"
assert_true "$([ -n "$IC_LIMIT_319" ] && [ "$IC_LIMIT_319" -gt 0 ]; echo $?)" \
  "#319: MAX_IMPORT_LINES ist als Konstante im Skript lesbar"
assert_true "$([ -n "$IC_BASIS_319" ] && [ "$IC_BASIS_319" -gt 0 ]; echo $?)" \
  "#319: die Herleitungs-Basis ist aus dem Kommentar lesbar"

# Herleitung als Kommentar an der Konstante (ADR-047 §4: keine Magic Number). Der Anker muss
# eine Phrase treffen, die NUR im Kommentarblock steht – das Wort „Herleitung" allein steht auch
# in der Remediation-Ausgabe, die Assertion wäre dann überclaimt (Lesson nothra/tch-gastro-services#312: das Label darf nur
# behaupten, was der Prüfausdruck abdeckt).
IC_SRC_319="$(flat_286 "$IMPORT_CHECK")"
assert_contains_286 "$IC_SRC_319" "Herleitung (ADR-047 §4" \
  "#319: Konstante trägt die Herleitung als Kommentar (Anker nur im Kommentarblock)"
assert_contains_286 "$IC_SRC_319" "25 % Puffer" "#319: Herleitung nennt den Puffer (25 %)"
# Die Herleitung muss die Konstante auch RECHNERISCH tragen: Basis + 25 %, aufgerundet auf 50.
# Beide Werte kommen aus dem Skript – der Test hält nur die Rechenregel, keine Zahl.
ic_expected_319=$(( ((IC_BASIS_319 * 125 / 100) + 49) / 50 * 50 ))
assert_true "$([ "$IC_LIMIT_319" -eq "$ic_expected_319" ]; echo $?)" \
  "#319: MAX_IMPORT_LINES ($IC_LIMIT_319) entspricht der dokumentierten Herleitung ($IC_BASIS_319 + 25 % → $ic_expected_319)"

# Fixture: eigene Projektwurzel; FACTORY_DIR steuert die Wurzel des Checks (wie bei den anderen Drift-Checks).
TMP_IC="$(mktemp -d)"
mkdir -p "$TMP_IC/docs"
ic_319() { FACTORY_DIR="$TMP_IC" bash "$IMPORT_CHECK" 2>&1; }
# mklines_319 <datei> <anzahl> – deterministischer Füllinhalt; `seq` wie an den bestehenden
# Fixture-Stellen der Suite (:3721), keine dritte Schreibweise.
mklines_319() { seq 1 "$2" > "$1"; }
# claude_fixture_319 [zeile…] – Fixture-CLAUDE.md aus 20 Füllzeilen plus den übergebenen Zeilen.
# Die 20 erklären die „21" in den Summen der Test-Labels (Füllzeilen + die Referenz-/Prosa-Zeile);
# sie stehen hier an einer Stelle statt dreizehnmal im Block.
claude_fixture_319() {
  mklines_319 "$TMP_IC/CLAUDE.md" 20
  [ "$#" -eq 0 ] || printf '%s\n' "$@" >> "$TMP_IC/CLAUDE.md"
}

# 1. Unter dem Deckel → exit 0, Ausgabe nennt Summe UND Grenze (sonst ist sie nicht handlungsfähig)
claude_fixture_319 '@docs/a.md'
mklines_319 "$TMP_IC/docs/a.md" 30
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 0 "$ic_rc" "#319: Summe unter der Grenze → exit 0"
assert_contains_286 "$ic_out" "51" "#319: Ausgabe nennt die Ist-Summe (21 + 30 = 51 Zeilen)"
# Fallback-Literal, damit die Assertion bei leerem IC_LIMIT_319 nicht vakuum-grün wird
# (grep -qF "" trifft jede Zeile) – sie soll dann aus dem richtigen Grund rot sein.
assert_contains_286 "$ic_out" "${IC_LIMIT_319:-__MAX_IMPORT_LINES_NICHT_LESBAR__}" \
  "#319: Ausgabe nennt die Grenze"

# 2. Grenzwert-Semantik: der Vergleich ist die EINZIGE Rechenoperation des Skripts, und
#    `-gt` vs. `-ge` unterscheidet sich genau an dieser einen Zeile. Ohne beide Fälle bliebe
#    eine Mutation des Operators unbemerkt grün (testing-standards.md: Boundary Values).
mklines_319 "$TMP_IC/CLAUDE.md" "$IC_LIMIT_319"
ic_319 >/dev/null 2>&1
assert_exit 0 "$?" "#319 Grenzwert: genau MAX_IMPORT_LINES Zeilen sind noch zulässig (exit 0)"
mklines_319 "$TMP_IC/CLAUDE.md" $((IC_LIMIT_319 + 1))
ic_319 >/dev/null 2>&1
assert_exit 1 "$?" "#319 Grenzwert: eine Zeile darüber ist rot (exit 1)"

# 3. Drift-Guard Seite A: CLAUDE.md selbst wächst über die Grenze → rot.
mklines_319 "$TMP_IC/CLAUDE.md" $((IC_LIMIT_319 + 10))
ic_319 >/dev/null 2>&1
assert_exit 1 "$?" "#319 Seite A: CLAUDE.md allein über der Grenze → exit 1 (fail-closed)"

# 4. Drift-Guard Seite B: CLAUDE.md klein, aber eine REFERENZIERTE Datei wächst über die Grenze.
#    Zwei Beiträger, damit auch die Sortierung der breakdown-Liste (größter zuerst) prüfbar ist.
claude_fixture_319 '@docs/a.md' '@docs/klein.md'
mklines_319 "$TMP_IC/docs/a.md" $((IC_LIMIT_319 + 10))
mklines_319 "$TMP_IC/docs/klein.md" 5
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 1 "$ic_rc" "#319 Seite B: referenzierte Datei über der Grenze → exit 1 (fail-closed)"
assert_contains_286 "$ic_out" 'docs/a.md' "#319 Seite B: Ausgabe nennt den Beiträger namentlich"
# Reihenfolge: der größte Beiträger steht vor dem kleinsten (sort -rn), sonst ist die Liste
# bei vielen Dateien nicht handlungsfähig. Positionsvergleich, nicht zwei Präsenz-Checks.
ic_pos_gross=$(printf '%s\n' "$ic_out" | grep -nF 'docs/a.md' | head -1 | cut -d: -f1)
ic_pos_klein=$(printf '%s\n' "$ic_out" | grep -nF 'docs/klein.md' | head -1 | cut -d: -f1)
assert_true "$([ -n "$ic_pos_gross" ] && [ -n "$ic_pos_klein" ] && [ "$ic_pos_gross" -lt "$ic_pos_klein" ]; echo $?)" \
  "#319 Seite B: größter Beiträger steht in der Liste vor dem kleinsten"
rm -f "$TMP_IC/docs/klein.md"

# 5. Summen-Beweis: zwei Dateien, jede allein unter der Grenze, zusammen darüber. Belegt, dass
#    der Check die SUMME prüft und nicht je Datei einzeln (ADR-047 §4: „ein Deckel für beide").
claude_fixture_319 '@docs/a.md' '@docs/b.md'
mklines_319 "$TMP_IC/docs/a.md" $((IC_LIMIT_319 * 2 / 3))
mklines_319 "$TMP_IC/docs/b.md" $((IC_LIMIT_319 * 2 / 3))
ic_319 >/dev/null 2>&1
assert_exit 1 "$?" "#319: zwei je-für-sich zulässige Dateien, zusammen über der Grenze → exit 1"

# 6. Rekursion: @import in einer importierten Datei zählt mit (CLAUDE.md → a.md → b.md).
#    Mutationsbeleg über dieselbe Assertion: ohne den geschachtelten Beitrag läge die Summe
#    unter der Grenze – der Test kann also nur wegen der Rekursion rot werden.
claude_fixture_319 '@docs/a.md'
mklines_319 "$TMP_IC/docs/a.md" 30
printf '@docs/b.md\n' >> "$TMP_IC/docs/a.md"
mklines_319 "$TMP_IC/docs/b.md" $((IC_LIMIT_319 + 10))
ic_319 >/dev/null 2>&1
assert_exit 1 "$?" "#319: geschachtelter @import zählt mit → exit 1"
rm -f "$TMP_IC/docs/b.md"
sed -i.bak '/^@docs\/b.md$/d' "$TMP_IC/docs/a.md" && rm -f "$TMP_IC/docs/a.md.bak"
ic_319 >/dev/null 2>&1
assert_exit 0 "$?" "#319 (Mutation): ohne den geschachtelten Beitrag ist dieselbe Prüfung grün"

# 7. Fail-closed bei unlesbarer Quelle – Seite B: einwortige Referenz-Zeile, Datei fehlt.
claude_fixture_319 '@docs/fehlt.md'
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 1 "$ic_rc" "#319: nicht lesbare Referenz-Zeile → exit 1 (fail-closed, keine Umgehung per Rename)"
assert_contains_286 "$ic_out" 'docs/fehlt.md' "#319: benennt die nicht lesbare Datei"

# 8. Fail-closed – Seite A: die Einstiegsdatei selbst fehlt. Eigener Guard mit eigener Meldung
#    (nicht der Referenz-Zweig): „Referenz in CLAUDE.md korrigieren" wäre als Remediation
#    unbrauchbar, wenn genau diese Datei fehlt. Muster wie bei den anderen Drift-Checks.
rm -f "$TMP_IC/CLAUDE.md"
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 1 "$ic_rc" "#319: fehlende FACTORY.md → exit 1 (fail-closed)"
assert_contains_286 "$ic_out" "Einstiegsdatei" "#319: eigene Meldung für die fehlende Einstiegsdatei"
# Nicht erreichbare Projektwurzel ist ein dritter, unterscheidbarer Fall (analog zu den anderen Drift-Checks).
ic_out="$(FACTORY_DIR="$TMP_IC/gibt-es-nicht" bash "$IMPORT_CHECK" 2>&1)"; ic_rc=$?
assert_exit 1 "$ic_rc" "#319: nicht erreichbare Projektwurzel → exit 1 (fail-closed)"
assert_contains_286 "$ic_out" "Projektwurzel nicht erreichbar" "#319: eigene Meldung für die Projektwurzel"

# 9. Zyklus (a.md importiert CLAUDE.md zurück) terminiert – mit Watchdog, damit ein fehlender
#    seen-Schutz die Suite nicht hängen lässt, sondern rot macht. Der Exit-Code allein genügt
#    NICHT: ein Mutant ohne seen-Dedup terminiert ebenfalls mit 0 und meldet nur eine zu große
#    Summe. Deshalb wird die SUMME assertiert (21 + 31 = 52) – sonst behauptet das Label mehr,
#    als der Ausdruck messen kann (Lesson nothra/tch-gastro-services#312).
claude_fixture_319 '@docs/a.md'
mklines_319 "$TMP_IC/docs/a.md" 30
printf '@CLAUDE.md\n' >> "$TMP_IC/docs/a.md"
IC_CYCLE_OUT_319="$(mktemp)"
( ic_319 > "$IC_CYCLE_OUT_319" 2>&1 ) & ic_pid=$!
( sleep 15; kill -9 "$ic_pid" 2>/dev/null ) & ic_dog=$!
wait "$ic_pid" 2>/dev/null; ic_rc=$?
kill "$ic_dog" 2>/dev/null; wait "$ic_dog" 2>/dev/null
assert_exit 0 "$ic_rc" "#319: zyklischer @import terminiert (kein Hänger)"
assert_contains_286 "$(cat "$IC_CYCLE_OUT_319")" "52 von" \
  "#319: der Zyklus zählt FACTORY.md nur einmal (52 Zeilen, nicht 73)"
rm -f "$IC_CYCLE_OUT_319"

# 10. K1 (Review-Iteration 1+2): ein `@pfad` MITTEN IN PROSA wird von Claude Code geladen –
#     empirisch belegt mit `claude --print`, auch **fett**, _kursiv_ und hinter `>`. Alle diese
#     Formen müssen mitzählen, sonst ist der Deckel per Prosa-Zeile lautlos umgehbar (fail-open
#     gegen die eigene Anforderung aus ADR-047 §4). Je Dekorationsform ein eigener Fall.
mklines_319 "$TMP_IC/docs/gross.md" $((IC_LIMIT_319 + 10))
for ic_deko_319 in 'Siehe @docs/gross.md fuer die Details.' \
                   'Kanonisch ist **@docs/gross.md** – dort nachlesen.' \
                   'Kanonisch ist _@docs/gross.md_ – dort nachlesen.' \
                   '>@docs/gross.md' \
                   'Details in @docs/gross.md.' \
                   'Details in (@docs/gross.md), siehe dort.'; do
  claude_fixture_319 "$ic_deko_319"
  ic_out="$(ic_319)"; ic_rc=$?
  assert_exit 1 "$ic_rc" "#319 K1: Inline-@import zählt mit – Form: $ic_deko_319"
  assert_contains_286 "$ic_out" 'docs/gross.md' "#319 K1: nennt die inline referenzierte Datei ($ic_deko_319)"
done
# Mutationsbeleg über dieselbe Assertion: ohne die Prosa-Zeile ist die Prüfung grün – der Test
# kann also nur wegen des Inline-Treffers rot werden (nicht wegen der 21 Basis-Zeilen).
claude_fixture_319
ic_319 >/dev/null 2>&1
assert_exit 0 "$?" "#319 K1 (Mutation): ohne die Inline-Zeile ist dieselbe Prüfung grün"

# 11. Gegenrichtung zu K1 – Prosa-Token, die auf KEINE Datei zeigen, dürfen weder gezählt noch
#     fail-closed rot werden. Der real wirksame Fall im Repo ist „@importiert" (CLAUDE.md);
#     `@serwist/next` hier bewusst OHNE Klammer, damit das Resolve-Sieb wirklich durchlaufen
#     wird (geklammert scheidet das Token schon am Zeilen-Split aus und prüfte nichts).
claude_fixture_319 'Die Lessons sind bewusst nicht @importiert (ADR-037).' 'Stack: @serwist/next, @neondatabase/serverless und @types/node.'
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 0 "$ic_rc" "#319 K1: Prosa-/npm-Scope-Token ohne Datei-Auflösung lassen den Check grün"
assert_absent "$ic_out" "importiert" "#319 K1: Prosa-Token wird nicht als Referenz gemeldet"
assert_absent "$ic_out" "serwist" "#319 K1: unklammerter npm-Scope wird nicht als Referenz gemeldet"

# 12. Eine Zeile, die mit `@` beginnt, ist nicht automatisch eine Import-Zeile: enthält der Rest
#     Leerzeichen, ist es Prosa (ein umgebrochener Absatz genügt) und darf den Push nicht mit
#     einer irreführenden „Datei nicht lesbar: <ganzer Satz>"-Meldung blockieren.
claude_fixture_319 '@importiert werden die Lessons bewusst nicht.'
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 0 "$ic_rc" "#319: Prosa-Zeile, die mit @ beginnt, ist kein Import (exit 0)"
assert_absent "$ic_out" "nicht lesbar" "#319: keine irreführende Fehlermeldung für eine Prosa-Zeile"
# Die einwortige Referenz-Zeile bleibt davon unberührt fail-closed (Regressions-Gegenprobe zu 7).
claude_fixture_319 '@docs/fehlt.md'
ic_319 >/dev/null 2>&1
assert_exit 1 "$?" "#319: einwortige Referenz-Zeile bleibt fail-closed (keine Aufweichung durch 12)"

# 13. Alleinstehende Import-Zeile mit Leerzeichen im Pfad: der Rest der Zeile ist der Pfad, wenn
#     er auflöst. Vorher wurde die Zeile gar nicht erkannt → 30 Zeilen blieben ungezählt.
claude_fixture_319 '@docs/mit datei.md'
mklines_319 "$TMP_IC/docs/mit datei.md" 30
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 0 "$ic_rc" "#319: Import-Zeile mit Leerzeichen im Pfad wird aufgelöst"
assert_contains_286 "$ic_out" "51" "#319: ihre Zeilen zählen mit (21 + 30 = 51)"

# 14. Datei ohne Schluss-Newline wird vollständig gezählt (`wc -l` hätte um 1 unterzählt; kein
#     Gate erzwingt die Schluss-Newline – `.prettierignore` deckt `docs/` und `CLAUDE.md`).
claude_fixture_319 '@docs/a.md'
printf 'eins\nzwei\ndrei' > "$TMP_IC/docs/a.md"   # bewusst OHNE \n am Ende
ic_out="$(ic_319)"; ic_rc=$?
assert_exit 0 "$ic_rc" "#319: Datei ohne Schluss-Newline → exit 0"
assert_contains_286 "$ic_out" "24" "#319: ihre letzte Zeile zählt mit (21 + 3 = 24, nicht 23)"

rm -rf "$TMP_IC"

# 15. Verdrahtung im Push-Gate – Anker ist die echte AUFRUFZEILE, nicht der Dateiname
#     (Lesson factory-workflow.md: Kommando ≠ Prosa-Erwähnung).
IC_CALL_319='bash "$IMPORT_CONTEXT_CHECK"'
grep -qF -- "$IC_CALL_319" "$CHECKS_DIR/pre-push.sh"
assert_true "$?" "#319: pre-push.sh ruft den Deckel-Check auf (echte Aufrufzeile)"

# Mutationsbeleg mit DEMSELBEN Assert-Ausdruck: ohne die Aufrufzeile wird der Guard rot
# (belegt Kausalität, nicht nur Quoting – Lesson nothra/tch-gastro-services#286).
IC_MUT_319="$(mktemp)"
grep -vF -- "$IC_CALL_319" "$CHECKS_DIR/pre-push.sh" > "$IC_MUT_319"
assert_absent "$(cat "$IC_MUT_319")" "$IC_CALL_319" \
  "#319 (Mutation): ohne die Aufrufzeile wird derselbe Guard rot"
rm -f "$IC_MUT_319"

# 16. VERHALTEN, nicht nur Verdrahtung: ein rotes Check-Ergebnis muss den Push blockieren
#     (Lesson nothra/tch-gastro-services#212 – deterministisches Gate braucht einen E2E-Verhaltenstest). pre-push.sh leitet
#     FACTORY_DIR aus dem eigenen Skript-Pfad ab (nicht aus der Env), deshalb Kopie von Gate +
#     Check in ein Temp-Root; die teuren Gates werden per Env auf `true` neutralisiert, Checks 4/5
#     fehlen dort und überspringen sich selbst – so entscheidet allein der Deckel. Muster wie
#     run_prepush_149 (:3313).
TMP_PP319="$(mktemp -d)"
mkdir -p "$TMP_PP319/scripts/checks"
mkdir -p "$TMP_PP319/scripts/lib"
cp "$SCRIPTS_DIR/lib/gate-config.sh" "$TMP_PP319/scripts/lib/"
cp "$CHECKS_DIR/pre-push.sh" "$CHECKS_DIR/import-context-limit-check.sh" "$TMP_PP319/scripts/checks/"
mk_feature_repo "$TMP_PP319" feature/319-deckel-e2e
run_prepush_319() {  # $1 = Zeilen in CLAUDE.md, $2 = Gate-Skript (Default: das kopierte Original)
  mklines_319 "$TMP_PP319/CLAUDE.md" "$1"
  ( cd "$TMP_PP319" && FACTORY_TEST_COMMAND=true FACTORY_TYPECHECK_COMMAND=true \
      FACTORY_FORMAT_COMMAND=true bash "${2:-scripts/checks/pre-push.sh}" >/dev/null 2>&1 )
}
run_prepush_319 $((IC_LIMIT_319 + 100))
assert_exit 1 "$?" "#319: roter Deckel blockiert den Push tatsächlich (E2E über pre-push.sh)"
run_prepush_319 20
assert_exit 0 "$?" "#319: Kontext unter der Grenze lässt den Push zu (E2E)"
# Mutationsbeleg: fällt das `FAILED=1` im Check-6-Block weg, blockiert derselbe rote Deckel
# nicht mehr – belegt, dass die Assertion oben genau daran hängt und nicht am Exit des Checks.
# Der awk-Block bricht am nächsten Job-Trenner ab (nicht nur an „Check 7"), damit die Isolation
# nicht still zu breit wird, falls der Deckel später der letzte Check ist (Klasse nothra/tch-gastro-services#255).
IC_PP_MUT_319="$TMP_PP319/scripts/checks/pre-push-ohne-failed.sh"
awk '
  /^# ─── Check 6:/ { in6 = 1; print; next }
  in6 && /^# ─── / { in6 = 0 }
  in6 && /^    FAILED=1$/ { next }
  { print }
' "$TMP_PP319/scripts/checks/pre-push.sh" > "$IC_PP_MUT_319"
assert_true "$([ "$(grep -c '^    FAILED=1$' "$IC_PP_MUT_319")" -lt "$(grep -c '^    FAILED=1$' "$TMP_PP319/scripts/checks/pre-push.sh")" ]; echo $?)" \
  "#319 (Mutation): das FAILED=1 des Check-6-Blocks ist entfernt"
run_prepush_319 $((IC_LIMIT_319 + 100)) "$IC_PP_MUT_319"
assert_exit 0 "$?" "#319 (Mutation): ohne FAILED=1 lässt derselbe rote Deckel den Push durch"
rm -rf "$TMP_PP319"

# 17. Referenz-Guard für alle Guidelines, die referenziert aber NICHT importiert werden
#     (ADR-047 §3): ohne ihn wird eine ausgelagerte Datei zur toten Datei. Deckt die zwei neu
#     ausgelagerten Dateien und die zwei schon vorher nur referenzierten ab – eine Schreibweise
#     statt zweier (der ältere bash-gotchas-Guard oben prüft nur die Präsenz der Referenz).
CLAUDE_FLAT_319="$(flat_286 "$FACTORY_ROOT/docs/factory/FACTORY.md")"
for g in git-workflow architecture-principles bash-gotchas token-efficiency; do
  assert_true "$([[ -f "$FACTORY_ROOT/docs/factory/guidelines/$g.md" ]]; echo $?)" \
    "#319: guidelines/$g.md vorhanden"
  assert_contains_286 "$CLAUDE_FLAT_319" "guidelines/$g.md" \
    "#319: $g.md ist in FACTORY.md referenziert (nicht verwaist)"
  # Gegenrichtung: nicht importiert – sonst ist die Umstellung nicht vollzogen
  grep -qE "^@docs/factory/guidelines/$g\.md$" "$FACTORY_ROOT/docs/factory/FACTORY.md"
  assert_true "$([ $? -ne 0 ]; echo $?)" "#319: $g.md ist nicht per @import geladen"
done

# 18. Die geladen bleibenden Guidelines MÜSSEN @importiert bleiben (ADR-047 §2).
for g in clean-code tdd-principles testing-standards; do
  grep -qE "^@docs/factory/guidelines/$g\.md$" "$FACTORY_ROOT/docs/factory/FACTORY.md"
  assert_true "$?" "#319: $g.md bleibt per @import geladen"
done

# 19. Der „Laden bei"-Trigger muss JE Datei existieren (ADR-047 §3), nicht irgendwo in CLAUDE.md:
# die Phrase wird deshalb zusammen mit dem Dateinamen als EINE Phrase geprüft. Eine
# dateiunabhängige Suche nach „Laden bei" wäre vakuös – belegt per Mutation unten.
# Die Trigger stehen in einem Blockquote, dessen Fortsetzungszeilen mit "> " beginnen; die
# Marker müssen vor dem Flachlesen weg, sonst landen sie mitten in der Phrase. Deshalb
# sed-Vorlauf in eine Kopie und darauf der vorhandene flat_286-Helfer (komponiert, keine
# zweite Lesefunktion – Lesson nothra/tch-gastro-services#240/#267 zur Helfer-Duplikation).
# ACHTUNG Fehlalarm-Modus: die Anker enthalten die vollständige Themen-Aufzählung des Bullets.
# Eine reine Umformulierung der Beschreibung macht diese Tests rot, OBWOHL der Trigger noch da
# ist – dann hier den Anker mitziehen, nicht den Trigger suchen.
IC_NOQUOTE_319="$(mktemp)"
sed 's/^[[:space:]]*>[[:space:]]*//' "$FACTORY_ROOT/docs/factory/FACTORY.md" > "$IC_NOQUOTE_319"
CLAUDE_TRIGGERS_319="$(flat_286 "$IC_NOQUOTE_319")"
rm -f "$IC_NOQUOTE_319"
IC_TRIGGER_GW_319='guidelines/git-workflow.md) – Branches, PR/Issue, Labels, Commits, Worktrees, Hook-Installation, Branch-Aufräumen · **Laden bei:**'
IC_TRIGGER_AP_319='guidelines/architecture-principles.md) – SOLID, Separation of Concerns, Dependency Rule, Fehlerbehandlung, API-Design · **Laden bei:**'
assert_contains_286 "$CLAUDE_TRIGGERS_319" "$IC_TRIGGER_GW_319" \
  "#319: git-workflow.md trägt einen eigenen „Laden bei\"-Trigger"
assert_contains_286 "$CLAUDE_TRIGGERS_319" "$IC_TRIGGER_AP_319" \
  "#319: architecture-principles.md trägt einen eigenen „Laden bei\"-Trigger"
# Mutation je Datei: Trigger nur an EINEM Bullet entfernen → nur dessen Assertion wird rot.
# Ersetzt wird LITERAL über awk index() – ein `sed`-Muster ist hier untauglich, weil die Phrase
# das Markdown-Bold `**Laden bei:**` enthält und BSD-sed das als Repetition-Operator ablehnt
# ("repetition-operator operand invalid"); die Substitution scheiterte dann still und die
# Mutation prüfte nichts (beim GREEN-Lauf dieser Task aufgefallen).
IC_MUT_FILE_319="$(mktemp)"
awk -v needle='API-Design · **Laden bei:**' -v repl='API-Design (ohne Trigger)' '
  { i = index($0, needle); if (i > 0) $0 = substr($0, 1, i - 1) repl substr($0, i + length(needle)); print }
' "$FACTORY_ROOT/docs/factory/FACTORY.md" | sed 's/^[[:space:]]*>[[:space:]]*//' > "$IC_MUT_FILE_319"
IC_CLAUDE_MUT_319="$(flat_286 "$IC_MUT_FILE_319")"
rm -f "$IC_MUT_FILE_319"
assert_contains_286 "$IC_CLAUDE_MUT_319" "$IC_TRIGGER_GW_319" \
  "#319 (Mutation): der git-workflow-Trigger bleibt unberührt"
assert_absent "$IC_CLAUDE_MUT_319" "$IC_TRIGGER_AP_319" \
  "#319 (Mutation): ein je-Datei entfernter Trigger macht genau dessen Assertion rot"

# 20. Die drei aus testing-standards.md verschobenen Abschnitte liegen in der Lesson und sind
#     im Index referenziert – verlustfreie Migration statt Streichung (spec-319 AC5/AC8).
# Im Factory-Repo liegt nur der ADR-040-Abschnitt (Coverage-Ausgabe); Exhaustiveness-Guards und Mock-Default
# sind App-Lessons des adoptierenden Projekts.
TESTING_LESSON_319="$(flat_286 "$FACTORY_ROOT/docs/factory/lessons/testing.md")"
for phrase in "Coverage-Ausgabe nur in ignorierte Pfade"; do
  assert_contains_286 "$TESTING_LESSON_319" "$phrase" \
    "#319: „$phrase\" steht in lessons/testing.md"
done
# Umfang statt nur Präsenz: die drei Abschnitte wurden byte-identisch migriert (1.197 + 1.531 +
# 920 = 3.648 Bytes Rumpf). Eine spätere versehentliche Kürzung würde die Präsenz-Checks oben
# nicht röten – deshalb ein Größen-Guard je Abschnitt (Lesson nothra/tch-gastro-services#196: Migration mit
# Reconstruction-Assertion belegen, nicht mit Titel-Präsenz).
ic_body_bytes_319() {  # $1 = Titel-Präfix des ### -Abschnitts
  awk -v anchor="$1" '
    index($0, "### ") == 1 && index($0, anchor) > 0 { found = 1; next }
    found && index($0, "### ") == 1 { exit }
    found { print }
  ' "$FACTORY_ROOT/docs/factory/lessons/testing.md" | wc -c | tr -d ' '
}
assert_true "$([ "$(ic_body_bytes_319 'Coverage-Ausgabe nur in ignorierte Pfade')" -ge 910 ]; echo $?)" \
  "#319: der ADR-040-Abschnitt ist vollständig migriert (≥ 910 Bytes Rumpf)"
# Der verschobene Text darf nicht auf seinen alten Kontext zeigen („siehe unten" zeigte in der
# Lesson ins Leere, weil darunter der Coverage-Abschnitt fehlt – Deixis-Falle, Lesson nothra/tch-gastro-services#315).
assert_absent "$TESTING_LESSON_319" "100 % bei neuem Code, siehe unten" \
  "#319: kein Deixis-Verweis „siehe unten\" im verschobenen Abschnitt"
# Und kein Verweis darf die verschobene Regel weiter in der alten Datei verorten. Die Suchphrase
# wird zur Laufzeit zusammengesetzt: stünde sie als Literal hier, enthielte die gescannte Datei
# (diese) sie selbst und der Guard wäre immer rot – selbstreferenzieller Content-Scan.
IC_OLD_HOME_319="testing-standards.md"
assert_absent "$(flat_286 "$CHECKS_DIR/tests/run-tests.sh")" \
  "$IC_OLD_HOME_319: Exhaustiveness-Guards" \
  "#319: kein Verweis mehr auf die verschobene Regel in der alten Datei"

# 21. Die kanonische pre-push-Check-Liste in git-workflow.md nennt den neuen Check (Lesson
#     nothra/tch-gastro-services#211/#176: Prosa im Präsens, die die geänderte Mechanik beschreibt, im selben PR nachziehen).
assert_contains_286 "$(flat_286 "$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md")" \
  "@import-Kontext-Deckel" "#319: git-workflow.md Hook-Tabelle nennt den Deckel-Check"
# Und die Invarianten-Registry in OPERATING.md (kanonische Quelle des prozeduralen Ablaufs).
# Anker ohne das führende `@import` in Backticks (der Zieltext setzt es als Code-Span, die
# Backticks würden sonst mitten in der Phrase stehen) – und ohne führenden Bindestrich: die
# assert_*-Helfer geben kein `--` an grep weiter, ein mit `-` beginnender Anker würde als Option
# gelesen (clean-code.md: variabler Suchwert immer als Daten behandeln).
assert_contains_286 "$(flat_286 "$FACTORY_ROOT/docs/factory/OPERATING.md")" \
  "Kontext unter dem Deckel halten" "#319: OPERATING.md führt die Deckel-Invariante"

# 22. Die Kern-Kurzregeln dürfen die Label-Konvention und die Schwellen-Tabelle NICHT kopieren:
#     git-workflow.md („Die kanonische Label-Liste bleibt allein in diesem Abschnitt"), ADR-018
#     und ADR-043 („Ein Ort je Regel") entscheiden das, und der nothra/tch-gastro-services#315-Registry-Guard kennt
#     CLAUDE.md nicht – eine Kopie hier wäre die einzige unbewachte (Review-Runde 3, K3).
assert_absent "$CLAUDE_FLAT_319" "Fund-Art" \
  "#319 K3: FACTORY.md kopiert die Schwellen-Tabelle nicht"
assert_absent "$CLAUDE_FLAT_319" "Im Zweifel Issue" \
  "#319 K3: FACTORY.md kopiert die Schwellen-Regel nicht als Prosa"
assert_absent "$CLAUDE_FLAT_319" "beliebig viele Aspekt-Labels" \
  "#319 K3: FACTORY.md kopiert die Label-Konvention nicht"
# Stattdessen ein Verweis auf die kanonische Quelle – sonst wäre die Regel im Dauerkontext
# unauffindbar (das wäre der umgekehrte Fehler). Anker trägt die Semantik der Regel, nicht nur
# das Fragment „kanonisch in": das wäre durch jede beliebige Umformulierung erfüllbar.
assert_contains_286 "$CLAUDE_FLAT_319" "nie aus dem Gedächtnis" \
  "#319 K3: FACTORY.md verpflichtet zum Nachlesen der kanonischen Quelle"
assert_contains_286 "$CLAUDE_FLAT_319" "„GitHub-Labels\"" \
  "#319 K3: der Verweis nennt den Abschnitt der kanonischen Quelle"

# 23. Keine falsche Erzwingungs-Behauptung (K2): der pre-push-Hook ist lokales, umgehbares
#     Feedback – fail-closed ist allein das Ruleset. Die Kurzregel darf das nicht verwischen,
#     und der Guardrail zum Deckel darf denselben Fehler nicht wiederholen.
assert_absent "$CLAUDE_FLAT_319" "beide fail-closed" \
  "#319 K2: keine Behauptung „beide fail-closed\" über Hook + Ruleset"
assert_contains_286 "$CLAUDE_FLAT_319" "umgehbar" \
  "#319 K2: Kurzregel benennt den Hook als umgehbares lokales Feedback"
# Und der commit-msg-Hook darf in ADR-047 nicht als Erzwinger des Commit-FORMATS auftreten –
# er prüft ausschließlich `--help`/`-h` (commit-msg-check.sh:11-12, :78). Ebenso darf
# branch-name-check.sh nicht als fail-closed-Gate auftreten: er ist ein PreToolUse-Hook auf den
# Bash-Tool-Input und greift nur bei `checkout -b`/`switch -c` aus Claude Code.
ADR047_FLAT_319="$(flat_286 "$FACTORY_ROOT/docs/factory/adr/047-import-kontext-guidelines-nach-erzwungenheit.md")"
assert_absent "$ADR047_FLAT_319" "\`commit-msg\`-Hook, \`issue-sync\`-Gate" \
  "#319 K2: ADR-047 führt den commit-msg-Hook nicht als Format-Erzwinger"
assert_contains_286 "$ADR047_FLAT_319" "PreToolUse" \
  "#319 K2: ADR-047 benennt branch-name-check.sh als PreToolUse-Hook, nicht als Push-Gate"
# Die YAGNI-Regel, die §4 für überholt erklärt, steht in OPERATING.md – nicht in
# token-efficiency.md (dort stand sie nie, `git log -S` belegt es).
assert_absent "$ADR047_FLAT_319" "Reflex\", \`token-efficiency.md\`" \
  "#319: ADR-047 zitiert die YAGNI-Regel nicht bei der falschen Quelle"
assert_contains_286 "$ADR047_FLAT_319" "OPERATING.md" \
  "#319: ADR-047 nennt OPERATING.md als Quelle der YAGNI-Regel"
# Und eine im selben PR umgesetzte ADR steht auf `Accepted`, nicht auf `Proposed`
# (Lesson factory-workflow.md, aus nothra/tch-gastro-services#197 – beim Implementieren mitzuziehen).
assert_contains_286 "$ADR047_FLAT_319" "## Status Accepted" \
  "#319: ADR-047 steht auf Accepted (Umsetzung im selben PR)"# ─── #319 (/security-review): Härtung des Gates gegen präparierte Referenzen ──
echo ""
echo "#319 Gate-Härtung (/security-review):"

TMP_SEC319="$(mktemp -d)"
mkdir -p "$TMP_SEC319/fx"
sec319() { FACTORY_DIR="$TMP_SEC319/fx" bash "$IMPORT_CHECK" 2>&1; }

# S1 – Fail-open bei nicht ermittelbarer Zeilenzahl. `$((total + ""))` ist in bash KEIN Fehler,
# sondern `+ 0`: schlug die Zählung fehl, meldete das Gate „0 von 1100" und exit 0, obwohl der
# Kontext die Grenze reißt. clean-code.md verlangt für genau das einen Integer-Guard vor der
# Arithmetik („fail-closed – im Zweifel ablehnen, nie still durchwinken").
seq 1 20 > "$TMP_SEC319/fx/CLAUDE.md"
printf '@big.md\n' >> "$TMP_SEC319/fx/CLAUDE.md"
seq 1 2000 > "$TMP_SEC319/fx/big.md"
sec319 >/dev/null 2>&1
assert_exit 1 "$?" "#319 S1 (Kontrolle): der Fixture ist ohne Manipulation rot"
mkdir -p "$TMP_SEC319/stub"
printf '#!/bin/sh\nexit 1\n' > "$TMP_SEC319/stub/awk"
chmod +x "$TMP_SEC319/stub/awk"
sec_out="$(PATH="$TMP_SEC319/stub:$PATH" FACTORY_DIR="$TMP_SEC319/fx" bash "$IMPORT_CHECK" 2>&1)"
sec_rc=$?
assert_exit 1 "$sec_rc" "#319 S1: nicht ermittelbare Zeilenzahl → exit 1 (fail-closed statt still grün)"
assert_absent "$sec_out" "0 von" "#319 S1: meldet keine Summe 0, die eine Freigabe vortäuscht"
rm -rf "$TMP_SEC319/stub"

# S2 – Pfad-Confinement. Eine Referenz-Zeile, die aus der Projektwurzel herausführt, ist kein
# @import dieses Repos: absolute Pfade und `..`-Segmente werden abgelehnt statt gezählt. Ohne
# das war der Check ein Zeilenzahl-Orakel über beliebige lesbare Dateien der Maschine
# (`@/etc/passwd` → „143 von 1100", exit 0).
for sec_pfad in '/etc/passwd' '../ausserhalb.md' 'unter/../../ausserhalb.md'; do
  seq 1 20 > "$TMP_SEC319/fx/CLAUDE.md"
  printf '@%s\n' "$sec_pfad" >> "$TMP_SEC319/fx/CLAUDE.md"
  sec_out="$(sec319)"; sec_rc=$?
  assert_exit 1 "$sec_rc" "#319 S2: Referenz außerhalb der Projektwurzel → exit 1 ($sec_pfad)"
  assert_contains_286 "$sec_out" "außerhalb der Projektwurzel" \
    "#319 S2: nennt den Grund der Ablehnung ($sec_pfad)"
done
# Gegenprobe: ein normaler wurzelrelativer Pfad bleibt unberührt zulässig.
seq 1 20 > "$TMP_SEC319/fx/CLAUDE.md"
printf '@unter/normal.md\n' >> "$TMP_SEC319/fx/CLAUDE.md"
mkdir -p "$TMP_SEC319/fx/unter"
seq 1 5 > "$TMP_SEC319/fx/unter/normal.md"
sec319 >/dev/null 2>&1
assert_exit 0 "$?" "#319 S2 (Gegenprobe): ein wurzelrelativer Pfad bleibt zulässig"
# Inline-Token außerhalb der Wurzel werden still übergangen (wie jedes nicht auflösende Token) –
# sonst würde eine Prosa-Erwähnung wie „@/etc/hosts" den Push blockieren.
seq 1 20 > "$TMP_SEC319/fx/CLAUDE.md"
printf 'Beispielhaft erwähnt: @/etc/passwd im Fließtext.\n' >> "$TMP_SEC319/fx/CLAUDE.md"
sec_out="$(sec319)"; sec_rc=$?
assert_exit 0 "$sec_rc" "#319 S2: Inline-Token außerhalb der Wurzel blockiert nicht"
assert_absent "$sec_out" "passwd" "#319 S2: und wird auch nicht gezählt oder gemeldet"

# S3 – Keine Terminal-/Log-Injection über den Pfad. `echo -e` interpretierte `\033`-Sequenzen aus
# dem Dateiinhalt und schrieb echte ESC-Bytes in die Gate-Ausgabe: ein präparierter Pfad konnte
# den Bildschirm löschen und ein grünes „alles ok" über die Ergebnisse der anderen Checks legen.
# Der Exit-Code war nie betroffen – die Täuschung zielte auf den Menschen (oder den Agenten),
# der die Push-Ausgabe liest.
seq 1 20 > "$TMP_SEC319/fx/CLAUDE.md"
printf '@x\\033[2J\\033[32mGATE-OK\n' >> "$TMP_SEC319/fx/CLAUDE.md"
sec_out="$(sec319)"
assert_contains_286 "$sec_out" 'x\033[2J' "#319 S3: die Escape-Sequenz bleibt literal in der Ausgabe"
printf '%s' "$sec_out" | LC_ALL=C grep -q "$(printf '\033')\[2J"
assert_true "$([ $? -ne 0 ]; echo $?)" "#319 S3: kein echtes ESC-Byte aus dem Pfad in der Ausgabe"

rm -rf "$TMP_SEC319"

# ─── nothra/tch-gastro-services#319 (/test): Lücken aus der AK-Abdeckungsmatrix ────────────────────────
echo ""
echo "#319 AK-Abdeckung (/test):"


# AC5 – „jede geltende Regel bleibt gültig und auffindbar". Die zwei verdichteten Guidelines
# behalten ihre Regel-Abschnitte; eine spätere, zu eifrige Verdichtung würde sonst unbemerkt
# eine Regelgruppe kappen (die vorhandenen Tests prüfen nur die drei VERSCHOBENEN Abschnitte).
ic_missing_sections_319() {  # $1 = Datei, $2… = erwartete Abschnitts-Überschriften
  local f="$1" fehlend="" titel
  shift
  for titel in "$@"; do
    grep -qF -- "## $titel" "$f" || fehlend="$fehlend '$titel'"
  done
  printf '%s' "$fehlend"
}
IC_TDD_319="$FACTORY_ROOT/docs/factory/guidelines/tdd-principles.md"
IC_TST_319="$FACTORY_ROOT/docs/factory/guidelines/testing-standards.md"
assert_true "$([ -z "$(ic_missing_sections_319 "$IC_TDD_319" \
  'Der Zyklus: Red → Green → Refactor' 'Test-Granularität' 'Was TDD nicht bedeutet' 'Wenn TDD schwer fällt')" ]; echo $?)" \
  "#319 AC5: tdd-principles.md trägt nach der Verdichtung alle Regel-Abschnitte"
assert_true "$([ -z "$(ic_missing_sections_319 "$IC_TST_319" \
  'Test-Aufbau: Arrange-Act-Assert' 'Test-Namen' 'Was testen? Was nicht?' 'Mocking-Regeln' \
  'Test-Isolation' 'Flaky Tests: Zero Tolerance' 'Coverage-Anforderungen')" ]; echo $?)" \
  "#319 AC5: testing-standards.md trägt nach der Verdichtung alle Regel-Abschnitte"
# Diskriminierungs-Kontrolle: der Helfer meldet eine fehlende Überschrift auch wirklich –
# sonst wäre die Abwesenheit von Fehlern oben nicht aussagekräftig.
assert_true "$([ -n "$(ic_missing_sections_319 "$IC_TDD_319" 'Ein Abschnitt, den es nicht gibt')" ]; echo $?)" \
  "#319 AC5 (Kontrolle): der Abschnitts-Helfer meldet eine fehlende Überschrift"

# AC8 – „kein Verweis zeigt ins Leere". In dieser Task sind zweimal tote relative Links
# entstanden (ein geratener ADR-Dateiname, ein Pfad ohne `../` aus tasks/) – beide erst durch
# einen Ad-hoc-Lauf gefunden. Der Check gehört damit in die Suite, begrenzt auf die Dateien,
# die dieser Task besitzt.
# Grenze der Erkennung: der Ausdruck sieht Markdown-Link-Syntax, nicht deren Kontext. Prosa, die
# ÜBER Links spricht (z. B. `](../adr/` in einem Backtick-Span, wie in lessons/factory-workflow.md),
# wird als Link gelesen und wäre ein Fehlalarm. Deshalb prüft der Guard eine feste Dateiliste –
# Dateien mit solcher Meta-Prosa gehören nicht hinein, bevor der Ausdruck Code-Spans ausnimmt.

# ─── nothra/tch-gastro-services#334: Telemetrie-Persistenz je Pipeline-Lauf (ADR-049) ──────────────────
echo ""
echo "#334 Telemetrie-Persistenz (ADR-049):"

TELE_LIB="$SCRIPTS_DIR/lib/telemetry-harvest.sh"
TELE_FIXTURE="$CHECKS_DIR/tests/fixtures/otel-console-sample.txt"
assert_true "$([[ -f "$TELE_LIB" ]]; echo $?)" "#334: scripts/lib/telemetry-harvest.sh vorhanden"
assert_true "$([[ -f "$TELE_FIXTURE" ]]; echo $?)" "#334: anonymisierte OTEL-Fixture vorhanden"

# Positivkontrolle VOR jedem Personendaten-Guard: trägt die Roh-Eingabe die verbotenen Felder
# überhaupt? Ohne sie prüfte der Guard unten nur, dass eine Datei ohne Personenfelder keine
# Personenfelder erzeugt – grün aus dem falschen Grund (Lesson nothra/tch-gastro-services#284/#319).
tele_raw_has_pii=0
for tele_f in 'user.email' 'user.id' 'user.account_id' 'user.account_uuid' 'organization.id'; do
  grep -qF -- "\"$tele_f\"" "$TELE_FIXTURE" || tele_raw_has_pii=1
done
assert_true "$tele_raw_has_pii" "#334 AK5 (Positivkontrolle): Fixture trägt alle fünf Personenfelder als Roh-Eingabe"

# Roh-Log wie im echten Lauf: Marker-Zeile von run_skill + Console-Exporter-Ausgabe.
TELE_TMP="$(mktemp -d)"
{ printf '→ Starte: /implement 334 (model: claude-haiku-4-5-20251001, max 20 turns)\n'
  cat "$TELE_FIXTURE"; } > "$TELE_TMP/raw.txt"

# Aufruf unter denselben Shell-Optionen wie der echte Aufrufer run-pipeline.sh
# (`set -euo pipefail`) – ein nachsichtigeres Harness übersieht genau die Klasse aus
# bash-gotchas.md §4 (leere Arrays/ungesetzte Variablen unter set -u).
tele_csv="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "2026-09-11T12:00:00Z" 334' \
  _ "$TELE_LIB" "$TELE_TMP/raw.txt" 2>"$TELE_TMP/err.txt")" && tele_rc=0 || tele_rc=$?
assert_true "$tele_rc" "#334 AK1: Ernte gegen die Fixture endet mit exit 0"

assert_contains_286 "$tele_csv" 'run_timestamp,task_id,step_seq,step,metric,model,query_source,agent_name,value_type,value' \
  "#334 AK1: CSV trägt die Whitelist-Kopfzeile"
assert_contains_286 "$tele_csv" '2026-09-11T12:00:00Z,334,1,implement,' \
  "#334 AK1/AK3: jede Zeile trägt Lauf-Zeitstempel, Task-ID und den Pipeline-Schritt"

# AK8: das verursachende Modell steht je Messwert in der Zeile.
assert_contains_286 "$tele_csv" ',claude_code.cost.usage,claude-haiku-4-5-20251001,main,,,0.0924215' \
  "#334 AK8/AK2: Kosten der Hauptsession mit Modell (Ist-Wert der Fixture)"
# AK2: der Sub-Agent ist eine eigene Zeile mit eigener Herkunft – weder in die Hauptsession
# eingerechnet noch weggelassen.
assert_contains_286 "$tele_csv" ',claude_code.cost.usage,claude-haiku-4-5-20251001,subagent,Explore,,0.02247895' \
  "#334 AK2: Sub-Agenten-Kosten getrennt ausgewiesen (agent.name + query_source)"
assert_contains_286 "$tele_csv" ',claude_code.token.usage,claude-haiku-4-5-20251001,main,,cacheRead,155975' \
  "#334 AK1: Token-Werttyp cacheRead der Hauptsession übernommen"
assert_contains_286 "$tele_csv" ',claude_code.token.usage,claude-haiku-4-5-20251001,subagent,Explore,output,540' \
  "#334 AK2: Token-Werttyp output des Sub-Agenten getrennt übernommen"

# Vollständigkeit: 2 cost- + 8 token-Datenpunkte der Fixture = 10 Datenzeilen (ohne Kopfzeile).
tele_rows=$(printf '%s\n' "$tele_csv" | grep -c '^2026-09-11T12:00:00Z,' || true)
assert_true "$([ "${tele_rows:-0}" -eq 10 ]; echo $?)" \
  "#334 AK1: genau 10 Datenzeilen – die 10 Datenpunkte der Fixture, keine erfunden, keine verloren (war: ${tele_rows:-0})"

# AK5 (der eigentliche Guard): weder ein verbotenes FELD noch ein verbotener WERT in der CSV.
# Beides, weil die Whitelist auf Feldnamen filtert, ein Leck aber über den Wert sichtbar würde.
for tele_f in 'user.email' 'user.id' 'user.account_id' 'user.account_uuid' 'organization.id' 'session.id'; do
  assert_absent "$tele_csv" "$tele_f" "#334 AK5: CSV enthält kein '$tele_f'"
done
for tele_v in 'anon@example.invalid' 'ANONYMISIERT-user-id' 'ANONYMISIERT-account-id' \
              'ANONYMISIERT-account-uuid' 'ANONYMISIERT-org-id' 'ANONYMISIERT-costcenter'; do
  assert_absent "$tele_csv" "$tele_v" "#334 AK5: CSV enthält auch den Wert '$tele_v' nicht"
done

# Security-Review-Finding (Kritisch): die Whitelist filtert nur FELDNAMEN, nie die FORM des
# Werts. Jeder String, der clean()s Zeichen-Alphabet einhält, wandert unverändert in die
# CSV – auch wenn er nicht vom echten OTEL-Exporter stammt, sondern aus der Konversations-
# ausgabe des Agenten (Teil desselben Streams, den telemetry_capture unverändert mitschreibt).
# Empirisch belegt (tasks/security-334.md): ein "model"-Feld mit einer E-Mail-Adresse wird
# klaglos übernommen. Guard: alle vier gelesenen Attribute mit demselben Angriffsmuster
# (E-Mail-artiger Wert) füttern, keines davon darf in der CSV auftauchen.
{ printf '→ Starte: /implement 334 (model: x, max 20 turns)\n'
  cat <<'RAW'
{
  descriptor: {
    name: "claude_code.token.usage",
  },
  dataPoints: [
    {
      attributes: {
        model: "opfer@angreifer.example",
        query_source: "opfer2@angreifer.example",
        "agent.name": "opfer3@angreifer.example",
        type: "opfer4@angreifer.example",
      },
      value: 1,
    }
  ],
}
RAW
} > "$TELE_TMP/wertefaelschung.txt"
tele_csv_wf="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "T" 334' \
  _ "$TELE_LIB" "$TELE_TMP/wertefaelschung.txt" 2>/dev/null || true)"
for tele_wf in 'opfer@angreifer.example' 'opfer2@angreifer.example' \
               'opfer3@angreifer.example' 'opfer4@angreifer.example'; do
  assert_absent "$tele_csv_wf" "$tele_wf" \
    "#334 (Security-Review-Finding): kein E-Mail-artiger Wert gelangt über ein gefälschtes Attribut in die CSV ('$tele_wf')"
done
# Kontrolle: derselbe Datenpunkt mit einem ECHTEN, erwartbaren model/query_source/type bleibt
# weiterhin nutzbar – der Fix darf keine legitimen Werte miterfassen (Diskriminierung).
{ printf '→ Starte: /implement 334 (model: x, max 20 turns)\n'
  cat "$TELE_FIXTURE"
} > "$TELE_TMP/echte-werte.txt"
tele_csv_echt="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "T" 334' \
  _ "$TELE_LIB" "$TELE_TMP/echte-werte.txt" 2>/dev/null || true)"
assert_contains_286 "$tele_csv_echt" ',claude_code.cost.usage,claude-haiku-4-5-20251001,main,,,0.0924215' \
  "#334 (Security-Review-Kontrolle): ein echter, erwartbarer Wert bleibt nach dem Fix erhalten"
assert_contains_286 "$tele_csv_echt" ',claude_code.cost.usage,claude-haiku-4-5-20251001,subagent,Explore,,0.02247895' \
  "#334 (Security-Review-Kontrolle): auch der Sub-Agenten-Datenpunkt bleibt erhalten"

# Kumulative Counter: derselbe Export-Zyklus zweimal im selben Schritt (das reale Verhalten bei
# gesetztem OTEL_METRIC_EXPORT_INTERVAL – gemessen am 2026-09-11: beide Zyklen tragen denselben
# Wert) darf die Zeilen nicht verdoppeln und den Wert nicht summieren.
{ printf '→ Starte: /implement 334 (model: claude-haiku-4-5-20251001, max 20 turns)\n'
  cat "$TELE_FIXTURE"; cat "$TELE_FIXTURE"; } > "$TELE_TMP/raw2.txt"
tele_csv2="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "2026-09-11T12:00:00Z" 334' \
  _ "$TELE_LIB" "$TELE_TMP/raw2.txt" 2>/dev/null || true)"
tele_rows2=$(printf '%s\n' "$tele_csv2" | grep -c '^2026-09-11T12:00:00Z,' || true)
assert_true "$([ "${tele_rows2:-0}" -eq 10 ]; echo $?)" \
  "#334: zwei Export-Zyklen desselben Schritts bleiben 10 Zeilen (kumulativer Counter, war: ${tele_rows2:-0})"
assert_contains_286 "$tele_csv2" ',claude_code.cost.usage,claude-haiku-4-5-20251001,main,,,0.0924215' \
  "#334: kumulativer Counter wird nicht summiert (0.0924215, nicht 0.184843)"

# AK3: zwei verschiedene Schritte bleiben getrennt – und derselbe Skill in zwei Aufrufen
# (Review-Rework-Schleife) kollabiert nicht zu einer Zeile, weil jeder Aufruf ein eigener
# claude-Prozess mit eigenem, bei 0 startendem Counter ist.
{ printf '→ Starte: /implement 334 (model: x, max 20 turns)\n'; cat "$TELE_FIXTURE"
  printf '→ Starte: /review 334 (model: x, max 30 turns)\n';    cat "$TELE_FIXTURE"
  printf '→ Starte: /implement 334 (model: x, max 20 turns)\n'; cat "$TELE_FIXTURE"; } > "$TELE_TMP/raw3.txt"
tele_csv3="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "2026-09-11T12:00:00Z" 334' \
  _ "$TELE_LIB" "$TELE_TMP/raw3.txt" 2>/dev/null || true)"
tele_rows3=$(printf '%s\n' "$tele_csv3" | grep -c '^2026-09-11T12:00:00Z,' || true)
assert_true "$([ "${tele_rows3:-0}" -eq 30 ]; echo $?)" \
  "#334 AK3: drei Schritt-Aufrufe → 3×10 Zeilen, je Aufruf getrennt (war: ${tele_rows3:-0})"
assert_contains_286 "$tele_csv3" ',1,implement,' "#334 AK3: erster Aufruf trägt step_seq 1"
assert_contains_286 "$tele_csv3" ',2,review,'    "#334 AK3: zweiter Aufruf trägt step_seq 2"
assert_contains_286 "$tele_csv3" ',3,implement,' \
  "#334 AK3: der zweite /implement-Aufruf bleibt als step_seq 3 eigenständig (Rework-Schleife)"

# Format-Drift-Guard (ADR-049 §E2), fail-closed: ein nicht mehr erkanntes Console-Format ist
# ein Fehler, keine Messung von 0.
printf 'irgendein Log ohne jede OTEL-Struktur\nnoch eine Zeile\n' > "$TELE_TMP/kaputt.txt"
tele_drift_out="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "T" 334' \
  _ "$TELE_LIB" "$TELE_TMP/kaputt.txt" 2>/dev/null)" && tele_drift_rc=0 || tele_drift_rc=$?
assert_true "$([ "$tele_drift_rc" -ne 0 ]; echo $?)" \
  "#334 Fehlerszenario: unerkanntes Console-Format endet non-zero (fail-closed, kein stilles 0)"
assert_absent "$tele_drift_out" 'claude_code.' "#334: bei Format-Drift entsteht keine Datenzeile"

# Drift auf der Marker-Seite: bleibt die Blockstruktur erkennbar, fehlt aber die Marker-Zeile,
# darf die Ernte nicht scheitern – die Messwerte sind echt, nur die Schritt-Zuordnung fehlt.
tele_csv4="$(bash -c 'set -euo pipefail; source "$1"; harvest_telemetry_csv "$2" "T" 334' \
  _ "$TELE_LIB" "$TELE_FIXTURE" 2>/dev/null || true)"
assert_contains_286 "$tele_csv4" ',0,unbekannt,' \
  "#334: Metrikblock ohne vorangehende Marker-Zeile wird als Schritt 'unbekannt' erfasst, nicht verworfen"

rm -rf "$TELE_TMP"

# Verdrahtung im Orchestrator: Default an, Abschalt-Parameter, Seam gesourct.
# Ersetzt die bis nothra/tch-gastro-services#334 gültige Assertion „OTEL ist opt-in (nicht automatisch in
# run-pipeline.sh gesourct)" – durch ADR-049 §E3 ungültig geworden. Ersatz statt Löschung:
# eine entfernte Zusicherung hinterlässt eine unbewachte Zusage.
grep -q 'source .*lib/telemetry-harvest.sh' "$PIPELINE"
assert_true "$?" "#334: run-pipeline.sh sourct den Ernte-Seam"
grep -qF -- 'TELEMETRY=true' "$PIPELINE"
assert_true "$?" "#334 AK4: Telemetrie ist in run-pipeline.sh per Default an"
grep -qF -- '--no-telemetry) TELEMETRY=false ;;' "$PIPELINE"
assert_true "$?" "#334 AK4: --no-telemetry schaltet sie im Argument-Parsing ab"
grep -qF -- 'CLAUDE_CODE_ENABLE_TELEMETRY=1' "$PIPELINE"
assert_true "$?" "#334: run-pipeline.sh aktiviert den Master-Schalter selbst"
grep -qF -- 'OTEL_METRICS_EXPORTER=console' "$PIPELINE"
assert_true "$?" "#334 §E2: Erhebung über den Console-Exporter"
# ADR-049 §E4: gezieltes Staging – factory-commit.sh (git add -A) würde bei einem Abbruch
# halbfertige Agenten-Änderungen mitcommitten.
tele_persist_body="$(awk '/^telemetry_persist\(\) \{/,/^\}/' "$PIPELINE")"
# Nur die CODE-Zeilen des Rumpfs: der WHY-Kommentar darin muss factory-commit.sh benennen
# (er begründet ja gerade dessen Nichtverwendung) und würde einen reinen Textscan über den
# ganzen Rumpf immer rot färben – die Prosa-Kollision aus Lesson nothra/tch-gastro-services#284.
tele_persist_code="$(printf '%s\n' "$tele_persist_body" | grep -v '^[[:space:]]*#' || true)"
assert_contains_286 "$tele_persist_code" 'commit -q -m "chore: telemetrie-messwerte lauf' \
  "#334 §E4: telemetry_persist() committet die CSV selbst"
assert_contains_286 "$tele_persist_code" 'git -C "$FACTORY_DIR" add -- "$TELEMETRY_CSV"' \
  "#334 §E4: gezieltes Staging genau der CSV, nicht des ganzen Baums"
# Review-Finding (Kritisch, Runde 2): der Commit darf NICHT von ambienter Git-Identität
# abhängen – auf einem frischen ubuntu-latest-Runner ohne konfigurierte user.email/user.name
# verwirft `git` seinen eigenen Fallback (empirisch in ubuntu:24.04 belegt: "unable to
# auto-detect email address"), wenn der Hostname keinen Domainanteil hat. Struktureller
# Guard statt Verhaltens-E2E, weil das Verhalten selbst plattformabhängig ist (auf macOS
# liefert git anstandslos eine Fallback-Identität und verdeckt eine fehlende Absicherung).
assert_contains_286 "$tele_persist_code" '-c user.email="factory-pipeline@localhost"' \
  "#334 (Review-Runde 2): der Commit trägt eine explizite user.email, unabhängig von ambienter Konfiguration"
assert_contains_286 "$tele_persist_code" '-c user.name="Development Factory"' \
  "#334 (Review-Runde 2): der Commit trägt auch einen expliziten user.name"
assert_contains_286 "$tele_persist_code" 'git -C "$FACTORY_DIR" push -q origin HEAD' \
  "#334 AK7: telemetry_persist() pusht den Commit auch (verify_final_state prüft ungepushte Commits)"
assert_absent "$tele_persist_code" 'factory-commit.sh' \
  "#334 §E4: der Telemetrie-Commit nutzt NICHT factory-commit.sh (git add -A)"
# Diskriminierungs-Kontrolle: schlägt derselbe Abwesenheits-Ausdruck an, wenn der Aufruf
# tatsächlich im Code stünde? Ohne sie belegt das grüne Ergebnis oben nur, dass irgendetwas
# gefiltert wurde – nicht, dass der Guard den Rückfall bemerken würde.
tele_persist_mutant="$(printf '%s\n  bash "$FACTORY_DIR/scripts/factory-commit.sh" "x"\n' "$tele_persist_code")"
printf '%s' "$tele_persist_mutant" | grep -qF 'factory-commit.sh'
assert_true "$?" "#334 (Kontrolle): derselbe Guard schlägt an, wenn factory-commit.sh im Code steht"


# ── E2E gegen den echten Orchestrator (Lesson nothra/tch-gastro-services#212: ein Wiring-Grep belegt kein Verhalten) ──
# Scaffold, Commit- und Origin-Helfer kommen aus den nothra/tch-gastro-services#310/#314-Blöcken oben – dort im
# HAS_YQ-Zweig definiert, deshalb steht auch dieser Abschnitt darin (Lesson nothra/tch-gastro-services#310: keine
# zweite, parallele Repo-Fixture daneben bauen).
if [ "$HAS_YQ" = 1 ]; then
  TELE_E2E_PROBE="$(mktemp -d)/env-probe.txt"

  # claude-Stub: schreibt die zwei Report-Dateien, protokolliert die geerbten OTEL-Variablen
  # und gibt die anonymisierte Fixture als Console-Exporter-Ausgabe aus.
  mk_tele_stub_334() {
    cat > "$1/bin/claude" <<STUB_334
#!/bin/sh
case "\$*" in
  *SKILL-security-review*) printf '## Ergebnis\nPASSED\n' > "\$PWD/tasks/security-$2.md" ;;
  *SKILL-review*)          printf '## Empfehlung\nAPPROVED\n' > "\$PWD/tasks/review-$2.md" ;;
esac
printf 'telemetry=%s exporter=%s\n' "\${CLAUDE_CODE_ENABLE_TELEMETRY:-unset}" "\${OTEL_METRICS_EXPORTER:-unset}" >> "$TELE_E2E_PROBE"
$3
exit 0
STUB_334
    chmod +x "$1/bin/claude"
  }

  # CLAUDE_CODE_ENABLE_TELEMETRY/OTEL_METRICS_EXPORTER werden mit ausgeknipst: sie sind in
  # einer interaktiven Claude-Code-Sitzung ambient gesetzt (hier beobachtet am 2026-09-11:
  # CLAUDE_CODE_ENABLE_TELEMETRY=1). Ohne das `-u` wäre der --no-telemetry-Test lokal
  # falschrot UND der Default-an-Test falschgrün – er belegte dann die ambiente Variable,
  # nicht die Aktivierung durch die Pipeline. Dieselbe Klasse wie das
  # PR_SHEPHERD/FACTORY_STAGE-Durchschlagen aus nothra/tch-gastro-services#262.
  run_334() {
    local dir="$1" task_id="$2"; shift 2
    OUT_334=$(cd "$dir" && PATH="$dir/bin:$PATH" \
      FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true FACTORY_COVERAGE_COMMAND=true \
      env -u PR_SHEPHERD -u FACTORY_STAGE -u FACTORY_METRICS_ISSUE -u GITHUB_STEP_SUMMARY \
          -u CLAUDE_CODE_ENABLE_TELEMETRY -u OTEL_METRICS_EXPORTER \
      bash "$dir/scripts/run-pipeline.sh" "$task_id" "$@" 2>&1); RC_334=$?
  }

  # tele_cost_sum_334 <csv-datei> – Summen-Helfer für die nothra/tch-gastro-services#334-Kostensummen-Assertion
  # (Review-Finding 2) unten UND den nothra/tch-gastro-services#341-Locale-Regressionstest: beide rufen denselben
  # Ausdruck, statt dass eine Kopie vom Original wegdriftet (lessons/testing.md,
  # Mutationsbeleg-Regel).
  # LC_ALL=C (nothra/tch-gastro-services#341): ohne gesetzte Locale parst BSD-awk "0.05"/"0.08" unter einer
  # Komma-Dezimaltrenner-Locale als 0 UND formatiert "%.2f" mit Komma – Ergebnis "0,00"
  # statt "0.13". Präzedenz in dieser Datei: :4687, :7871.
  tele_cost_sum_334() {
    LC_ALL=C awk -F, '$4=="implement" && $5=="claude_code.cost.usage"{s+=$10} END{printf "%.2f", s+0}' "$1"
  }

  # ── AK1/AK3/AK4/AK7 (Default an): CSV entsteht, ist committet und gepusht.
  TMP_334A="$(mktemp -d)"; TMP_334A_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334A" 905
  cp "$TELE_FIXTURE" "$TMP_334A/bin/otel-fixture.txt"
  mk_tele_stub_334 "$TMP_334A" 905 'cat "$(dirname "$0")/otel-fixture.txt"'
  : > "$TELE_E2E_PROBE"
  commit_314_pushed "$TMP_334A" "$TMP_334A_ORIGIN"
  run_334 "$TMP_334A" 905
  assert_contains_286 "$(cat "$TELE_E2E_PROBE")" 'telemetry=1 exporter=console' \
    "#334 AK4 (E2E): ein Lauf ohne Parameter vererbt die OTEL-Variablen an die CLI"
  tele_csv_e2e="$(find "$TMP_334A/tasks" -name 'telemetry-905-*.csv' | head -1)"
  assert_true "$([ -n "$tele_csv_e2e" ]; echo $?)" \
    "#334 AK1 (E2E): der Lauf legt tasks/telemetry-905-<zeitstempel>.csv an"
  assert_contains_286 "$OUT_334" 'Telemetrie persistiert' "#334 AK1 (E2E): der Lauf meldet die Persistenz"
  if [ -n "$tele_csv_e2e" ]; then
    tele_body_e2e="$(cat "$tele_csv_e2e")"
    assert_contains_286 "$tele_body_e2e" ',implement,claude_code.cost.usage,' \
      "#334 AK3 (E2E): die Kosten des /implement-Schritts stehen unter diesem Schritt"
    assert_contains_286 "$tele_body_e2e" ',security-review,claude_code.cost.usage,' \
      "#334 AK3 (E2E): auch ein späterer Schritt ist eigenständig zugeordnet"
    assert_contains_286 "$tele_body_e2e" ',subagent,Explore,' \
      "#334 AK2 (E2E): der Sub-Agenten-Anteil steht getrennt in der Datei"
    for tele_f in 'user.email' 'user.id' 'user.account_id' 'user.account_uuid' 'organization.id'; do
      assert_absent "$tele_body_e2e" "$tele_f" "#334 AK5 (E2E): die geschriebene Datei enthält kein '$tele_f'"
    done
    # AK7: getrackt, committet UND gepusht – nicht nur geschrieben. `git status --porcelain`
    # über die Datei ist leer, sobald sie committet ist; `git log origin/<branch>` belegt den
    # Push (ohne ihn ließe verify_final_state jeden Folgelauf scheitern).
    assert_true "$([ -z "$(git -C "$TMP_334A" status --porcelain -- "$tele_csv_e2e")" ]; echo $?)" \
      "#334 AK7 (E2E): die CSV ist committet – sie hinterlässt keinen dirty Working Tree"
    tele_br_334="$(git -C "$TMP_334A" rev-parse --abbrev-ref HEAD)"
    git -C "$TMP_334A" log --oneline "origin/$tele_br_334" -- "$tele_csv_e2e" 2>/dev/null | grep -q .
    assert_true "$?" "#334 AK7 (E2E): der Commit ist auch auf origin – der Lauf pusht ihn selbst"
  fi
  assert_true "$([ -z "$(find "$TMP_334A/tasks" -name 'telemetry-raw-*.tmp.txt')" ]; echo $?)" \
    "#334 AK5 (E2E): der personenbehaftete Roh-Output bleibt nicht liegen"
  rm -rf "$TMP_334A" "$TMP_334A_ORIGIN"

  # ── AK4 (abgeschaltet): --no-telemetry erzeugt nichts und aktiviert nichts.
  TMP_334B="$(mktemp -d)"; TMP_334B_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334B" 906
  cp "$TELE_FIXTURE" "$TMP_334B/bin/otel-fixture.txt"
  mk_tele_stub_334 "$TMP_334B" 906 'cat "$(dirname "$0")/otel-fixture.txt"'
  : > "$TELE_E2E_PROBE"
  commit_314_pushed "$TMP_334B" "$TMP_334B_ORIGIN"
  run_334 "$TMP_334B" 906 --no-telemetry
  assert_contains_286 "$(cat "$TELE_E2E_PROBE")" 'telemetry=unset exporter=unset' \
    "#334 AK4: --no-telemetry setzt die OTEL-Variablen gar nicht erst"
  assert_true "$([ -z "$(find "$TMP_334B/tasks" -name 'telemetry-906-*.csv')" ]; echo $?)" \
    "#334 AK4: --no-telemetry schreibt kein Artefakt"
  assert_absent "$OUT_334" 'Telemetrie ernten' "#334 AK4: --no-telemetry führt den Ernte-Schritt nicht aus"
  rm -rf "$TMP_334B" "$TMP_334B_ORIGIN"

  # ── AK6 / Fehlerszenario 1: die CLI emittiert nichts Erkennbares.
  # Gebrochen wird die MESSUNG (der Stub gibt Text ohne OTEL-Struktur aus), nicht nur der
  # Input – ein Guard, der nur leere Eingaben kennt, sähe den stillen Teilausfall nie (nothra/tch-gastro-services#319).
  TMP_334C="$(mktemp -d)"; TMP_334C_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334C" 907
  mk_tele_stub_334 "$TMP_334C" 907 'printf "ich bin ein Log ohne jede OTEL-Struktur\n"'
  : > "$TELE_E2E_PROBE"
  commit_314_pushed "$TMP_334C" "$TMP_334C_ORIGIN"
  run_334 "$TMP_334C" 907
  assert_contains_286 "$OUT_334" 'Keine auswertbaren OTEL-Messwerte' \
    "#334 Fehlerszenario 1: das Fehlen wird sichtbar gemeldet"
  assert_true "$([ -z "$(find "$TMP_334C/tasks" -name 'telemetry-907-*.csv')" ]; echo $?)" \
    "#334 Fehlerszenario 1: es entsteht KEIN leeres/irreführendes Artefakt"
  assert_contains_286 "$OUT_334" 'Pipeline erfolgreich abgeschlossen' \
    "#334 AK6: der Lauf bleibt trotz gescheiterter Messung erfolgreich"
  assert_exit 0 "$RC_334" "#334 AK6: gescheiterte Messung lässt den Exit-Code unverändert"
  rm -rf "$TMP_334C" "$TMP_334C_ORIGIN"

  # ── AK6/AK7: Push scheitert (kein origin). Entweder committet UND gepusht – oder gar
  # nichts. Ein liegengebliebener Commit ließe jeden Folgelauf im selben Worktree an der
  # Endzustands-Verifikation scheitern.
  TMP_334D="$(mktemp -d)"
  scaffold_310 "$TMP_334D" 908
  cp "$TELE_FIXTURE" "$TMP_334D/bin/otel-fixture.txt"
  mk_tele_stub_334 "$TMP_334D" 908 'cat "$(dirname "$0")/otel-fixture.txt"'
  : > "$TELE_E2E_PROBE"
  commit_310 "$TMP_334D"
  tele_head_before_334="$(git -C "$TMP_334D" rev-parse HEAD)"
  run_334 "$TMP_334D" 908
  # Referenzlauf im identischen Setup, nur ohne Telemetrie: AK6 verlangt „Exit-Code
  # unverändert" – belegbar nur im Vergleich mit demselben Lauf ohne die Messung.
  TMP_334E="$(mktemp -d)"
  scaffold_310 "$TMP_334E" 908
  mk_tele_stub_334 "$TMP_334E" 908 'printf "x\n"'
  commit_310 "$TMP_334E"
  tele_rc_with_334="$RC_334"
  run_334 "$TMP_334E" 908 --no-telemetry
  assert_exit "$RC_334" "$tele_rc_with_334" \
    "#334 AK6: gescheiterter Push ändert den Exit-Code nicht (gleicher Code wie ohne Telemetrie)"
  assert_true "$([ "$(git -C "$TMP_334D" rev-parse HEAD)" = "$tele_head_before_334" ]; echo $?)" \
    "#334 AK7: nach gescheitertem Push liegt kein Telemetrie-Commit im Branch"
  assert_true "$([ -z "$(find "$TMP_334D/tasks" -name 'telemetry-908-*.csv')" ]; echo $?)" \
    "#334 AK7: nach gescheitertem Push bleibt auch keine uncommittete CSV liegen"
  rm -rf "$TMP_334D" "$TMP_334E"

  # ── Review-Finding 1 (Kritisch): „Index nicht leer"-Zweig darf die geerntete CSV nicht
  # auf der Platte zurücklassen – sonst dirty Working Tree trotz „übersprungen (fail-open)".
  TMP_334F="$(mktemp -d)"; TMP_334F_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334F" 909
  cp "$TELE_FIXTURE" "$TMP_334F/bin/otel-fixture.txt"
  # codify staged bewusst eine fremde Datei, bevor telemetry_persist läuft (Ort im Ablauf:
  # unmittelbar nach /codify) – simuliert eine Situation, in der bereits etwas im Index liegt.
  mk_tele_stub_334 "$TMP_334F" 909 \
    'case "$*" in *SKILL-codify*) : > "$PWD/tasks/leftover-staged.txt"; git add "$PWD/tasks/leftover-staged.txt" ;; esac
cat "$(dirname "$0")/otel-fixture.txt"'
  : > "$TELE_E2E_PROBE"
  commit_314_pushed "$TMP_334F" "$TMP_334F_ORIGIN"
  run_334 "$TMP_334F" 909
  assert_contains_286 "$OUT_334" 'Index nicht leer' \
    "#334 (Review-Finding 1): der Index-nicht-leer-Zweig greift wie erwartet"
  assert_true "$([ -z "$(find "$TMP_334F/tasks" -name 'telemetry-909-*.csv')" ]; echo $?)" \
    "#334 (Review-Finding 1): der Index-nicht-leer-Zweig hinterlässt KEINE CSV auf der Platte"
  # Kein "Pipeline erfolgreich"-Assert hier: die selbst injizierte Vorbedingung
  # (leftover-staged.txt) macht den Arbeitsbaum unabhängig vom Telemetrie-Fix dirty – das
  # ist Absicht des Szenarios, nicht Teil dessen, was der Fix beheben soll.
  rm -rf "$TMP_334F" "$TMP_334F_ORIGIN"

  # ── Review-Finding 1 (Kritisch), zweiter Zweig: `git add` gelingt, `git commit` scheitert
  # (hier: ablehnender pre-commit-Hook – deterministischer als auf fehlende globale
  # Git-Identität zu setzen, Lesson testing.md nothra/tch-gastro-services#265). Auch hier darf keine CSV liegen bleiben.
  TMP_334G="$(mktemp -d)"; TMP_334G_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334G" 910
  cp "$TELE_FIXTURE" "$TMP_334G/bin/otel-fixture.txt"
  mk_tele_stub_334 "$TMP_334G" 910 'cat "$(dirname "$0")/otel-fixture.txt"'
  : > "$TELE_E2E_PROBE"
  commit_314_pushed "$TMP_334G" "$TMP_334G_ORIGIN"
  mkdir -p "$TMP_334G/.git/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$TMP_334G/.git/hooks/pre-commit"
  chmod +x "$TMP_334G/.git/hooks/pre-commit"
  run_334 "$TMP_334G" 910
  assert_contains_286 "$OUT_334" 'Telemetrie-Commit fehlgeschlagen' \
    "#334 (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig greift wie erwartet"
  assert_true "$([ -z "$(find "$TMP_334G/tasks" -name 'telemetry-910-*.csv')" ]; echo $?)" \
    "#334 (Review-Finding 1): der Commit-fehlgeschlagen-Zweig hinterlässt KEINE CSV auf der Platte"
  rm -rf "$TMP_334G" "$TMP_334G_ORIGIN"

  # ── Review-Finding 2 (Kritisch): Retry-mit-Backoff INNERHALB eines run_skill()-Aufrufs
  # (Rate-Limit-Fall, run-pipeline.sh:405) darf die Kosten des ersten (gescheiterten)
  # Versuchs nicht verlieren. Zwei physische claude-Prozesse unter demselben Skill –
  # sleep ist über scaffold_310s Stub bereits entschärft (kein echtes Warten).
  TMP_334H="$(mktemp -d)"; TMP_334H_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334H" 911
  cat > "$TMP_334H/bin/otel-fixture-fail.txt" <<'FIXA'
{
  descriptor: {
    name: "claude_code.cost.usage",
  },
  dataPoints: [
    {
      attributes: {
        model: "claude-haiku-4-5-20251001",
        query_source: "main",
      },
      value: 0.05,
    }
  ],
}
FIXA
  cat > "$TMP_334H/bin/otel-fixture-ok.txt" <<'FIXB'
{
  descriptor: {
    name: "claude_code.cost.usage",
  },
  dataPoints: [
    {
      attributes: {
        model: "claude-haiku-4-5-20251001",
        query_source: "main",
      },
      value: 0.08,
    }
  ],
}
FIXB
  cat > "$TMP_334H/bin/claude" <<'STUB_334H'
#!/bin/sh
case "$*" in
  *SKILL-implement*)
    d="$(dirname "$0")"
    n=0
    [ -f "$d/.impl-attempts" ] && n="$(cat "$d/.impl-attempts")"
    n=$((n + 1))
    echo "$n" > "$d/.impl-attempts"
    if [ "$n" -eq 1 ]; then
      cat "$d/otel-fixture-fail.txt"
      exit 7
    fi
    cat "$d/otel-fixture-ok.txt"
    exit 0
    ;;
  *SKILL-security-review*) printf '## Ergebnis\nPASSED\n' > "$PWD/tasks/security-911.md" ;;
  *SKILL-review*)          printf '## Empfehlung\nAPPROVED\n' > "$PWD/tasks/review-911.md" ;;
esac
exit 0
STUB_334H
  chmod +x "$TMP_334H/bin/claude"
  commit_314_pushed "$TMP_334H" "$TMP_334H_ORIGIN"
  run_334 "$TMP_334H" 911
  tele_csv_h="$(find "$TMP_334H/tasks" -name 'telemetry-911-*.csv' | head -1)"
  assert_true "$([ -n "$tele_csv_h" ]; echo $?)" \
    "#334 (Review-Finding 2): der Lauf mit einem gescheiterten ersten Versuch persistiert dennoch eine CSV"
  if [ -n "$tele_csv_h" ]; then
    # Summe statt Maximum: 0.05 (Versuch 1, gescheitert) + 0.08 (Versuch 2, erfolgreich) = 0.13.
    # awk statt bc/jq – hier bereits als Test-Utility im Einsatz (siehe die awk-Aufrufe oben).
    tele_sum_h=$(tele_cost_sum_334 "$tele_csv_h")
    assert_true "$([ "$tele_sum_h" = "0.13" ]; echo $?)" \
      "#334 (Review-Finding 2): Kosten BEIDER Versuche stehen in der Summe (0.13), nicht nur der letzte (0.08) (war: $tele_sum_h)"
  fi
  rm -rf "$TMP_334H" "$TMP_334H_ORIGIN"

  # ── nothra/tch-gastro-services#341: tele_cost_sum_334() bleibt unter deutscher Locale locale-unabhängig ──
  # BSD-awk parst/formatiert Dezimalzahlen sonst lokale-abhängig (Komma statt Punkt) –
  # dieselbe Fail-Klasse wie nothra/tch-gastro-services#96, hier in awk statt bash-printf. Ruft denselben Helfer wie
  # die nothra/tch-gastro-services#334-Assertion oben auf (kein kopierter awk-Ausdruck, sonst Drift zwischen Test und
  # echter Zeile, lessons/testing.md).
  if [ "$HAS_DE_LOCALE" -eq 1 ]; then
    TELE_341_CSV="$(mktemp)"
    cat > "$TELE_341_CSV" <<'CSV341'
run_timestamp,task_id,step_seq,step,metric,model,query_source,agent_name,value_type,value
2026-09-16T00:00:00Z,341,1,implement,claude_code.cost.usage,claude-haiku-4-5-20251001,main,,double,0.05
2026-09-16T00:00:00Z,341,2,implement,claude_code.cost.usage,claude-haiku-4-5-20251001,main,,double,0.08
CSV341
    tele_sum_341="$(LC_ALL=de_DE.UTF-8 LC_NUMERIC=de_DE.UTF-8 tele_cost_sum_334 "$TELE_341_CSV")"
    assert_true "$([ "$tele_sum_341" = "0.13" ]; echo $?)" \
      "#341: tele_cost_sum_334() summiert 0.05+0.08 unter deutscher Locale korrekt zu 0.13 (war: $tele_sum_341)"
    rm -f "$TELE_341_CSV"
  else
    echo "  • #341: tele_cost_sum_334() locale-sicher – übersprungen (de_DE.UTF-8-Locale fehlt)"
  fi

  # ── Fehlerszenario 2 (spec-334): Lauf bricht vorzeitig ab (hier: Quality-Gate „Tests"
  # scheitert nach Phase 1) – die bis dahin angefallene Telemetrie (der /implement-Schritt)
  # wird trotzdem persistiert. Das ist NICHT der reguläre Aufrufort zwischen /codify und
  # /pr-shepherd, sondern ausschließlich der EXIT-Trap-Fallback (measure_process_metrics_on_exit).
  TMP_334I="$(mktemp -d)"; TMP_334I_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334I" 912
  cp "$TELE_FIXTURE" "$TMP_334I/bin/otel-fixture.txt"
  mk_tele_stub_334 "$TMP_334I" 912 'cat "$(dirname "$0")/otel-fixture.txt"'
  commit_314_pushed "$TMP_334I" "$TMP_334I_ORIGIN"
  OUT_334I=$(cd "$TMP_334I" && PATH="$TMP_334I/bin:$PATH" \
    FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=false \
    env -u PR_SHEPHERD -u FACTORY_STAGE -u FACTORY_METRICS_ISSUE -u GITHUB_STEP_SUMMARY \
        -u CLAUDE_CODE_ENABLE_TELEMETRY -u OTEL_METRICS_EXPORTER \
    bash "$TMP_334I/scripts/run-pipeline.sh" 912 2>&1); RC_334I=$?
  assert_true "$([ "$RC_334I" -ne 0 ]; echo $?)" \
    "#334 Fehlerszenario 2: der erzwungene Gate-Fehlschlag beendet den Lauf tatsächlich non-zero"
  assert_absent "$OUT_334I" 'Phase 2: Code-Review' \
    "#334 Fehlerszenario 2 (Kontrolle): der Abbruch geschieht wie beabsichtigt VOR Phase 2 (Test-Vorbedingung selbst geprüft)"
  tele_csv_i="$(find "$TMP_334I/tasks" -name 'telemetry-912-*.csv' | head -1)"
  assert_true "$([ -n "$tele_csv_i" ]; echo $?)" \
    "#334 Fehlerszenario 2: die EXIT-Trap persistiert die bis zum Abbruch angefallene Telemetrie"
  if [ -n "$tele_csv_i" ]; then
    assert_contains_286 "$(cat "$tele_csv_i")" ',implement,claude_code.cost.usage,' \
      "#334 Fehlerszenario 2: die CSV enthält die Kosten des vor dem Abbruch gelaufenen /implement-Schritts"
  fi
  rm -rf "$TMP_334I" "$TMP_334I_ORIGIN"

  # ── Fehlerszenario 3 (spec-334): kein Lauf überschreibt das Artefakt eines anderen.
  # Zwei sequenzielle Läufe für ZWEI TASKS im selben Worktree – nach dem zweiten Lauf müssen
  # beide Telemetrie-Dateien noch existieren (der zweite Lauf löscht/überschreibt die Datei
  # des ersten nicht). Bewusst zwei Task-IDs statt zweier Läufe derselben Task innerhalb der
  # gleichen Sekunde: Letzteres wäre ein Test-Artefakt der Sekunden-Granularität des
  # Zeitstempels, kein realistisches Szenario (ein echter Pipeline-Lauf dauert Minuten).
  TMP_334J="$(mktemp -d)"; TMP_334J_ORIGIN="$(mktemp -d)"
  scaffold_310 "$TMP_334J" 913
  printf '# Task 914: zweiter Lauf\n' > "$TMP_334J/tasks/task-914-zweiter-lauf.md"
  cp "$TELE_FIXTURE" "$TMP_334J/bin/otel-fixture.txt"
  # EIN Stub für BEIDE Task-IDs, einmal geschrieben und committet: würde der Stub zwischen
  # den beiden Läufen erneut geschrieben (mk_tele_stub_334 ein zweites Mal), stünde
  # bin/claude als geänderte, uncommittete Tracked-Datei da – der zweite Lauf schlüge dann
  # schon am Preflight („Working Tree nicht sauber") fehl, bevor die eigentliche Frage
  # (überschreibt er die erste CSV?) je geprüft würde.
  #
  # Die review-914.md/security-914.md-Schreibvorgänge müssen an dieselbe Skill-Fallunterscheidung
  # gebunden sein wie das eingebaute $2=913-Case – sonst schreibt JEDER claude-Aufruf während
  # des ERSTEN Laufs (auch /implement, /test, /refactor) review-914.md unconditional vorab.
  # Das ließ den späteren echten /review-Aufruf des ZWEITEN Laufs auf identischen Inhalt
  # treffen → Report-Guard wertet ihn als „aus einem früheren Aufruf, unverändert" (stale) →
  # /review scheitert nach 3 Versuchen → der zweite Lauf bricht in Phase 2 ab, nicht am Ende.
  # Test bestand dadurch nur zufällig, weil der EXIT-Trap-Fallback (nicht der reguläre
  # Aufrufort zwischen /codify und /pr-shepherd) die Telemetrie rettete – ein Test-Selbstfund
  # während /test, kein Produktionsdefekt (Rezidiv der Lesson „Mock-Default … verdeckt" in
  # neuer Form: die Testdouble-Fixture erzeugte Zustand außerhalb ihres eigenen Zuständigkeits-
  # fensters und kollidierte mit einer echten Guard-Logik der Produktion).
  # Zusätzlich an `task-914` geankert, nicht nur an den Skill-Marker: Ein reiner
  # `*SKILL-review*`-Treffer feuerte auch beim ECHTEN /review-Aufruf von Lauf 1 (Task 913) –
  # dieselbe Prompt-Substring-Prüfung kennt den Unterschied zwischen den Läufen nicht, nur
  # die eingebettete Task-Datei (`task-${TASK_ID}-*.md`, hier `task-914-zweiter-lauf.md`)
  # unterscheidet sie zuverlässig.
  mk_tele_stub_334 "$TMP_334J" 913 \
    'case "$*" in
  *SKILL-review*task-914*)          printf "## Empfehlung\nAPPROVED\n" > "$PWD/tasks/review-914.md" ;;
  *SKILL-security-review*task-914*) printf "## Ergebnis\nPASSED\n" > "$PWD/tasks/security-914.md" ;;
esac
cat "$(dirname "$0")/otel-fixture.txt"'
  commit_314_pushed "$TMP_334J" "$TMP_334J_ORIGIN"
  run_334 "$TMP_334J" 913
  tele_csv_j1="$(find "$TMP_334J/tasks" -name 'telemetry-913-*.csv' | head -1)"
  assert_true "$([ -n "$tele_csv_j1" ]; echo $?)" \
    "#334 Fehlerszenario 3: erster Lauf (Task 913) persistiert seine CSV"
  run_334 "$TMP_334J" 914
  tele_csv_j2="$(find "$TMP_334J/tasks" -name 'telemetry-914-*.csv' | head -1)"
  assert_true "$([ -n "$tele_csv_j2" ]; echo $?)" \
    "#334 Fehlerszenario 3: zweiter Lauf (Task 914) persistiert seine EIGENE CSV"
  assert_true "$([ -f "$tele_csv_j1" ]; echo $?)" \
    "#334 AK1/Fehlerszenario 3: die CSV des ERSTEN Laufs existiert nach dem zweiten Lauf noch (kein Überschreiben)"
  rm -rf "$TMP_334J" "$TMP_334J_ORIGIN"
  rm -rf "$(dirname "$TELE_E2E_PROBE")"
else
  skip_yq "#334 E2E: Telemetrie-Persistenz in run-pipeline.sh"
fi

# ── Doku ohne Drift (CLAUDE.md, OPERATING.md) ───────────────────────────────
# Beide beschrieben die Telemetrie bis nothra/tch-gastro-services#334 als „Default aus, otel.env.example sourcen".
# Erledigt der PR die Mechanik, ist dieselbe Prosa im selben PR nachzuziehen (Lesson nothra/tch-gastro-services#176).
# Kontrolle für die `--`-Härtung der beiden Assert-Helfer (siehe ihre Definition oben):
# eine Phrase, die mit `-` beginnt, muss gefunden UND ihr Fehlen erkannt werden. Ohne das `--`
# bricht grep hier mit einem Usage-Fehler ab – der Präsenz-Check wäre rot, der
# Abwesenheits-Check grün, in beiden Fällen ohne je gesucht zu haben.
assert_contains_286 'ein --no-telemetry im Text' '--no-telemetry' \
  "#334 (Kontrolle): assert_contains_286 findet eine Phrase, die mit '-' beginnt"
assert_absent 'hier steht der Parameter nicht' '--no-telemetry' \
  "#334 (Kontrolle): assert_absent erkennt das Fehlen derselben Phrase"

claude_md_flat_334=$(flat_286 "$CLAUDE_MD")
assert_contains_286 "$claude_md_flat_334" 'läuft seit nothra/tch-gastro-services#334 automatisch je Pipeline-Lauf' \
  "#334 Doku: FACTORY.md beschreibt die Telemetrie als automatischen Pipeline-Bestandteil"
assert_contains_286 "$claude_md_flat_334" '--no-telemetry' \
  "#334 Doku: FACTORY.md nennt den Abschalt-Parameter"
assert_contains_286 "$claude_md_flat_334" 'tasks/telemetry-<task-id>-<zeitstempel>.csv' \
  "#334 Doku: FACTORY.md nennt den Ablageort"
assert_absent "$claude_md_flat_334" 'OTEL-Metriken (Token/Kosten/Nutzung pro Skill & Agent). Default aus' \
  "#334 Doku: die überholte 'Default aus'-Formulierung steht nicht mehr in FACTORY.md"

# Geprüft wird der Endzustand der COMMITTETEN Live-Datei, nicht tasks/patch-334.diff: das
# Patch-Artefakt ist transient, die Zusicherung hängt an der Datei, die Agenten wirklich
# lesen (Lesson nothra/tch-gastro-services#212). Die Datei liegt unter .claude/** und war für den Agenten gesperrt –
# der Patch-Umweg ändert nichts daran, was hier zu bewachen ist.
daily_metrics_flat_334=$(flat_286 "$FACTORY_ROOT/.claude/commands/daily-metrics.md")
assert_contains_286 "$daily_metrics_flat_334" 'tasks/telemetry-<task-id>-<zeitstempel>.csv' \
  "#334 Doku: daily-metrics.md verweist für Token/Kosten auf die persistierte Telemetrie-CSV"
assert_absent "$daily_metrics_flat_334" 'die liefert die Telemetrie-Ebene (OTEL, `config/otel.env.example`)' \
  "#334 Doku: daily-metrics.md nennt otel.env.example nicht mehr als DEN Telemetrie-Weg"

operating_flat_334=$(flat_286 "$OPERATING_MD")
assert_contains_286 "$operating_flat_334" 'Telemetrie (Token/Kosten) – Default an' \
  "#334 Doku: OPERATING.md §0.5 nennt den neuen Default"
assert_contains_286 "$operating_flat_334" 'run-pipeline.sh <task-id> --no-telemetry' \
  "#334 Doku: OPERATING.md nennt den Abschalt-Aufruf vollständig"
assert_contains_286 "$operating_flat_334" 'Jeder Task-PR trägt darum eine Telemetrie-CSV im Diff.' \
  "#334 Doku: OPERATING.md warnt vor der neuen Datei in jedem Diff"
assert_absent "$operating_flat_334" '`source config/otel.env.example` aktiviert' \
  "#334 Doku: OPERATING.md nennt otel.env.example nicht mehr als Aktivierungsweg"
# ── nothra/tch-gastro-services#426 T1a-1 · Zuordnungstabelle docs/factory/OWNERSHIP.md (AK-A1…A6, F-1) ─────────────────
# Jede getrackte Datei gehört genau einer Seite (factory | project). ownership-check.sh ist der
# einzige Parser des Zeilenformats; T1b leitet die filter-repo-Allowlist daraus ab (--list).
OWN_CHECK_426="$CHECKS_DIR/ownership-check.sh"

# Fixture-Tabelle + Dateiliste in einem Wegwerf-Verzeichnis; $1 = Tabellen-Zeilen, $2 = Dateien
own_run_426() {
  local dir; dir="$(mktemp -d)"
  printf '| Seite | Muster | Begründung |\n|---|---|---|\n%b' "$1" > "$dir/OWNERSHIP.md"
  printf '%b' "$2" > "$dir/files.txt"
  FACTORY_LOCK_FILE="$NO_LOCK_FILE" OWNERSHIP_FILE="$dir/OWNERSHIP.md" OWNERSHIP_FILE_LIST="$dir/files.txt" \
    bash "$OWN_CHECK_426" "${@:3}" 2>&1
  local rc=$?
  rm -rf "$dir"
  return $rc
}

# AK-A1/A5: ein Treffer je Datei, Glob-Semantik (`*` je Segment, `**` beliebig tief)
out_426="$(own_run_426 '| factory | `scripts/lib/**` | Lib |\n| project | `app/**` | App |\n| project | `*.md` | Wurzel |\n' \
  'scripts/lib/a/b.sh\napp/x/page.tsx\nREADME.md\n')"
assert_exit 0 $? "#426 AK-A5: vollständige, eindeutige Tabelle → Exit 0"
assert_contains_286 "$out_426" 'factory: 1, project: 2' \
  "#426 AK-A5: Ausgabe nennt die Verteilung je Seite"

# AK-A2 / F-1 (fehlt): Datei ohne Zuordnung → rot und Datei benannt
out_426="$(own_run_426 '| project | `app/**` | App |\n' 'app/a.ts\nscripts/neu.sh\n')"
assert_exit 1 $? "#426 AK-A2: Datei ohne Zuordnung → Exit 1"
assert_contains_286 "$out_426" 'scripts/neu.sh: keiner Seite zugeordnet' \
  "#426 AK-A2: die fehlende Datei wird namentlich genannt"
assert_absent "$out_426" 'app/a.ts:' "#426 AK-A2: zugeordnete Datei wird nicht gemeldet"

# AK-A2 / F-1 (doppelt): zwei Seiten treffen dieselbe Datei → rot, beide Muster genannt
out_426="$(own_run_426 '| factory | `scripts/**` | alles |\n| project | `scripts/nur-projekt.sh` | Projekt |\n' 'scripts/nur-projekt.sh\n')"
assert_exit 1 $? "#426 AK-A2: Datei mit Zuordnung zu beiden Seiten → Exit 1"
assert_contains_286 "$out_426" 'scripts/nur-projekt.sh: mehreren Seiten zugeordnet' \
  "#426 AK-A2: die doppelte Datei wird namentlich genannt"
assert_contains_286 "$out_426" 'factory: scripts/**, project: scripts/nur-projekt.sh' \
  "#426 AK-A2: beide konkurrierenden Muster stehen in der Meldung"

# Zwei Muster derselben Seite sind keine Doppelzuordnung
out_426="$(own_run_426 '| factory | `scripts/**` | a |\n| factory | `scripts/lib/*.sh` | b |\n' 'scripts/lib/x.sh\n')"
assert_exit 0 $? "#426 AK-A2: zwei Muster DERSELBEN Seite zählen nicht als doppelt"

# Glob-Grenzen: `*` überschreitet kein `/`; Regex-Sonderzeichen sind wörtlich (`.` ≠ beliebig)
own_run_426 '| project | `docs/*.md` | flach |\n' 'docs/a/b.md\n' > /dev/null
assert_exit 1 $? "#426 Glob: '*' reicht nicht über ein Pfadsegment hinaus"
own_run_426 '| project | `a.md` | exakt |\n' 'aXmd\n' > /dev/null
assert_exit 1 $? "#426 Glob: '.' im Muster ist ein wörtlicher Punkt"

# Fail-closed: leere Tabelle, fehlende Tabelle, leere Dateiliste
own_run_426 '' 'a.md\n' > /dev/null
assert_exit 2 $? "#426 fail-closed: Tabelle ohne Zeilen → Exit 2 (nicht still grün)"
FACTORY_LOCK_FILE="$NO_LOCK_FILE" OWNERSHIP_FILE=/nicht/vorhanden/OWNERSHIP.md OWNERSHIP_FILE_LIST=/dev/null bash "$OWN_CHECK_426" > /dev/null 2>&1
assert_exit 2 $? "#426 fail-closed: nicht lesbare Tabelle → Exit 2"
own_run_426 '| project | `**` | alles |\n' '' > /dev/null
assert_exit 2 $? "#426 fail-closed: leere Dateiliste → Exit 2"

# AK-A5: --list liefert die Allowlist einer Seite (Eingabe für T1b)
out_426="$(own_run_426 '| factory | `scripts/**` | f |\n| project | `app/**` | p |\n' 'scripts/a.sh\napp/b.ts\nscripts/c.sh\n' --list factory)"
assert_exit 0 $? "#426 AK-A5: --list factory läuft"
assert_true "$([ "$out_426" = "$(printf 'scripts/a.sh\nscripts/c.sh')" ]; echo $?)" \
  "#426 AK-A5: --list factory nennt genau die factory-Dateien"
own_run_426 '| factory | `a/**` | f |\n' 'a/x\n' --list beide > /dev/null
assert_exit 2 $? "#426 AK-A5: --list mit unbekannter Seite → Exit 2"

# AK-A1/A3/A4 gegen die ECHTE Tabelle und `git ls-files` (kein Fixture)
own_real_out="$(bash "$OWN_CHECK_426" 2>&1)"
own_real_rc=$?
assert_exit 0 "$own_real_rc" "#426 AK-A1/A6: jede getrackte Datei hat genau eine Seite (Modus des Repos – Tabelle oder Lock – + git ls-files)"
[ "$own_real_rc" -eq 0 ] || echo "$own_real_out" | head -20 | sed 's/^/      /'

# Ausgabe erst einsammeln, dann per Here-String greppen (nie `printf | grep -q`): bei einer Liste über dem
# Pipe-Puffer (~64 KB, die Projekt-Liste wächst mit jeder Datei) beendet `grep -q` früh, und `pipefail` macht
# aus dem SIGPIPE des Schreibers ein falsches Rot (Exit 141) – nur auf dem CI-Runner sichtbar (bash-gotchas #3).
# Bewusst OHNE Lock-Override: hier gilt der Modus des Repos (Tabelle im Factory-Repo, Lock im Konsumenten).
own_side_426() { local l; l="$(bash "$OWN_CHECK_426" --list "$1" 2>/dev/null)"; grep -qxF -- "$2" <<< "$l"; }
# Gegenprobe: ein Factory-Kern ist NICHT 'project' (sonst wäre jede Zeile trivial 'project')
own_side_426 factory scripts/run-pipeline.sh
assert_exit 0 $? "#426 AK-A4 (Kontrolle): scripts/run-pipeline.sh ist 'factory' zugeordnet"
own_side_426 project scripts/run-pipeline.sh
assert_exit 1 $? "#426 AK-A4 (Kontrolle): scripts/run-pipeline.sh ist NICHT 'project' zugeordnet"

# AK-A6: das Gate hängt im lokalen pre-push (Zeile des echten Aufrufs) UND in der Suite, die
# CI als factory-self-test fährt – ein bestehender Required Check, kein neuer Check-Name.
assert_true "$(grep -q 'ownership-check.sh' "$CHECKS_DIR/pre-push.sh"; echo $?)" \
  "#426 AK-A6: pre-push.sh ruft ownership-check.sh auf (lokales Gate)"
assert_true "$(grep -q 'bash scripts/checks/tests/run-tests.sh' "$FACTORY_ROOT/.github/workflows/factory-ci.yml"; echo $?)" \
  "#426 AK-A6: factory-self-test (CI) führt diese Suite aus – damit auch den Check oben"
# ── Factory-Issue #22 · Konsumenten-Vertrag: ownership-check.sh im Lock-Modus (AK2.15a/b, F-22.1/3/4) ─────────────────
# Mit `factory.lock` im Repo-Wurzelverzeichnis gilt allein der Lock (ADR 064 D2/D3); ohne Lock bleibt der Tabellenmodus
# oben unverändert. Der Lock ist das Release-Manifest (JSON); gelesen wird nur die Pfadmenge.
OWN_CHECK_22="$CHECKS_DIR/ownership-check.sh"

# mk_lock_fixture_22 <lock-json> <getrackte Dateien (\n-getrennt)> <Anpassungsstellen-Liste (roh)> → Verzeichnis mit
# factory.lock, files.txt, points.txt. `%b` in <getrackte Dateien>/<Liste> deutet \n und \r; <lock-json> ist roh.
mk_lock_fixture_22() {
  local dir; dir="$(mktemp -d)" || return 1
  printf '%s' "$1" > "$dir/factory.lock"
  printf '%b' "$2" > "$dir/files.txt"
  printf '%b' "$3" > "$dir/points.txt"
  printf '%s' "$dir"
}
# lock_json_22 <Lock-Pfade (\n-getrennt)> → Lock im Schema des Release-Manifests
lock_json_22() {
  printf '%b' "$1" | jq -R . | jq -s -c '{schema: 1, repo: "x/y", version: "v0", commit: "0", files: map({path: ., sha256: "0"})}'
}
# lock_check_22 <Fixture-Verzeichnis> [Argumente…] – ownership-check.sh im Fixture (stdout+stderr).
# Die Zuordnungstabelle fehlt absichtlich (TABLE_22 leer): der Lock-Modus darf sie nicht brauchen. PATH_22/BASH_22 ersetzen
# PATH und die Shell (Stub ohne jq); TABLE_22 setzt eine Tabelle daneben.
lock_check_22() {
  local dir="$1"; shift
  env PATH="${PATH_22:-$PATH}" FACTORY_LOCK_FILE="$dir/factory.lock" CUSTOMIZATION_POINTS_FILE="$dir/points.txt" \
    OWNERSHIP_FILE="${TABLE_22:-/nicht/vorhanden/OWNERSHIP.md}" OWNERSHIP_FILE_LIST="$dir/files.txt" \
    "${BASH_22:-bash}" "$OWN_CHECK_22" "$@" 2>&1
}
# write_all_project_table_22 <Datei> – Zuordnungstabelle, die ALLES der Seite `project` zuordnet: ein Rückfall in den Tabellenmodus
# ergäbe damit Exit 0 und fiele in den Negativtests (kaputter Lock) sofort auf.
write_all_project_table_22() {
  printf '| Seite | Muster | Begründung |\n|---|---|---|\n| project | `**` | alles |\n' > "$1"
}
# lock_run_22 <Lock-Pfade> <getrackte Dateien> <Anpassungsstellen> [Argumente…] – Fixture bauen, laufen lassen, aufräumen
lock_run_22() {
  local dir rc; dir="$(mk_lock_fixture_22 "$(lock_json_22 "$1")" "$2" "$3")"
  lock_check_22 "$dir" "${@:4}"; rc=$?
  rm -rf "$dir"; return $rc
}
# lock_bad_22 <Lock-Inhalt roh> – gültige Tabelle liegt daneben: ein Rückfall in den Tabellenmodus ergäbe Exit 0
lock_bad_22() {
  local dir rc; dir="$(mk_lock_fixture_22 "$1" 'a.md\n' 'CLAUDE.md\n')"
  write_all_project_table_22 "$dir/OWNERSHIP.md"
  TABLE_22="$dir/OWNERSHIP.md" lock_check_22 "$dir"; rc=$?
  rm -rf "$dir"; return $rc
}

# AK2.15a: Lock ohne OWNERSHIP.md → grün, Seite `factory` = Lock-Pfadmenge, Rest `project`
out_22="$(lock_run_22 'scripts/a.sh\nscripts/b.sh\n' 'scripts/a.sh\nscripts/b.sh\nCLAUDE.md\n' 'CLAUDE.md\n')"
assert_exit 0 $? "#22 AK2.15a: Lock ohne OWNERSHIP.md → Exit 0"
assert_contains_286 "$out_22" 'factory: 2, project: 1' "#22 AK2.15a: Verteilung = Lock-Pfadmenge gegen den Rest"
assert_contains_286 "$out_22" 'Modus: Lock' "#22 AK2.15a-3: die Ausgabe nennt den Modus"

# AK2.15a-2: --list je Seite, jede Datei genau einer Seite
out_22="$(lock_run_22 'scripts/a.sh\nscripts/b.sh\n' 'scripts/a.sh\nCLAUDE.md\nscripts/b.sh\ndocs/x.md\n' 'CLAUDE.md\n' --list factory)"
assert_exit 0 $? "#22 AK2.15a-2: --list factory im Lock-Modus"
assert_true "$([ "$out_22" = "$(printf 'scripts/a.sh\nscripts/b.sh')" ]; echo $?)" "#22 AK2.15a-2: --list factory nennt genau die Lock-Pfade"
out_22="$(lock_run_22 'scripts/a.sh\nscripts/b.sh\n' 'scripts/a.sh\nCLAUDE.md\nscripts/b.sh\ndocs/x.md\n' 'CLAUDE.md\n' --list project)"
assert_exit 0 $? "#22 AK2.15a-2: --list project im Lock-Modus"
assert_true "$([ "$out_22" = "$(printf 'CLAUDE.md\ndocs/x.md')" ]; echo $?)" "#22 AK2.15a-2: --list project nennt genau das Komplement"

# AK2.15a-3: Lock UND widersprüchliche Tabelle → allein der Lock entscheidet (kein Mischmodus)
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"scripts/a.sh","sha256":"0"}]}' 'scripts/a.sh\nREADME.md\n' 'README.md\n')"
printf '| Seite | Muster | Begründung |\n|---|---|---|\n| project | `scripts/**` | widerspricht dem Lock |\n' > "$dir_22/OWNERSHIP.md"
out_22="$(TABLE_22="$dir_22/OWNERSHIP.md" lock_check_22 "$dir_22")"
assert_exit 0 $? "#22 AK2.15a-3: widersprüchliche Tabelle neben dem Lock stört nicht (README.md ist in der Tabelle unzugeordnet)"
assert_contains_286 "$out_22" 'factory: 1, project: 1' "#22 AK2.15a-3: Ergebnis folgt dem Lock, nicht der Tabelle"
rm -rf "$dir_22"

# AK2.15b (Fall 1): Lock-Pfad nicht getrackt → Exit 1, Pfad + Signal „nicht getrackt“
out_22="$(lock_run_22 'scripts/a.sh\nscripts/weg.sh\n' 'scripts/a.sh\nCLAUDE.md\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 AK2.15b: Lock-Pfad ohne Datei → Exit 1"
assert_contains_286 "$out_22" 'scripts/weg.sh: nicht getrackt' "#22 AK2.15b: der fehlende Lock-Pfad wird namentlich genannt"
assert_absent "$out_22" 'Anpassungsstelle' "#22 AK2.15b: Fall 1 löst nicht das Signal von Fall 2 aus"
# AK2.15b (Fall 2): Anpassungsstelle im Lock → Exit 1, Pfad + Signal „Anpassungsstelle“
out_22="$(lock_run_22 'scripts/a.sh\nCLAUDE.md\n' 'scripts/a.sh\nCLAUDE.md\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 AK2.15b: Anpassungsstelle im Lock → Exit 1"
assert_contains_286 "$out_22" 'CLAUDE.md: Anpassungsstelle steht im Lock' "#22 AK2.15b: die Anpassungsstelle wird namentlich genannt"
assert_absent "$out_22" 'nicht getrackt' "#22 AK2.15b: Fall 2 löst nicht das Signal von Fall 1 aus"

# AK2.15b (Review-Fund): die Liste darf nicht still ins Leere laufen, wenn sie CRLF/Randleerraum trägt oder keinen Eintrag hat –
# sonst wäre die Prüfung „Anpassungsstelle im Lock“ fail-open (F-22.2).
out_22="$(lock_run_22 'scripts/a.sh\nCLAUDE.md\n' 'scripts/a.sh\nCLAUDE.md\n' '# Kommentar\r\nCLAUDE.md\r\n')"
assert_exit 1 $? "#22 AK2.15b: Anpassungsstellen-Liste mit CRLF-Zeilenenden greift trotzdem → Exit 1"
assert_contains_286 "$out_22" 'CLAUDE.md: Anpassungsstelle steht im Lock' "#22 AK2.15b: CRLF-Liste: die Anpassungsstelle wird namentlich genannt"
out_22="$(lock_run_22 'scripts/a.sh\nCLAUDE.md\n' 'scripts/a.sh\nCLAUDE.md\n' '   CLAUDE.md  \n')"
assert_exit 1 $? "#22 AK2.15b: Anpassungsstelle mit Leerzeichen am Rand greift trotzdem → Exit 1"
out_22="$(lock_run_22 'scripts/a.sh\n' 'scripts/a.sh\n' '# nur Kommentar\n\n')"
assert_exit 2 $? "#22 F-22.2: Anpassungsstellen-Liste ohne Eintrag → Exit 2 (nicht „keine Anpassungsstelle verletzt“)"
assert_contains_286 "$out_22" 'Anpassungsstellen' "#22 F-22.2: die Meldung zur leeren Liste nennt die Anpassungsstellen"

# Review-Fund (Iteration 2): die Fundzahl in der Schlusszeile ist die echte Zahl, auch jenseits von 255 (ein Exit-Code-Zähler wäre bei 255 gekappt)
out_22="$(lock_run_22 "$(seq -f 'x%g.txt' 1 300)\n" 'a.md\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 AK2.15b: 300 fehlende Lock-Pfade → Exit 1"
assert_contains_286 "$out_22" '300 Fund(e)' "#22 AK2.15b: die Schlusszeile nennt die echte Fundzahl (300, nicht auf 255 gekappt)"

# Security-Review (Task 22): ein Lock-Pfad, der wie eine echo-Option aussieht (`-n`, `-e`, `-E`), darf den Fundzähler nicht verschlucken –
# sonst endet ein Lock mit nicht getracktem Pfad „-n“ mit Exit 0 (fail-open im Ownership-Gate).
for opt_22 in -n -e -E; do
  out_22="$(lock_run_22 "$opt_22\n" 'a.md\n' 'CLAUDE.md\n')"
  assert_exit 1 $? "#22 Security: nicht getrackter Lock-Pfad '$opt_22' → Exit 1 (kein Fail-open durch echo-Option)"
  assert_contains_286 "$out_22" '1 Fund(e)' "#22 Security: Lock-Pfad '$opt_22' wird als Fund gezählt"
done

# F-22.4: doppelter Lock-Pfad → Exit 1 mit Pfad, nicht still zusammengefasst
out_22="$(lock_run_22 'scripts/a.sh\nscripts/a.sh\n' 'scripts/a.sh\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 F-22.4: doppelter Lock-Pfad → Exit 1"
assert_contains_286 "$out_22" 'scripts/a.sh: mehrfach im Lock' "#22 F-22.4: der doppelte Pfad wird namentlich genannt"

# F-22.3: Sonderzeichen und Leerzeichen wörtlich, keine Muster-Auswertung
out_22="$(lock_run_22 'a+b.sh\nx[1].md\ndir/mit leerzeichen.txt\n' 'a+b.sh\nx[1].md\ndir/mit leerzeichen.txt\nrest.md\n' 'CLAUDE.md\n' --list factory)"
assert_exit 0 $? "#22 F-22.3: Pfade mit '+', '[', Leerzeichen sind gültige Lock-Pfade"
assert_true "$([ "$out_22" = "$(printf 'a+b.sh\ndir/mit leerzeichen.txt\nx[1].md')" ]; echo $?)" "#22 F-22.3: genau diese Pfade stehen auf Seite factory"
out_22="$(lock_run_22 'a.b\n' 'aXb\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 F-22.3: '.' im Lock-Pfad ist kein Joker (aXb ≠ a.b)"
assert_contains_286 "$out_22" 'a.b: nicht getrackt' "#22 F-22.3: der Joker-Kandidat bleibt ein fehlender Pfad"
out_22="$(lock_run_22 'x*\n' 'xyz\n' 'CLAUDE.md\n')"
assert_exit 1 $? "#22 F-22.3: '*' im Lock-Pfad ist kein Glob"

# F-22.3 (Review-Fund): Nicht-ASCII-Pfade. `git ls-files` quotet sie standardmäßig ("docs/f\303\274r.md"); gegen echtes git prüfen,
# nicht gegen eine Dateiliste – sonst bliebe der Quoting-Fehler unsichtbar.
dir_22="$(mktemp -d)"
git -C "$dir_22" init -q; git -C "$dir_22" config user.email t@t.t; git -C "$dir_22" config user.name t
# Die Quoting-Regel gilt es zu belegen: nicht von einer globalen Git-Konfiguration abhängig machen (sonst wäre der Test zufällig grün).
git -C "$dir_22" config core.quotepath true; git -C "$dir_22" config commit.gpgsign false
mkdir -p "$dir_22/docs"; : > "$dir_22/docs/für.md"; : > "$dir_22/übung.md"; printf 'CLAUDE.md\n' > "$dir_22/points.txt"
printf '{"schema":1,"files":[{"path":"docs/für.md","sha256":"0"}]}' > "$dir_22/factory.lock"
git -C "$dir_22" add -A; git -C "$dir_22" commit -q -m init
umlaut_22() { FACTORY_DIR="$dir_22" FACTORY_LOCK_FILE="$dir_22/factory.lock" CUSTOMIZATION_POINTS_FILE="$dir_22/points.txt" bash "$OWN_CHECK_22" "$@" 2>&1; }
out_22="$(umlaut_22)"
assert_exit 0 $? "#22 F-22.3: Lock-Pfad mit Umlaut gegen echtes git ls-files → Exit 0 (kein Falsch-Rot durch Quoting)"
out_22="$(umlaut_22 --list factory)"
assert_true "$([ "$out_22" = 'docs/für.md' ]; echo $?)" "#22 F-22.3: --list factory nennt den Umlaut-Pfad unquotet"
out_22="$(umlaut_22 --list project | LC_ALL=C sort)"
assert_true "$([ "$out_22" = "$(printf 'factory.lock\npoints.txt\nübung.md')" ]; echo $?)" "#22 F-22.3: --list project nennt Umlaut-Dateien unquotet"
rm -rf "$dir_22"

# F-22.1: unlesbarer / leerer / ungültiger Lock → Exit 2 (fail-closed), kein Rückfall in den Tabellenmodus
lock_bad_22 '' > /dev/null;                                          assert_exit 2 $? "#22 F-22.1: leerer Lock → Exit 2, kein Tabellenmodus"
lock_bad_22 'das ist kein json' > /dev/null;                         assert_exit 2 $? "#22 F-22.1: Lock ohne gültiges JSON → Exit 2"
lock_bad_22 '{"schema":1,"files":[]}' > /dev/null;                   assert_exit 2 $? "#22 F-22.1: Lock ohne Pfadeintrag → Exit 2"
lock_bad_22 '{"schema":2,"files":[{"path":"a.md"}]}' > /dev/null;    assert_exit 2 $? "#22 F-22.1: unbekanntes Schema → Exit 2"
lock_bad_22 '{"schema":1,"files":[{"sha256":"0"}]}' > /dev/null;     assert_exit 2 $? "#22 F-22.1: Eintrag ohne Pfad → Exit 2"
out_22="$(lock_bad_22 '{"schema":2,"files":[{"path":"a.md"}]}')"
assert_contains_286 "$out_22" 'schema' "#22 F-22.1: die Meldung nennt das Schema als Ursache"
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"a.md"}]}' 'a.md\n' 'CLAUDE.md\n')"; chmod 000 "$dir_22/factory.lock"
if [ -r "$dir_22/factory.lock" ]; then
  echo "  (übersprungen: Lock trotz chmod 000 lesbar – Lauf als Superuser)"
else
  lock_check_22 "$dir_22" > /dev/null
  assert_exit 2 $? "#22 F-22.1: nicht lesbarer Lock → Exit 2"
fi
chmod 600 "$dir_22/factory.lock"; rm -rf "$dir_22"
# F-22.1 (Review-Fund): ein hängender Symlink `factory.lock` ist auch ein Lock – nicht „kein Lock“ (sonst stiller Rückfall in die Tabelle)
dir_22="$(mk_lock_fixture_22 '' 'a.md\n' 'CLAUDE.md\n')"; rm -f "$dir_22/factory.lock"; ln -s /nicht/vorhanden/ziel "$dir_22/factory.lock"
write_all_project_table_22 "$dir_22/OWNERSHIP.md"
out_22="$(TABLE_22="$dir_22/OWNERSHIP.md" lock_check_22 "$dir_22")"
assert_exit 2 $? "#22 F-22.1: hängender Symlink als factory.lock → Exit 2, kein Rückfall in den Tabellenmodus"
assert_contains_286 "$out_22" 'factory.lock' "#22 F-22.1: die Meldung zum hängenden Symlink nennt factory.lock"
rm -rf "$dir_22"

# F-22.1 (Messung): ohne jq im PATH → Exit 2 mit klarer Meldung, nicht Exit 0 (Stub bricht die Messung, nicht nur den Input).
# Der Stub enthält die üblichen Werkzeuge ohne jq (eine Obermenge dessen, was ownership-check.sh braucht). Der Test belegt, dass die
# jq-Prüfung vor allen anderen Werkzeugen greift – er hängt nicht an der Vollständigkeit dieser Liste.
NOJQ_TOOLS_22="bash dirname cat sort uniq comm grep awk sed mktemp rm tr git head"
nojq_22="$(mktemp -d)"
for t_22 in $NOJQ_TOOLS_22; do
  p_22="$(command -v "$t_22" 2>/dev/null)" && ln -s "$p_22" "$nojq_22/$t_22"
done
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"a.md"}]}' 'a.md\n' 'CLAUDE.md\n')"
out_22="$(PATH_22="$nojq_22" BASH_22="$nojq_22/bash" lock_check_22 "$dir_22")"
assert_exit 2 $? "#22 F-22.1: Lock-Modus ohne jq → Exit 2"
assert_contains_286 "$out_22" 'jq' "#22 F-22.1: die Meldung nennt jq"
rm -rf "$nojq_22" "$dir_22"

# F-22.2: Liste der Anpassungsstellen fehlt → Exit 2 (nicht „keine Anpassungsstelle verletzt“)
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"a.md"}]}' 'a.md\n' '')"; rm -f "$dir_22/points.txt"
out_22="$(lock_check_22 "$dir_22")"
assert_exit 2 $? "#22 F-22.2: fehlende Anpassungsstellen-Liste → Exit 2"
assert_contains_286 "$out_22" 'Anpassungsstellen' "#22 F-22.2: die Meldung nennt die Liste der Anpassungsstellen"
rm -rf "$dir_22"

# /test-Ergänzung (Zeilenabdeckung von ownership-check.sh per xtrace): fail-closed-Pfade ohne eigenen Test.
# Aufruffehler: unbekannter Parameter → Exit 2 mit Meldung (beide Modi teilen die Argument-Auswertung vor der Moduswahl)
out_22="$(lock_run_22 'a.md\n' 'a.md\n' 'CLAUDE.md\n' --unbekannt)"
assert_exit 2 $? "#22 /test: unbekannter Parameter → Exit 2 (auch mit Lock)"
assert_contains_286 "$out_22" 'unbekannter Parameter: --unbekannt' "#22 /test: die Meldung nennt den unbekannten Parameter"
# Dateiliste (Override für Tests) nicht lesbar → Exit 2 – im Lock-Modus und im Tabellenmodus, je mit der Meldung
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"a.md"}]}' 'a.md\n' 'CLAUDE.md\n')"; rm -f "$dir_22/files.txt"
out_22="$(lock_check_22 "$dir_22")"
assert_exit 2 $? "#22 /test: Lock-Modus mit nicht lesbarer Dateiliste → Exit 2"
assert_contains_286 "$out_22" 'Dateiliste nicht lesbar' "#22 /test: die Meldung nennt die nicht lesbare Dateiliste (Lock-Modus)"
write_all_project_table_22 "$dir_22/OWNERSHIP.md"
out_22="$(FACTORY_LOCK_FILE="$NO_LOCK_FILE" OWNERSHIP_FILE="$dir_22/OWNERSHIP.md" OWNERSHIP_FILE_LIST="$dir_22/files.txt" bash "$OWN_CHECK_22" 2>&1)"
assert_exit 2 $? "#22 /test: Tabellenmodus mit nicht lesbarer Dateiliste → Exit 2"
assert_contains_286 "$out_22" 'Dateiliste nicht lesbar' "#22 /test: die Meldung nennt die nicht lesbare Dateiliste (Tabellenmodus)"
rm -rf "$dir_22"
# Kein git-Repo und keine Dateiliste → `git ls-files` scheitert → Exit 2 (nie „keine Dateien, alles grün“)
dir_22="$(mktemp -d)"; printf '{"schema":1,"files":[{"path":"a.md"}]}' > "$dir_22/factory.lock"; printf 'CLAUDE.md\n' > "$dir_22/points.txt"
out_22="$(GIT_CEILING_DIRECTORIES="$(dirname "$dir_22")" FACTORY_DIR="$dir_22" FACTORY_LOCK_FILE="$dir_22/factory.lock" CUSTOMIZATION_POINTS_FILE="$dir_22/points.txt" bash "$OWN_CHECK_22" 2>&1)"
assert_exit 2 $? "#22 /test: Lock-Modus ohne git-Repo und ohne Dateiliste → Exit 2"
assert_contains_286 "$out_22" 'git ls-files fehlgeschlagen' "#22 /test: die Meldung nennt das fehlgeschlagene git ls-files"
rm -rf "$dir_22"
# Interner Fehler: scheitert `comm` selbst (Messung gebrochen per PATH-Stub), ist das Exit 2 – nicht „ein Fund“ und nicht grün
brkcomm_22="$(mktemp -d)"
for t_22 in $NOJQ_TOOLS_22 jq; do
  p_22="$(command -v "$t_22" 2>/dev/null)" && ln -s "$p_22" "$brkcomm_22/$t_22"
done
rm -f "$brkcomm_22/comm"; printf '#!/bin/sh\nexit 3\n' > "$brkcomm_22/comm"; chmod +x "$brkcomm_22/comm"
dir_22="$(mk_lock_fixture_22 '{"schema":1,"files":[{"path":"a.md"}]}' 'a.md\nb.md\n' 'CLAUDE.md\n')"
out_22="$(PATH_22="$brkcomm_22" BASH_22="$brkcomm_22/bash" lock_check_22 "$dir_22")"
assert_exit 2 $? "#22 /test: scheitert comm selbst → Exit 2 (interner Fehler, fail-closed)"
assert_contains_286 "$out_22" 'interner Fehler' "#22 /test: die Meldung nennt den internen Fehler"
rm -rf "$brkcomm_22" "$dir_22"

# AK2.15c: ohne Lock bleibt der Tabellenmodus – keine Moduszeile, Meldungen unverändert (Kontrolle zu den Tests oben)
out_22="$(own_run_426 '| project | `**` | alles |\n' 'a.md\n')"
assert_exit 0 $? "#22 AK2.15c: ohne Lock gilt die Tabelle (Exit 0)"
assert_absent "$out_22" 'Modus:' "#22 AK2.15c: der Tabellenmodus trägt keine Moduszeile (Ausgabe unverändert)"
# F-22.5: Alles, was die ausgelieferte Suite sourct oder als Fixture liest (tests/lib, tests/fixtures), liegt auf Seite `factory` –
# sonst fehlte es im Konsumenten, und die Suite bräche dort beim `source` ab (die Dateien selbst stehen auf Seite factory, ADR-064 D6).
for f_22 in "$CHECKS_DIR"/tests/lib/* "$CHECKS_DIR"/tests/fixtures/*; do
  own_side_426 factory "${f_22#"$FACTORY_ROOT"/}"
  assert_exit 0 $? "#22 F-22.5: ${f_22#"$FACTORY_ROOT"/} wird mit der Suite ausgeliefert (Seite factory)"
done

# ── nothra/tch-gastro-services#426 T1a-1 · ADRs trennen (AK-B1…B6, F-2) ────────────────────────────────────────────────
ADR_LINKS_426="$CHECKS_DIR/adr-links-check.sh"
# Der Verzeichnisname steht nur hier und wird zur Laufzeit eingesetzt: ein Fixture-Literal wie
# `<verzeichnis>/009-x.md` in DIESER Datei würde vom Link-Check selbst als toter Link gefunden
# (Content-Scan-Guard, dessen Phrase in der gescannten Datei steht – Lesson nothra/tch-gastro-services#319).
ADR_DIR_426="adr"

# Fixture-Repo mit je einer ADR pro Verzeichnis
adr_fixture_426() { # $1 = Verzeichnis
  mkdir -p "$1/docs/$ADR_DIR_426" "$1/docs/factory/$ADR_DIR_426" "$1/docs/specs" "$1/scripts"
  : > "$1/docs/$ADR_DIR_426/014-app.md"; : > "$1/docs/factory/$ADR_DIR_426/009-fac.md"
  git -C "$1" init -q
}

TMP_ADR_426="$(mktemp -d)"; adr_fixture_426 "$TMP_ADR_426"
printf '[ok](../%s/014-app.md) und [ok2](../factory/%s/009-fac.md#abschnitt)\n' "$ADR_DIR_426" "$ADR_DIR_426" \
  > "$TMP_ADR_426/docs/specs/s.md"
git -C "$TMP_ADR_426" add -A
FACTORY_DIR="$TMP_ADR_426" bash "$ADR_LINKS_426" > /dev/null 2>&1
assert_exit 0 $? "#426 AK-B3: lebende ADR-Links (relativ, mit Anker) → Exit 0"

# F-2: Link zeigt nach dem Umzug ins Leere → Quelle:Zeile und Ziel genannt
printf 'Zeile eins\n[alt](../%s/009-fac.md) – dort liegt sie seit dem Umzug nicht mehr\n' "$ADR_DIR_426" \
  > "$TMP_ADR_426/docs/specs/s.md"
git -C "$TMP_ADR_426" add -A
out_426="$(FACTORY_DIR="$TMP_ADR_426" bash "$ADR_LINKS_426" 2>&1)"
assert_exit 1 $? "#426 F-2: toter Markdown-ADR-Link → Exit 1"
assert_contains_286 "$out_426" "docs/specs/s.md:2: toter ADR-Link → ../$ADR_DIR_426/009-fac.md" \
  "#426 F-2: Quelle (Datei:Zeile) und Ziel werden genannt"

# wurzel-relative Pfadangabe in einem Skript (kein Markdown-Link)
printf '#!/bin/sh\ncat docs/%s/009-fac.md\n' "$ADR_DIR_426" > "$TMP_ADR_426/scripts/x.sh"
printf 'nichts\n' > "$TMP_ADR_426/docs/specs/s.md"
git -C "$TMP_ADR_426" add -A
out_426="$(FACTORY_DIR="$TMP_ADR_426" bash "$ADR_LINKS_426" 2>&1)"
assert_exit 1 $? "#426 F-2: toter wurzel-relativer ADR-Pfad im Skript → Exit 1"
assert_contains_286 "$out_426" "scripts/x.sh:2: toter ADR-Link → docs/$ADR_DIR_426/009-fac.md" \
  "#426 F-2: auch der Skript-Verweis wird mit Datei:Zeile genannt"
rm -rf "$TMP_ADR_426"

FACTORY_DIR="$TMP_ADR_426/nicht-vorhanden" bash "$ADR_LINKS_426" > /dev/null 2>&1
assert_exit 2 $? "#426 fail-closed: kein git-Repo → Exit 2 (nicht still grün)"

# AK-B3 gegen den echten Baum (inkl. Specs, Tasks, Lessons, Skripte)
out_426="$(bash "$ADR_LINKS_426" 2>&1)"
adr_links_rc_426=$?
assert_exit 0 "$adr_links_rc_426" "#426 AK-B3: im ganzen Repo zeigt kein ADR-Link ins Leere"
[ "$adr_links_rc_426" -eq 0 ] || echo "$out_426" | grep '^✗' | head -20 | sed 's/^/      /'

# AK-B1/B2: Zuordnung der ADR-Dateien (Anhang 1 der Spec, final in ADR-063 Nachtrag Q3)
FACTORY_ADR_NUMS_426="001 002 003 004 005 006 007 008 009 010 011 012 013 018 019 029 030 037 038 040 041 042 043 045 047 049 051 063 064"
adr_nums_426() { # $1 = Verzeichnis → Nummern der ADR-Dateien, eindeutig sortiert
  local f; for f in "$1"/[0-9][0-9][0-9]-*.md; do [ -e "$f" ] && basename "$f" | cut -c1-3; done | sort -u
}
assert_true "$([ "$(adr_nums_426 "$FACTORY_ROOT/docs/factory/adr" | tr '\n' ' ')" = "$FACTORY_ADR_NUMS_426 " ]; echo $?)" \
  "#426 AK-B1: docs/factory/adr/ enthält genau die Factory-ADRs (Nummern unverändert)"
leaked_426=""
for n_426 in $FACTORY_ADR_NUMS_426; do
  ls "$FACTORY_ROOT/docs/adr/$n_426"-*.md > /dev/null 2>&1 && leaked_426="$leaked_426 $n_426"
done
assert_true "$([ -z "$leaked_426" ]; echo $?)" \
  "#426 AK-B2: keine Factory-ADR liegt noch in docs/adr/ (Reste:${leaked_426:- keine})"
# (Die App-ADRs liegen im adoptierenden Projekt, nicht in der Factory-Auslieferung.)

# AK-B4: jedes ADR-README listet GENAU die ADRs seines Verzeichnisses
adr_readme_matches_426() { # $1 = Verzeichnis
  local listed on_disk
  listed="$(grep -oE '\]\([0-9]{3}-[^)]*\.md\)' "$1/README.md" | sed -E 's/^\]\(//; s/\)$//' | sort)"
  on_disk="$(cd "$1" && ls [0-9][0-9][0-9]-*.md | sort)"
  [ "$listed" = "$on_disk" ]
}
adr_readme_matches_426 "$FACTORY_ROOT/docs/factory/adr"
assert_exit 0 $? "#426 AK-B4: docs/factory/adr/README.md listet genau die Factory-ADRs"
TMP_RM_426="$(mktemp -d)"; : > "$TMP_RM_426/001-a.md"; : > "$TMP_RM_426/002-b.md"
printf '[a](001-a.md)\n' > "$TMP_RM_426/README.md"
adr_readme_matches_426 "$TMP_RM_426"
assert_exit 1 $? "#426 AK-B4 (Kontrolle): eine nicht gelistete ADR macht den Vergleich rot"
printf '[a](001-a.md) [b](002-b.md) [c](003-c.md)\n' > "$TMP_RM_426/README.md"
adr_readme_matches_426 "$TMP_RM_426"
assert_exit 1 $? "#426 AK-B4 (Kontrolle): ein gelisteter Geisterverweis macht den Vergleich rot"
rm -rf "$TMP_RM_426"

# AK-B5: aktive Projekt-Dateien nennen Factory-ADRs als `Factory-ADR-NNN` (Helfer `bare_factory_adr_426` in lib/assert-helpers.sh)
TMP_B5_426="$(mktemp -d)"
printf 'siehe ADR-018 und Factory-ADR-043 sowie ADR-014\n' > "$TMP_B5_426/probe.md"
out_426="$(bare_factory_adr_426 "$TMP_B5_426/probe.md" "$FACTORY_ADR_NUMS_426")"
assert_contains_286 "$out_426" 'ADR-018' "#426 AK-B5 (Kontrolle): ein bloßes ADR-018 wird als Factory-Verweis erkannt"
assert_absent "$out_426" 'ADR-043' "#426 AK-B5 (Kontrolle): Factory-ADR-043 ist korrekt präfixiert, kein Treffer"
assert_absent "$out_426" 'ADR-014' "#426 AK-B5 (Kontrolle): eine App-ADR (014) ist kein Treffer"
rm -rf "$TMP_B5_426"

# AK-B6: ADR-063 ist Accepted und trägt den Nachtrag mit den Detailentscheidungen Q1–Q6
ADR063_426="$FACTORY_ROOT/docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md"
adr063_flat_426="$(flat_286 "$ADR063_426")"
assert_contains_286 "$adr063_flat_426" '## Status Accepted' "#426 AK-B6: ADR-063 steht auf Accepted"
assert_absent "$adr063_flat_426" '## Status Proposed' "#426 AK-B6: ADR-063 steht nicht mehr auf Proposed"
for q_426 in Q1 Q2 Q3 Q4 Q5 Q6; do
  assert_contains_286 "$adr063_flat_426" "**$q_426 ·" "#426 AK-B6: der Nachtrag in ADR-063 entscheidet $q_426"
done

# ── nothra/tch-gastro-services#426 T1a-1 · Lessons trennen (AK-C1…C5, F-3) und Kleinfunde teilen (AK-L1) ──────────────
LESSONS_TSV_426="$CHECKS_DIR/tests/fixtures/lessons-split-426.tsv"
SKILLS_DIR_426="${SKILLS_DIR_426:-$FACTORY_ROOT/.claude/commands}"   # nur zur Vorab-Prüfung eines Patches

# lessons_split_check_426 <tsv> <factory-dir> <projekt-dir> → Meldungen je Abweichung, Exit 1 bei mindestens einer
# Je TSV-Zeile (Seite, Lesson, Überschrift): die Überschrift steht GENAU EINMAL in der Lesson der
# erwarteten Seite und NICHT in der gleichnamigen Lesson der anderen Seite (nichts verloren, nichts
# verdoppelt, nichts auf der falschen Seite).
lessons_split_check_426() {
  local tsv="$1" fac="$2" prj="$3" bad=0 side lesson heading dir other here there
  while IFS="$(printf '\t')" read -r side lesson heading; do
    case "$side" in ''|'#'*) continue ;; esac
    if [ "$side" = factory ]; then dir="$fac"; other="$prj"; else dir="$prj"; other="$fac"; fi
    # Die Überschriften tragen seit der Bereinigung qualifizierte Verweise (…/nothra/tch-gastro-services#<nr>); die
    # Fixture hält den Stand der Trennung unverändert – für den Vergleich wird die Qualifizierung zurückübersetzt.
    here="$(sed 's#nothra/tch-gastro-services\##\##g' "$dir/$lesson" 2>/dev/null | grep -cxF -- "### $heading")"
    there="$(sed 's#nothra/tch-gastro-services\##\##g' "$other/$lesson" 2>/dev/null | grep -cxF -- "### $heading")"
    if [ "${here:-0}" -ne 1 ] || [ "${there:-0}" -ne 0 ]; then
      echo "✗ ${lesson}: „${heading}“ (erwartet: ${side}) – dort ${here:-0}×, auf der anderen Seite ${there:-0}×"
      bad=1
    fi
  done < "$tsv"
  return $bad
}

# (AK-C1 – die App-Lessons liegen unter docs/project/lessons/ – entfällt: sie gehören dem adoptierenden Projekt.)

# AK-C2 / F-3: Kontrollen für die Prüfung selbst (Fixture), dann der echte Bestand
TMP_LS_426="$(mktemp -d)"; mkdir -p "$TMP_LS_426/f" "$TMP_LS_426/p"
printf '### Eins\n\ntext\n\n### Zwei\n' > "$TMP_LS_426/f/t.md"; printf '### Drei\n' > "$TMP_LS_426/p/t.md"
printf 'factory\tt.md\tEins\nfactory\tt.md\tZwei\nproject\tt.md\tDrei\n' > "$TMP_LS_426/t.tsv"
lessons_split_check_426 "$TMP_LS_426/t.tsv" "$TMP_LS_426/f" "$TMP_LS_426/p" > /dev/null
assert_exit 0 $? "#426 AK-C2 (Kontrolle): vollständig getrennter Fixture-Bestand → grün"
printf '### Eins\n' > "$TMP_LS_426/f/t.md"
out_426="$(lessons_split_check_426 "$TMP_LS_426/t.tsv" "$TMP_LS_426/f" "$TMP_LS_426/p")"
assert_exit 1 $? "#426 F-3: ein verlorener Eintrag macht die Prüfung rot"
assert_contains_286 "$out_426" 'Zwei' "#426 F-3: der verlorene Eintrag wird namentlich genannt"
printf '### Eins\n\n### Zwei\n' > "$TMP_LS_426/f/t.md"; printf '### Drei\n\n### Zwei\n' > "$TMP_LS_426/p/t.md"
out_426="$(lessons_split_check_426 "$TMP_LS_426/t.tsv" "$TMP_LS_426/f" "$TMP_LS_426/p")"
assert_exit 1 $? "#426 F-3: ein verdoppelter Eintrag (auf beiden Seiten) macht die Prüfung rot"
printf '### Eins\n\n### Zwei\n\n### Zwei\n' > "$TMP_LS_426/f/t.md"; printf '### Drei\n' > "$TMP_LS_426/p/t.md"
lessons_split_check_426 "$TMP_LS_426/t.tsv" "$TMP_LS_426/f" "$TMP_LS_426/p" > /dev/null
assert_exit 1 $? "#426 F-3: ein doppelt vorhandener Eintrag auf derselben Seite macht die Prüfung rot"
printf '### Eins\n\n### Zwei\n\n### Drei\n' > "$TMP_LS_426/f/t.md"; printf '' > "$TMP_LS_426/p/t.md"
lessons_split_check_426 "$TMP_LS_426/t.tsv" "$TMP_LS_426/f" "$TMP_LS_426/p" > /dev/null
assert_exit 1 $? "#426 F-3: ein Eintrag auf der falschen Seite macht die Prüfung rot"
rm -rf "$TMP_LS_426"

# Nur die Factory-Zeilen gegen die Factory-Lessons; die Projekt-Zeilen der Fixture betreffen die App-Lessons
# des adoptierenden Projekts (die Fixture selbst bleibt unverändert, siehe PROJECT-CONTEXT.md → erlaubte Stellen).
LESSONS_TSV_FAC_426="$(mktemp)"; awk -F'\t' '$1 == "factory" || /^#/' "$LESSONS_TSV_426" > "$LESSONS_TSV_FAC_426"
out_426="$(lessons_split_check_426 "$LESSONS_TSV_FAC_426" "$FACTORY_ROOT/docs/factory/lessons" "$(mktemp -d)")"
lessons_rc_426=$?
rm -f "$LESSONS_TSV_FAC_426"
assert_exit 0 "$lessons_rc_426" "#426 AK-C2: jeder Lesson-Eintrag steht genau einmal, auf seiner Seite (Rekonstruktion gegen den Stand der Trennung)"
[ "$lessons_rc_426" -eq 0 ] || echo "$out_426" | head -10 | sed 's/^/      /'
assert_true "$([ "$(grep -vc '^#' "$LESSONS_TSV_426")" -eq 175 ]; echo $?)" \
  "#426 AK-C2: die Rekonstruktions-Liste deckt alle 175 Einträge der sieben Ausgangs-Lessons ab"


# (AK-C4 – Kern-Kurzregeln mit Verweis auf die App-Lessons – entfällt: der Index des Factory-Repos hat keine.)

# AK-C5: /codify nennt beide Orte und die Zuordnungsregel (Live-Datei; Patch-Lieferung, siehe Task)
codify_flat_426="$(flat_286 "$SKILLS_DIR_426/codify.md")"
assert_contains_286 "$codify_flat_426" 'docs/factory/lessons/<thema>.md' "#426 AK-C5: /codify nennt den Factory-Ort der Lessons"
assert_contains_286 "$codify_flat_426" 'docs/project/lessons/<thema>.md' "#426 AK-C5: /codify nennt den Projekt-Ort der Lessons"
assert_contains_286 "$codify_flat_426" 'Zuordnungsregel' "#426 AK-C5: /codify beschreibt die Zuordnungsregel Factory vs. Projekt"
assert_contains_286 "$codify_flat_426" 'docs/factory/OWNERSHIP.md' "#426 AK-C5: die Zuordnungsregel verweist auf die Zuordnungstabelle"

# AK-L1: Kleinfunde nach betroffener Datei geteilt; die Skills nennen beide Orte
kf_side_426() { # $1 = Kleinfunde-Datei, $2 = erwartete Seite → Anzahl Einträge, deren erste Wo-Datei NICHT auf dieser Seite liegt
  local f bad=0 list; list="$(bash "$OWN_CHECK_426" --list "$2" 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qxF -- "$f" <<< "$list" || { echo "✗ $1: Wo-Datei $f liegt nicht auf Seite $2"; bad=$((bad + 1)); }
  done <<< "$(grep -oE '^- \*\*Wo:\*\* \[`[^`:]+' "$1" | sed -E 's/^- \*\*Wo:\*\* \[`//')"
  return $((bad > 0))
}
out_426="$(kf_side_426 "$FACTORY_ROOT/docs/factory/kleinfunde.md" factory)"
assert_exit 0 $? "#426 AK-L1: jeder Eintrag in docs/factory/kleinfunde.md betrifft eine Factory-Datei"
[ -z "$out_426" ] || echo "$out_426" | head -5 | sed 's/^/      /'
for sk_426 in review security-review codify; do
  sk_flat_426="$(flat_286 "$SKILLS_DIR_426/$sk_426.md")"
  assert_contains_286 "$sk_flat_426" 'docs/factory/kleinfunde.md' "#426 AK-L1: /$sk_426 nennt den Factory-Ort der Kleinfunde"
  assert_contains_286 "$sk_flat_426" 'docs/project/kleinfunde.md' "#426 AK-L1: /$sk_426 nennt den Projekt-Ort der Kleinfunde"
  assert_contains_286 "$sk_flat_426" 'docs/factory/OWNERSHIP.md' "#426 AK-L1: /$sk_426 nennt die Zuordnungsregel (betroffene Datei laut Tabelle)"
done

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe D: CLAUDE.md und FACTORY.md (AK-D1…D5) ─────────────────────────────
echo ""
echo "#431 AK-D: generischer Teil in FACTORY.md, CLAUDE.md dünn:"
FACTORY_MD_431="$FACTORY_ROOT/docs/factory/FACTORY.md"

# AK-D1/AK-D2: Datei-Anteile
assert_true "$([[ -f "$FACTORY_MD_431" ]]; echo $?)" "#431 AK-D1: docs/factory/FACTORY.md existiert"
for sec_431 in '## Kernprinzip' '## Nicht verhandelbare Prinzipien' '## Pipeline-Übersicht' '## Coding Guidelines' \
               '### Kern-Kurzregeln Git-Workflow (immer geladen)' '## Agent-Rollen' '## Work Tracking' \
               '## Guardrails' '## Self-Improvement Loop'; do
  grep -qxF -- "$sec_431" "$FACTORY_MD_431"
  assert_exit 0 "$?" "#431 AK-D1: FACTORY.md enthält den generischen Abschnitt '$sec_431'"
done
grep -qE '^# Development Factory · v[0-9]+\.[0-9]+\.[0-9]+$' "$FACTORY_MD_431"
assert_exit 0 "$?" "#431 AK-D1: FACTORY.md trägt die Versionsangabe"


# AK-D5: dieselben Dateien im Dauerkontext wie vor der Änderung (Baseline in der Task-Datei).
for g_431 in clean-code tdd-principles testing-standards; do
  grep -qxF "@docs/factory/guidelines/$g_431.md" "$FACTORY_MD_431"
  assert_exit 0 "$?" "#431 AK-D5: $g_431.md bleibt im Dauerkontext (Import in FACTORY.md)"
done

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe E: zusammengesetzte Dateien (AK-E1…E4, F-4) ────────────────────────
echo ""
echo "#431 AK-E: Fragmente + factory-sync.sh --compose:"
SYNC_431="$FACTORY_ROOT/scripts/factory-sync.sh"
assert_true "$([[ -f "$SYNC_431" ]]; echo $?)" "#431 AK-E3: scripts/factory-sync.sh existiert"
for f_431 in .claude/settings.factory.json docs/factory/gitignore.factory; do
  assert_true "$([[ -f "$FACTORY_ROOT/$f_431" ]]; echo $?)" "#431 AK-E1/E2: Factory-Fragment $f_431 existiert"
done
jq -e . "$FACTORY_ROOT/.claude/settings.factory.json" >/dev/null 2>&1
assert_exit 0 "$?" "#431 AK-E1: .claude/settings.factory.json ist gültiges JSON"

# compose_431 <wurzel> [args…] – führt den echten Compose-Modus gegen eine Fixture-Wurzel aus.
compose_431() { local r="$1"; shift; FACTORY_DIR="$r" bash "$SYNC_431" --compose "$@" 2>&1; }
# Fixture (Factory-Issue #23, AK-28a): die Factory-Fragmente stammen aus dem Repo (Seite factory), die Projekt-Fragmente baut
# der Test selbst – die ausgelieferte Suite liest weder Projekt-Fragmente noch committete zusammengesetzte Dateien des echten
# Repos (deren Zustand prüft die Projekt-Suite bzw. das Integritäts-Gate des Konsumenten).
fixture_431() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/.claude" "$d/docs/factory"
  cp "$FACTORY_ROOT/.claude/settings.factory.json" "$d/.claude/"
  cp "$FACTORY_ROOT/docs/factory/gitignore.factory" "$d/docs/factory/"
  printf '{"permissions":{"allow":["Bash(echo fixture:*)"]},"env":{"FIXTURE":"1"}}\n' > "$d/.claude/settings.project.json"
  printf 'fixture-ignore/\n' > "$d/.gitignore.project"
  printf '%s' "$d"
}
FX_431="$(fixture_431)"

# AK-E3: Zusammensetzung deterministisch, aus Factory- und Fixture-Fragment.
compose_431 "$FX_431" >/dev/null
assert_exit 0 "$?" "#431 AK-E3: --compose erzeugt beide Dateien"
compose_431 "$FX_431" --check >/dev/null
assert_exit 0 "$?" "#431 AK-E3: frisch zusammengesetzte Dateien == Zusammensetzung der Fragmente (--check)"
jq -e '.permissions.allow | index("Bash(echo fixture:*)")' "$FX_431/.claude/settings.json" >/dev/null 2>&1
assert_exit 0 "$?" "#431 AK-E3: settings.json enthält die Permission des Fixture-Projekt-Fragments"
assert_true "$([ "$(cat "$FX_431/.gitignore")" = "$(cat "$FACTORY_ROOT/docs/factory/gitignore.factory" "$FX_431/.gitignore.project")" ]; echo $?)" "#431 AK-E3: .gitignore = Factory-Fragment + Fixture-Projekt-Fragment"
first_431="$(cat "$FX_431/.claude/settings.json" "$FX_431/.gitignore" | cksum)"
compose_431 "$FX_431" >/dev/null
assert_true "$([ "$first_431" = "$(cat "$FX_431/.claude/settings.json" "$FX_431/.gitignore" | cksum)" ]; echo $?)" "#431 AK-E3: zweimal zusammengesetzt = gleiches Ergebnis"
# AK-28a: ein Projekt-Fragment mit anderem Inhalt ändert das Ergebnis, ohne dass ein Test es als „Ist“ voraussetzt
printf '{}\n' > "$FX_431/.claude/settings.project.json"; printf '' > "$FX_431/.gitignore.project"
compose_431 "$FX_431" >/dev/null
assert_exit 0 "$?" "#431 AK-28a: leere Projekt-Fragmente werden zusammengesetzt"
assert_true "$([ "$(cat "$FX_431/.gitignore")" = "$(cat "$FACTORY_ROOT/docs/factory/gitignore.factory")" ]; echo $?)" "#431 AK-28a: .gitignore bei leerem Projekt-Fragment = Factory-Fragment"
printf '{"permissions":{"allow":["Bash(echo fixture:*)"]}}\n' > "$FX_431/.claude/settings.project.json"; printf 'fixture-ignore/\n' > "$FX_431/.gitignore.project"
compose_431 "$FX_431" >/dev/null

# F-4: Abweichung je Seite → rot, mit Dateiname (Mutation: committete Datei bzw. Fragment ändern).
printf '\n# drift\n' >> "$FX_431/.gitignore"
out_431="$(compose_431 "$FX_431" --check)"; rc_431=$?
assert_exit 1 "$rc_431" "#431 F-4: abweichende .gitignore → --check rot"
assert_contains_286 "$out_431" '.gitignore' "#431 F-4: Meldung nennt die abweichende Datei"
compose_431 "$FX_431" >/dev/null
jq '.permissions.allow += ["Bash(echo drift:*)"]' "$FX_431/.claude/settings.json" > "$FX_431/x" && mv "$FX_431/x" "$FX_431/.claude/settings.json"
out_431="$(compose_431 "$FX_431" --check)"; rc_431=$?
assert_exit 1 "$rc_431" "#431 F-4: abweichende settings.json → --check rot"
assert_contains_286 "$out_431" 'settings.json' "#431 F-4: Meldung nennt settings.json"
compose_431 "$FX_431" >/dev/null
jq '.permissions.allow += ["Bash(echo frag:*)"]' "$FX_431/.claude/settings.project.json" > "$FX_431/x" && mv "$FX_431/x" "$FX_431/.claude/settings.project.json"
compose_431 "$FX_431" --check >/dev/null
assert_exit 1 "$?" "#431 F-4: geändertes Projekt-Fragment ohne neues Zusammensetzen → --check rot"
compose_431 "$FX_431" >/dev/null
jq -e '.permissions.allow | index("Bash(echo frag:*)")' "$FX_431/.claude/settings.json" >/dev/null
assert_exit 0 "$?" "#431 AK-E4: Projekt-Permission im Fragment erscheint nach --compose in settings.json"
# fail-closed: fehlendes Fragment
rm -f "$FX_431/.claude/settings.project.json"
compose_431 "$FX_431" >/dev/null
assert_exit 1 "$?" "#431 AK-E3: fehlendes Fragment → --compose bricht ab (fail-closed)"
FACTORY_DIR="$FX_431" bash "$SYNC_431" >/dev/null 2>&1
assert_exit 1 "$?" "#431 AK-E3: ohne Modus → exit 1"
rm -rf "$FX_431"

# AK-E1: Das Factory-Fragment trägt keine App-Pfade (die gehören dem Projekt-Fragment adoptierender Projekte).
jq -e '.permissions.allow | index("Edit(app/**)")' "$FACTORY_ROOT/.claude/settings.factory.json" >/dev/null 2>&1
assert_exit 1 "$?" "#431 AK-E1: Edit(app/**) steht nicht im Factory-Fragment"

# AK-E4: Doku nennt den Änderungsweg.
own_doc_431="$(flat_286 "$FACTORY_ROOT/docs/factory/OPERATING.md")"
assert_contains_286 "$own_doc_431" 'Projekt-Fragment ändern' "#431 AK-E4: OPERATING.md: Projekt-Fragment ändern"
assert_contains_286 "$own_doc_431" 'factory-sync.sh --compose' "#431 AK-E4: OPERATING.md nennt das Zusammensetz-Kommando"
assert_contains_286 "$own_doc_431" 'beide committen' "#431 AK-E4: OPERATING.md: Fragment und Ergebnis beide committen"

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe F: CI-Workflows (AK-F1…F4, F-7) ─────────────────────────────────────
echo ""
echo "#431 AK-F: factory-ci.yml nur Factory, ci.yml projekteigen:"
FCI_431="$FACTORY_ROOT/.github/workflows/factory-ci.yml"
jobs_of_431() { awk '/^jobs:/{j=1;next} j && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{sub(/^  /,"");sub(/:.*/,"");print}' "$1" | sort | tr '\n' ' '; }

assert_true "$([ "$(jobs_of_431 "$FCI_431")" = "config-validation factory-integrity factory-self-test issue-sync post-merge-verify pr-closes-issue " ]; echo $?)" \
  "#431 AK-F1: factory-ci.yml enthält genau die sechs Factory-Jobs (Ist: $(jobs_of_431 "$FCI_431"))"
grep -q 'pnpm' "$FCI_431"
assert_exit 1 "$?" "#431 AK-F1: factory-ci.yml enthält keinen pnpm-Aufruf"

# AK-F3/F-7: Required-Check-Namen (protect-main) = Menge der Job-Namen beider Factory-/Projekt-CI.
all_jobs_431="$(jobs_of_431 "$FCI_431")"
for chk_431 in issue-sync factory-self-test pr-closes-issue config-validation; do
  assert_contains_286 "$all_jobs_431" "$chk_431 " "#431 AK-F3: Required Check '$chk_431' wird von einem Workflow gemeldet"
done

miss_431=""
for wfp_431 in "$FCI_431" "$FACTORY_ROOT/.github/workflows/factory-poll.yml"; do
  for sp_431 in $(grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' "$wfp_431" | sort -u); do
    [[ -f "$FACTORY_ROOT/$sp_431" ]] || miss_431="$miss_431 $(basename "$wfp_431"):$sp_431"
  done
done
assert_true "$([ -z "$miss_431" ]; echo $?)" "#431 AK-F4: alle in Workflows genannten Skriptpfade existieren (fehlt:${miss_431:- nichts})"

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe G: Erweiterungspunkte in den Git-Gates (AK-G1…G4, F-5) ─────────────
echo ""
echo "#431 AK-G: pre-commit.d / pre-push.d:"
unset FACTORY_LINT_COMMAND FACTORY_TEST_COMMAND FACTORY_COVERAGE_COMMAND
GATE_LIB_431="$SCRIPTS_DIR/lib/gate-config.sh"

# mk_gate_root_431 <dir> – Wegwerf-Projektwurzel mit Kopie der Gates + Lib + Defaults auf einem Feature-Branch.
mk_gate_root_431() {
  mkdir -p "$1/scripts/checks" "$1/scripts/lib"
  cp "$CHECKS_DIR/pre-commit.sh" "$CHECKS_DIR/pre-push.sh" "$1/scripts/checks/"
  cp "$GATE_LIB_431" "$1/scripts/lib/"
  cp "$FACTORY_ROOT/factory.defaults.yml" "$1/"
  mk_feature_repo "$1" feature/431-gate-test
}
# run_gate_431 <root> <pre-commit|pre-push> [env…] – Gate mit neutralisierten Kommandos; stdout+stderr, Exit-Code via $RC_431.
run_gate_431() {
  local root="$1" gate="$2"; shift 2
  GATE_OUT_431="$( cd "$root" && env FACTORY_LINT_COMMAND=true FACTORY_TEST_COMMAND=true \
      FACTORY_TYPECHECK_COMMAND=true FACTORY_FORMAT_COMMAND=true "$@" \
      bash "scripts/checks/$gate.sh" 2>&1 )"
  RC_431=$?
}

TMP_G431="$(mktemp -d)"
mk_gate_root_431 "$TMP_G431"
for gate_431 in pre-push pre-commit; do
  d_431="$TMP_G431/scripts/project/checks/$gate_431.d"
  # AK-G2: Verzeichnis fehlt → Gate läuft ohne Fehler weiter; leer → ebenso.
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 0 "$RC_431" "#431 AK-G2: $gate_431 ohne Projekt-Verzeichnis → exit 0"
  mkdir -p "$d_431"
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 0 "$RC_431" "#431 AK-G2: $gate_431 mit leerem $gate_431.d → exit 0"
  : > "$d_431/.gitkeep"
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 0 "$RC_431" "#431 AK-G2: $gate_431: .gitkeep zählt nicht als Projekt-Check"

  # AK-G1: lexikalische Reihenfolge, Fehlschlag → rot mit Skriptname.
  printf '#!/usr/bin/env bash\necho b >> "%s/order.log"\n' "$TMP_G431" > "$d_431/20-zweiter.sh"
  printf '#!/usr/bin/env bash\necho a >> "%s/order.log"\n' "$TMP_G431" > "$d_431/10-erster.sh"
  chmod +x "$d_431/20-zweiter.sh" "$d_431/10-erster.sh"
  rm -f "$TMP_G431/order.log"
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 0 "$RC_431" "#431 AK-G1: $gate_431 führt grüne Projekt-Checks aus → exit 0"
  assert_true "$([ "$(tr -d '\n' < "$TMP_G431/order.log")" = "ab" ]; echo $?)" "#431 AK-G1: $gate_431: Projekt-Checks laufen lexikalisch (10-erster vor 20-zweiter)"
  printf '#!/usr/bin/env bash\necho kaputt-meldung\nexit 3\n' > "$d_431/15-rot.sh"; chmod +x "$d_431/15-rot.sh"
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 1 "$RC_431" "#431 AK-G1/F-5: $gate_431 mit fehlschlagendem Projekt-Check → exit 1"
  assert_contains_286 "$GATE_OUT_431" '15-rot.sh' "#431 AK-G1/F-5: $gate_431 nennt das fehlgeschlagene Skript"
  assert_contains_286 "$GATE_OUT_431" 'kaputt-meldung' "#431 AK-G1: $gate_431 zeigt die Ausgabe des fehlgeschlagenen Checks"
  rm -f "$d_431/15-rot.sh"

  # AK-G3: nicht ausführbar → rot mit Hinweis auf das Ausführbar-Bit.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d_431/30-nicht-ausfuehrbar.sh"
  run_gate_431 "$TMP_G431" "$gate_431"
  assert_exit 1 "$RC_431" "#431 AK-G3/F-5: $gate_431 mit nicht ausführbarer Datei → exit 1"
  assert_contains_286 "$GATE_OUT_431" '30-nicht-ausfuehrbar.sh' "#431 AK-G3: $gate_431 nennt die nicht ausführbare Datei"
  assert_contains_286 "$GATE_OUT_431" 'Ausführbar-Bit' "#431 AK-G3: $gate_431 weist auf das fehlende Ausführbar-Bit hin"
  rm -f "$d_431/30-nicht-ausfuehrbar.sh"
done
rm -rf "$TMP_G431"

# AK-G4 (Mechanik, neutral): ein Check im Erweiterungspunkt pre-push.d blockiert den Push, solange er rot ist;
# pre-push.sh selbst kennt keinen Projekt-Check namentlich. Die Prüfung am echten Routen-Check steht in der Projekt-Suite.
TMP_G4_431="$(mktemp -d)"
mk_gate_root_431 "$TMP_G4_431"
mkdir -p "$TMP_G4_431/scripts/project/checks/pre-push.d"
printf '#!/usr/bin/env bash\n[ -e "%s/drift" ] && { echo "drift-gefunden"; exit 1; }\nexit 0\n' "$TMP_G4_431" > "$TMP_G4_431/scripts/project/checks/pre-push.d/10-drift-check.sh"
chmod +x "$TMP_G4_431/scripts/project/checks/pre-push.d/10-drift-check.sh"
run_gate_431 "$TMP_G4_431" pre-push
assert_exit 0 "$RC_431" "#432 AK-G4 (neutral): Check im Erweiterungspunkt grün → pre-push exit 0"
: > "$TMP_G4_431/drift"
run_gate_431 "$TMP_G4_431" pre-push
assert_exit 1 "$RC_431" "#432 AK-G4 (neutral): Drift im Erweiterungspunkt-Check blockiert den Push (Verhaltenstest)"
assert_contains_286 "$GATE_OUT_431" '10-drift-check.sh' "#432 AK-G4 (neutral): die Meldung nennt den Projekt-Check"
rm -rf "$TMP_G4_431"

# mk_start_work_fixture_431 <tmp-dir> <factory.config.yml-Inhalt> – Wegwerf-Repo mit Defaults + Config + .env.local und
# gh-Stub (<tmp>/bin/gh); gibt den Repo-Pfad aus. Für die start-work-Tests der Gruppe H (Install-Schritt, Hinweis).
mk_start_work_fixture_431() {
  local tmp="$1" repo="$1/repo"
  mkdir -p "$tmp/bin" "$repo"
  printf '#!/bin/sh\ncase "$1 $2" in "issue create") echo "https://github.com/acme/demo/issues/901";; *) exit 0;; esac\n' > "$tmp/bin/gh"
  chmod +x "$tmp/bin/gh"
  git -C "$repo" init -q -b main; git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  cp "$FACTORY_ROOT/factory.defaults.yml" "$repo/"
  printf '%s\n' "$2" > "$repo/factory.config.yml"
  printf 'X=1\n' > "$repo/.env.local"
  git -C "$repo" add factory.defaults.yml factory.config.yml; git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}
# run_start_work_431 <tmp-dir> <repo> <worktree-unterordner> <task-id> <beschreibung> – stdout+stderr; Exit-Code des Skripts.
run_start_work_431() {
  ( cd "$2" && PATH="$1/bin:$PATH" FACTORY_DIR="$2" FACTORY_REPO=acme/demo \
      FACTORY_WORKTREE_BASE="$1/$3" bash "$SW" "$4" "$5" 2>&1 )
}

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe H: Gate-Kommandos aus der Konfiguration (AK-H1…H6, F-6) ─────────────
echo ""
echo "#431 AK-H: commands.* in factory.config.yml:"
if [ "$HAS_YQ" = 1 ]; then
  for k_431 in lint test typecheck format coverage; do
    d_431="$(yq ".commands.$k_431 // \"\"" "$FACTORY_ROOT/factory.defaults.yml")"
    assert_true "$([ -z "$d_431" ]; echo $?)" "#431 AK-H2: factory.defaults.yml hat keinen Default für commands.$k_431 (Ist: '$d_431')"
  done
  assert_true "$(! yq '.commands' "$FACTORY_ROOT/factory.defaults.yml" | grep -q pnpm; echo $?)" "#431 AK-H2: kein pnpm im commands-Block der Defaults"

  # AK-H3: die Gates lesen aus der Konfiguration; Env hat Vorrang.
  TMP_H3="$(mktemp -d)"
  mk_gate_root_431 "$TMP_H3"
  cat > "$TMP_H3/factory.config.yml" <<CFG
commands:
  lint: "touch '$TMP_H3/cfg-lint'"
  test: "touch '$TMP_H3/cfg-test'"
  typecheck: "touch '$TMP_H3/cfg-typecheck'"
  format: "touch '$TMP_H3/cfg-format'"
CFG
  ( cd "$TMP_H3" && env -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
      bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
  assert_exit 0 "$?" "#431 AK-H3: pre-push läuft allein mit commands.* aus der Config"
  for k_431 in test typecheck format; do
    assert_true "$([ -f "$TMP_H3/cfg-$k_431" ]; echo $?)" "#431 AK-H3: pre-push führt commands.$k_431 aus der Config aus"
  done
  ( cd "$TMP_H3" && env -u FACTORY_LINT_COMMAND bash scripts/checks/pre-commit.sh >/dev/null 2>&1 )
  assert_exit 0 "$?" "#431 AK-H3: pre-commit läuft allein mit commands.lint aus der Config"
  assert_true "$([ -f "$TMP_H3/cfg-lint" ]; echo $?)" "#431 AK-H3: pre-commit führt commands.lint aus der Config aus"
  rm -f "$TMP_H3"/cfg-*
  ( cd "$TMP_H3" && env -u FACTORY_LINT_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
      FACTORY_TEST_COMMAND="touch '$TMP_H3/env-test'" bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
  assert_true "$([ -f "$TMP_H3/env-test" ] && [ ! -f "$TMP_H3/cfg-test" ]; echo $?)" "#431 AK-H3: FACTORY_TEST_COMMAND hat Vorrang vor commands.test"
  # Leerer Format-Wert = übersprungen: per Env (Opt-out, schlägt die Config) und per leerer Config.
  rm -f "$TMP_H3"/cfg-* "$TMP_H3"/env-*
  ( cd "$TMP_H3" && env -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND \
      FACTORY_FORMAT_COMMAND="" bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
  assert_true "$([ ! -f "$TMP_H3/cfg-format" ]; echo $?)" "#431 AK-H3: leerer FACTORY_FORMAT_COMMAND überspringt das Format-Gate trotz commands.format"
  sed -i.bak 's|^  format: .*|  format: ""|' "$TMP_H3/factory.config.yml"; rm -f "$TMP_H3/factory.config.yml.bak"
  ( cd "$TMP_H3" && env -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
      bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
  assert_exit 0 "$?" "#431 AK-H3: leeres commands.format überspringt das Format-Gate (kein Fehler)"
  rm -rf "$TMP_H3"

  # AK-H4/F-6: Pflicht-Kommando fehlt in Config und Env → Gate bricht mit Schlüsselnamen ab (kein pnpm-Fallback).
  TMP_H4="$(mktemp -d)"
  mk_gate_root_431 "$TMP_H4"
  for k_431 in test typecheck; do
    args_431=(FACTORY_FORMAT_COMMAND=true)
    [ "$k_431" != test ] && args_431+=(FACTORY_TEST_COMMAND=true)
    [ "$k_431" != typecheck ] && args_431+=(FACTORY_TYPECHECK_COMMAND=true)
    out_431="$( cd "$TMP_H4" && env -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
        "${args_431[@]}" bash scripts/checks/pre-push.sh 2>&1 )"; rc_431=$?
    assert_exit 1 "$rc_431" "#431 AK-H4/F-6: pre-push ohne $k_431-Kommando → exit 1"
    assert_contains_286 "$out_431" "commands.$k_431" "#431 AK-H4/F-6: die Meldung nennt den Schlüssel commands.$k_431"
    assert_absent "$out_431" 'pnpm' "#431 AK-H4: kein stiller pnpm-Fallback für $k_431"
  done
  out_431="$( cd "$TMP_H4" && env -u FACTORY_LINT_COMMAND bash scripts/checks/pre-commit.sh 2>&1 )"; rc_431=$?
  assert_exit 1 "$rc_431" "#431 AK-H4/F-6: pre-commit ohne Lint-Kommando → exit 1"
  assert_contains_286 "$out_431" 'commands.lint' "#431 AK-H4/F-6: die Meldung nennt den Schlüssel commands.lint"
  rm -rf "$TMP_H4"

  # AK-H5: config-validation lehnt ungültigen Typ in commands.* ab (Positiv- und Negativtest).
  TMP_H5="$(mktemp -d)"
  CVC_431="$CHECKS_DIR/config-validation-check.sh"
  printf 'commands:\n  lint: "pnpm lint"\n  install: ""\nstart_work:\n  hint: "x"\n' > "$TMP_H5/ok.yml"
  bash "$CVC_431" "$FACTORY_ROOT/factory.defaults.yml" "$TMP_H5/ok.yml" >/dev/null 2>&1
  assert_exit 0 "$?" "#431 AK-H5: commands.* als Strings → gültig (Positivtest)"
  bash "$CVC_431" "$FACTORY_ROOT/factory.defaults.yml" "$FACTORY_ROOT/factory.config.yml" >/dev/null 2>&1
  assert_exit 0 "$?" "#431 AK-H5: die echte factory.config.yml ist gültig"
  for bad_431 in "lint: 5" "lint: true" "lint:" "lint: [a, b]" "lint: {a: b}" "neu: x"; do
    printf 'commands:\n  %s\n' "$bad_431" > "$TMP_H5/bad.yml"
    out_431="$(bash "$CVC_431" "$FACTORY_ROOT/factory.defaults.yml" "$TMP_H5/bad.yml" 2>&1)"; rc_431=$?
    assert_true "$([ "$rc_431" -ne 0 ]; echo $?)" "#431 AK-H5: ungültiges commands.* '$bad_431' → abgelehnt (exit $rc_431)"
  done
  printf 'commands:\n  lint: 5\n' > "$TMP_H5/bad.yml"
  out_431="$(bash "$CVC_431" "$FACTORY_ROOT/factory.defaults.yml" "$TMP_H5/bad.yml" 2>&1)"
  assert_contains_286 "$out_431" 'commands.lint' "#431 AK-H5: die Ablehnung nennt den Schlüssel commands.lint"
  printf 'start_work:\n  hint: 5\n' > "$TMP_H5/bad.yml"
  bash "$CVC_431" "$FACTORY_ROOT/factory.defaults.yml" "$TMP_H5/bad.yml" >/dev/null 2>&1
  assert_true "$([ "$?" -ne 0 ]; echo $?)" "#431 AK-H5: start_work.hint als Zahl → abgelehnt"
  rm -rf "$TMP_H5"
else
  skip_yq "#431 AK-H1…H5: commands.* (Config, Gates, Validierung)"
fi

# AK-H6: start-work: Install-Schritt + Seed-Hinweis aus der Config; ohne Eintrag entfällt der Schritt still.
if [ "$HAS_YQ" = 1 ]; then
  TMP_H6="$(mktemp -d)"
  REPO_H6="$(mk_start_work_fixture_431 "$TMP_H6" $'commands:\n  install: "touch install-ran.marker"\nstart_work:\n  hint: "Eigener Hinweis aus der Config"')"
  OUT_H6="$(run_start_work_431 "$TMP_H6" "$REPO_H6" wt 931 hint-test)"
  assert_true "$([ -f "$TMP_H6/wt/feature-931-hint-test/install-ran.marker" ]; echo $?)" "#431 AK-H6: start-work führt commands.install im Worktree aus"
  assert_contains_286 "$OUT_H6" 'Eigener Hinweis aus der Config' "#431 AK-H6: start-work gibt start_work.hint nach dem Kopieren der .env.local aus"
  assert_absent "$OUT_H6" 'db:seed' "#431 AK-H6: kein hartkodierter db:seed-Hinweis mehr im Skript"
  # Ohne Eintrag: kein Install-Schritt, kein Hinweis, kein Fehler.
  printf 'schemaVersion: 1\n' > "$REPO_H6/factory.config.yml"
  OUT_H6="$(run_start_work_431 "$TMP_H6" "$REPO_H6" wt2 932 ohne-eintrag)"; rc_431=$?
  assert_exit 0 "$rc_431" "#431 AK-H6: ohne commands.install/start_work.hint läuft start-work fehlerfrei"
  assert_true "$([ ! -f "$TMP_H6/wt2/feature-932-ohne-eintrag/install-ran.marker" ]; echo $?)" "#431 AK-H6: ohne commands.install entfällt der Install-Schritt"
  assert_absent "$OUT_H6" 'im Worktree (FACTORY_WT_SKIP_INSTALL' "#431 AK-H6: ohne commands.install keine Install-Meldung (still)"
  rm -rf "$TMP_H6"
else
  skip_yq "#431 AK-H6: start-work liest Install-Schritt und Hinweis aus der Config"
fi

# ─── nothra/tch-gastro-services#431 T1a-2 · Gruppe I: Labels aus der Konfiguration (AK-I1…I3) ─────────────────────────
echo ""
echo "#431 AK-I: labels.* in factory.defaults.yml / factory.config.yml:"
if [ "$HAS_YQ" = 1 ]; then
  DEF_431="$FACTORY_ROOT/factory.defaults.yml"; CFG_431="$FACTORY_ROOT/factory.config.yml"
  assert_true "$([ "$(yq -o=json -I=0 '.labels.kinds' "$DEF_431")" = '["bug","enhancement","documentation"]' ]; echo $?)" "#431 AK-I1: defaults tragen labels.kinds (bug, enhancement, documentation)"
  assert_true "$([ "$(yq -o=json -I=0 '.labels.aspects' "$DEF_431")" = '["security","tech-debt","test"]' ]; echo $?)" "#431 AK-I1: defaults tragen labels.aspects (security, tech-debt, test)"
  assert_true "$([ "$(yq -o=json -I=0 '.labels.aspects_extra' "$DEF_431")" = '[]' ]; echo $?)" "#431 AK-I1: defaults tragen labels.aspects_extra als leere Liste (keine projekteigenen Labels)"

  # Validierung (Regel 2 für Listen + Regel 8).
  TMP_I1="$(mktemp -d)"; CVC_I_431="$CHECKS_DIR/config-validation-check.sh"
  printf 'labels:\n  aspects_extra: [eins, zwei]\n' > "$TMP_I1/ok.yml"
  bash "$CVC_I_431" "$DEF_431" "$TMP_I1/ok.yml" >/dev/null 2>&1
  assert_exit 0 "$?" "#431 AK-I1: labels.aspects_extra mit gültigen Strings → gültig (Positivtest)"
  bash "$CVC_I_431" "$DEF_431" "$CFG_431" >/dev/null 2>&1
  assert_exit 0 "$?" "#431 AK-I1: die echte factory.config.yml ist gültig"
  for bad_431 in "aspects_extra: [mit leerraum]" "aspects_extra: ['a,b']" "aspects_extra: [5]" "aspects_extra: ['']" "aspects_extra: nur-ein-string" "aspects_extra: {a: b}" "unbekannt: [x]"; do
    printf 'labels:\n  %s\n' "$bad_431" > "$TMP_I1/bad.yml"
    bash "$CVC_I_431" "$DEF_431" "$TMP_I1/bad.yml" >/dev/null 2>&1
    assert_true "$([ "$?" -ne 0 ]; echo $?)" "#431 AK-I1: ungültiges labels.* '$bad_431' → abgelehnt"
  done
  rm -rf "$TMP_I1"

  # AK-I2: Drift-Guard gegen die neue Quelle (Funktion label_drift_431: assert-helpers.sh). Die PROJECT-CONTEXT.md ist eine
  # Anpassungsstelle des Konsumenten – die Suite baut ihre eigene Fixture und liest die des echten Repos nicht (Factory-Issue #28);
  # der Zustand der echten Datei im Factory-Repo steht in der Projekt-Suite.
  GW_431="$FACTORY_ROOT/docs/factory/guidelines/git-workflow.md"
  TMP_I2="$(mktemp -d)"
  printf 'labels:\n  aspects_extra: [fixture-label]\n' > "$TMP_I2/cfg-fx.yml"
  printf '# Fixture\n\n| Label | Aspekt |\n|-------|--------|\n| `fixture-label` | beschrieben |\n' > "$TMP_I2/pcx.md" \
    || { echo "run-tests: Fixture-PROJECT-CONTEXT.md nicht schreibbar (fail-closed, Factory-Issue #28 FS1)" >&2; exit 2; }
  PCX_431="$TMP_I2/pcx.md"
  # Positivkontrolle (AK3/FS2): beschriebenes Label + Tabellenformat der Fixture → keine Abweichung; sonst bewiesen die Mutationen nichts.
  assert_true "$([ -z "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg-fx.yml" "$GW_431" "$PCX_431")" ]; echo $?)" "#28 AK3: Fixture mit beschriebenem Label → Drift-Guard meldet keine Abweichung (Positivkontrolle)"
  # AK4: eigenes aspects_extra ohne Beschreibung in der Fixture betrifft nur den Guard-Aufruf mit dieser Config, nicht die Suite
  printf '# Fixture ohne Labelzeilen\n' > "$TMP_I2/pcx-leer.md"
  assert_contains_286 "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg-fx.yml" "$GW_431" "$TMP_I2/pcx-leer.md")" 'projekt-fehlt-in-PROJECT-CONTEXT:fixture-label' "#28 AK1/AK4: Fixture ohne Labelbeschreibung → Guard meldet es (die Suite selbst liest keine echte PROJECT-CONTEXT.md)"
  # FS2: weicht die Fixture vom gelesenen Tabellenformat ab (`| \`label\` |`), wird die Positivkontrolle rot statt der Mutationen
  printf '# Fixture\n\n| Label | Aspekt |\n| fixture-label | beschrieben |\n' > "$TMP_I2/pcx-format.md"
  assert_true "$([ -n "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg-fx.yml" "$GW_431" "$TMP_I2/pcx-format.md")" ]; echo $?)" "#28 FS2: Fixture ohne Backtick-Tabellenzeile → Drift-Guard meldet eine Abweichung (Positivkontrolle würde rot)"
  # Mutationen: je Seite eine eigene Assertion mit demselben Ausdruck.
  printf 'labels:\n  aspects_extra: [zzz-neu]\n' > "$TMP_I2/cfg.yml"
  assert_contains_286 "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg.yml" "$GW_431" "$PCX_431")" 'projekt-fehlt-in-PROJECT-CONTEXT:zzz-neu' "#431 AK-I2 (Mutation): ein Config-Label ohne Beschreibung in PROJECT-CONTEXT.md macht den Guard rot"
  grep -vF -- '| `security` |' "$GW_431" > "$TMP_I2/gw.md"
  assert_contains_286 "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg-fx.yml" "$TMP_I2/gw.md" "$PCX_431")" 'generisch-fehlt-in-git-workflow:security' "#431 AK-I2 (Mutation): ein generisches Label ohne Tabellenzeile in git-workflow.md macht den Guard rot"
  { cat "$GW_431"; printf '| `zzz-neu` | doppelt |\n'; } > "$TMP_I2/gw2.md"
  { cat "$PCX_431"; printf '| `zzz-neu` | beschrieben |\n'; } > "$TMP_I2/pc2.md"
  assert_contains_286 "$(label_drift_431 "$DEF_431" "$TMP_I2/cfg.yml" "$TMP_I2/gw2.md" "$TMP_I2/pc2.md")" 'projekt-steht-in-git-workflow:zzz-neu' "#431 AK-I2 (Mutation): ein projekteigenes Label in der generischen Tabelle macht den Guard rot"
  rm -rf "$TMP_I2"
  gw_flat_431="$(flat_286 "$GW_431")"
  assert_contains_286 "$gw_flat_431" 'PROJECT-CONTEXT.md' "#431 AK-I2: git-workflow.md verweist für projekteigene Labels auf PROJECT-CONTEXT.md"
  assert_contains_286 "$gw_flat_431" '`labels.aspects_extra`' "#431 AK-I2: git-workflow.md nennt labels.aspects_extra als Quelle der projekteigenen Labels"
  assert_absent "$gw_flat_431" '| `factory-pipeline` |' "#431 AK-I2: git-workflow.md trägt keine Zeile für das projekteigene Label mehr"
else
  skip_yq "#431 AK-I1/I2: labels.* (Config, Validierung, Drift-Guard)"
fi

# ─── Factory-Issue #28 AK6: die ausgelieferte Suite liest keine projekteigenen Dateien des echten Repos ───────────────
# Einzige begründete Ausnahme: factory.config.yml (der Konsument prüft seine eigene Config, Entscheidung Q1 in spec-28).
# Der Guard sucht Pfade der Form <Repo-Wurzel-Variable>/…<projekteigene Datei> und baut sein Muster zur Laufzeit zusammen,
# sonst träfe er sich in dieser Datei selbst (Lesson testing.md: Content-Scan-Guard mit Literal ist immer rot).
#
# Zweite Klasse (Factory-Issue #32): INDIREKTE Leser – ein Check-Skript, dem die echte Repo-Wurzel als Wurzel-Variable
# mitgegeben wird (`FACTORY_DIR=<echte Wurzel> bash <check>`), liest selbst CLAUDE.md/PROJECT-CONTEXT.md des Konsumenten.
# Fixture-Wurzeln (`$TMP_…`) treffen das Muster nicht; nur `$FACTORY_ROOT`/`$REPO_ROOT` als Wert zählt. Ein `env`-Präfix
# erfasst das Muster mit (kein Zeilenanfangs-Anker). Blind ist der Guard für den Direktaufruf eines Gates/Check-Skripts aus
# dem echten `$CHECKS_DIR` ohne Wurzel-Variable (Fund `#149`, per Fixture-Lauf gefunden) und für getrennte `export`-Zeilen.
project_reads_28() {
  local f out="" hits names="PROJECT-CONTEXT\\.md|gitignore\\.project|settings\\.project\\.json|CLAUDE\\.md|README\\.md|CHANGELOG\\.md"
  local real_root="[$]\\{?(FACTORY_ROOT|REPO_ROOT)\\}?" root_var="(FACTORY_DIR|FACTORY_ROOT|REPO_ROOT)"
  for f in "$@"; do
    [ -r "$f" ] || { out="$out UNLESBAR:$f"; continue; }
    hits="$(grep -nE "[$]\{?(FACTORY_ROOT|REPO_ROOT|FACTORY_DIR)\}?/[^ \"']*($names)" "$f")"
    [ -z "$hits" ] || out="$out $f:$(printf '%s' "$hits" | head -1 | cut -d: -f1)"
    hits="$(grep -nE "${root_var}=[\"']?${real_root}[\"']?[[:space:]]+(bash|sh)[[:space:]]" "$f")"
    [ -z "$hits" ] || out="$out $f:$(printf '%s' "$hits" | head -1 | cut -d: -f1)"
  done
  printf '%s' "$out"
}
SHIPPED_TESTS_28=("$SCRIPTS_DIR/checks/tests/run-tests.sh" "$SCRIPTS_DIR/checks/tests/factory-lock-tests.sh" "$SCRIPTS_DIR/checks/tests/lib/assert-helpers.sh")
assert_true "$([ -z "$(project_reads_28 "${SHIPPED_TESTS_28[@]}")" ]; echo $?)" "#28 AK6: die ausgelieferten Test-Dateien lesen keine projekteigene Datei des echten Repos (Ausnahme: factory.config.yml)"
TMP_28="$(mktemp -d)"; HELPERS_28="$SCRIPTS_DIR/checks/tests/lib/assert-helpers.sh"
# mutant_28 <Pfad-nach-Variable> → Kopie der Helfer-Lib mit einem ergänzten Lesezugriff nach $TMP_28/mut.sh (Pfad auf stdout)
mutant_28() { { cat "$HELPERS_28"; printf 'x="$(cat "%s")"\n' "$1"; } > "$TMP_28/mut.sh"; printf '%s' "$TMP_28/mut.sh"; }
for name_28 in docs/factory/PROJECT-CONTEXT.md .gitignore.project .claude/settings.project.json CLAUDE.md README.md CHANGELOG.md; do
  assert_contains_286 "$(project_reads_28 "$(mutant_28 "\$FACTORY_ROOT/$name_28")")" "$TMP_28/mut.sh:" "#28 AK6 (Mutation): Lesezugriff auf $name_28 ergänzt → Guard rot"
done
for var_28 in REPO_ROOT FACTORY_DIR; do
  assert_contains_286 "$(project_reads_28 "$(mutant_28 "\${$var_28}/CLAUDE.md")")" "$TMP_28/mut.sh:" "#28 AK6 (Mutation): Lesezugriff über \$$var_28 statt \$FACTORY_ROOT → Guard rot"
done
assert_true "$([ -z "$(project_reads_28 "$(mutant_28 "\$FACTORY_ROOT/factory.config.yml")")" ]; echo $?)" "#28 AK6 (Kontrolle): factory.config.yml ist die erlaubte Ausnahme"
# Indirekter Leser (Factory-Issue #32): Check-Skript gegen die echte Wurzel. Mutant-Zeile zur Laufzeit gebaut (kein Literal im Quelltext).
indirect_28() { { cat "$HELPERS_28"; printf '%s\n' "$1"; } > "$TMP_28/ind.sh"; printf '%s' "$TMP_28/ind.sh"; }
for root_28 in FACTORY_ROOT REPO_ROOT; do
  assert_contains_286 "$(project_reads_28 "$(indirect_28 "x=\"\$(FACTORY_DIR=\"\$$root_28\" bash \"\$CHK\" 2>&1)\"")")" "$TMP_28/ind.sh:" "#32 AK4 (Mutation): Check-Skript mit FACTORY_DIR=\$$root_28 aufgerufen → Guard rot"
done
assert_contains_286 "$(project_reads_28 "$(indirect_28 "FACTORY_DIR=\$FACTORY_ROOT"' bash "$CHK"')")" "$TMP_28/ind.sh:" "#32 AK4 (Mutation): Aufruf ohne Anführungszeichen um die Wurzel → Guard rot"
assert_contains_286 "$(project_reads_28 "$(indirect_28 "env FACTORY_DIR=\"\$FACTORY_ROOT\" bash \"\$CHK\"")")" "$TMP_28/ind.sh:" "#32 AK4 (Mutation): Aufruf über env-Präfix mit der echten Wurzel → Guard rot"
assert_true "$([ -z "$(project_reads_28 "$(indirect_28 'FACTORY_DIR="$TMP_FX" bash "$CHK" 2>&1')")" ]; echo $?)" "#32 AK4 (Kontrolle): Check-Skript gegen Fixture-Wurzel bleibt grün"
assert_contains_286 "$(project_reads_28 "$TMP_28/gibt-es-nicht.sh")" "UNLESBAR:$TMP_28/gibt-es-nicht.sh" "#28 AK6 (fail-closed): unlesbare Quelle → Guard rot statt still grün"
rm -rf "$TMP_28"

# AK-I3: Verhalten unverändert (Q5) – weder start-work.sh noch der Seam lesen die Label-Listen oder lehnen ab;
# die fail-open-Verhaltenstests ('Seam: fehlendes Aspekt-Label → Issue trotzdem angelegt') laufen oben unverändert.
grep -qE 'factory_cfg[[:space:]]+labels|labels\.(kinds|aspects)' "$SW" "$SCRIPTS_DIR/lib/create-issue.sh"
assert_exit 1 "$?" "#431 AK-I3: start-work.sh und Issue-Seam validieren nicht gegen labels.* (nur die Datenquelle wandert)"


# ─── nothra/tch-gastro-services#431 /test-Ergänzungen: Fail-closed bei unlesbarer Config, Fail-open beim Install-Schritt ───
echo ""
echo "#431 /test: yq defekt → Gate fail-closed; fehlgeschlagener Install-Schritt → Warnung:"
unset FACTORY_LINT_COMMAND FACTORY_TEST_COMMAND FACTORY_COVERAGE_COMMAND
TMP_T431="$(mktemp -d)"
mk_gate_root_431 "$TMP_T431"
printf 'commands:\n  test: "true"\n  typecheck: "true"\n  format: "true"\n  lint: "true"\n' > "$TMP_T431/factory.config.yml"
mkdir -p "$TMP_T431/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP_T431/bin/yq"; chmod +x "$TMP_T431/bin/yq"
# Kontrolle: mit funktionierendem yq läuft dasselbe Setup grün (sonst wäre das Rot unten nicht yq-bedingt).
( cd "$TMP_T431" && env -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
    bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
assert_exit 0 "$?" "#431 /test (Kontrolle): Config mit allen Kommandos und funktionierendem yq → pre-push exit 0"
out_t431="$( cd "$TMP_T431" && PATH="$TMP_T431/bin:$PATH" \
    env -u FACTORY_LINT_COMMAND -u FACTORY_TEST_COMMAND -u FACTORY_TYPECHECK_COMMAND -u FACTORY_FORMAT_COMMAND \
    bash scripts/checks/pre-push.sh 2>&1 )"; rc_t431=$?
assert_exit 1 "$rc_t431" "#431 /test: defektes yq (Config nicht lesbar) → pre-push blockiert fail-closed"
out_t431="$( cd "$TMP_T431" && PATH="$TMP_T431/bin:$PATH" env -u FACTORY_LINT_COMMAND bash scripts/checks/pre-commit.sh 2>&1 )"; rc_t431=$?
assert_exit 1 "$rc_t431" "#431 /test: defektes yq → pre-commit blockiert fail-closed"
# Env-Override braucht die Config nicht: mit allen Env-Kommandos läuft das Gate trotz defektem yq (Opt-out-Weg bleibt).
( cd "$TMP_T431" && PATH="$TMP_T431/bin:$PATH" FACTORY_TEST_COMMAND=true FACTORY_TYPECHECK_COMMAND=true FACTORY_FORMAT_COMMAND=true \
    bash scripts/checks/pre-push.sh >/dev/null 2>&1 )
assert_exit 0 "$?" "#431 /test: gesetzte Env-Kommandos brauchen die Config nicht – defektes yq blockiert dann nicht"
rm -rf "$TMP_T431"

if [ "$HAS_YQ" = 1 ]; then
  TMP_T2_431="$(mktemp -d)"
  REPO_T2_431="$(mk_start_work_fixture_431 "$TMP_T2_431" $'commands:\n  install: "false"')"
  out_t431="$(run_start_work_431 "$TMP_T2_431" "$REPO_T2_431" wt 933 install-fehlt)"; rc_t431=$?
  assert_exit 0 "$rc_t431" "#431 /test AK-H6: fehlgeschlagenes commands.install bricht start-work nicht ab (exit 0)"
  assert_contains_286 "$out_t431" 'false fehlgeschlagen' "#431 /test AK-H6: der fehlgeschlagene Install-Schritt erzeugt eine Warnung mit dem Kommando"
  assert_true "$([ -d "$TMP_T2_431/wt/feature-933-install-fehlt" ]; echo $?)" "#431 /test AK-H6: der Worktree besteht trotz fehlgeschlagenem Install"
  rm -rf "$TMP_T2_431"
else
  skip_yq "#431 /test AK-H6: fehlgeschlagener Install-Schritt"
fi

# ─── nothra/tch-gastro-services#432 T1a-3 · Gruppe K: Factory-Texte generisch (AK-K1, K1a, K2) ─────────────────────────
echo ""
echo "#432 AK-K: Factory-Texte ohne Stack-Begriffe des Ursprungs-Projekts:"
# Zur Laufzeit zusammengesetzt: als Literal stünden die Begriffe in dieser Datei selbst (C1-Guard unten).
STACK_RE_432="pnpm|Ne""on|Ver""cel|db:seed|Drizzle"
for txt_432 in docs/factory/agents/coding-agent.md docs/factory/agents/review-agent.md \
    docs/factory/guidelines/git-workflow.md docs/factory/guidelines/testing-standards.md \
    docs/factory/guidelines/bash-gotchas.md docs/factory/OPERATING.md; do
  grep -qE "$STACK_RE_432" "$FACTORY_ROOT/$txt_432"
  assert_exit 1 "$?" "#432 AK-K1: $txt_432 nennt keine Stack-Begriffe des Ursprungs-Projekts mehr"
done
IMPL_432="$FACTORY_ROOT/.claude/commands/implement.md"
grep -qE "$STACK_RE_432" "$IMPL_432"
assert_exit 1 "$?" "#432 AK-K1: .claude/commands/implement.md nennt keine Stack-Begriffe des Ursprungs-Projekts mehr (Endzustand der Live-Datei)"

# (AK-K2 – Inhalt von docs/project/betrieb.md – entfällt: das Betriebsdokument gehört dem adoptierenden Projekt.)
operating_flat_432="$(flat_286 "$FACTORY_ROOT/docs/factory/OPERATING.md")"
for ref_432 in '0.1' '0.2' '0.3' '1.4' '4.3'; do
  assert_contains_286 "$operating_flat_432" "project/betrieb.md\` → $ref_432" "#432 AK-K2: OPERATING.md verweist für $ref_432 auf betrieb.md"
done

# (AK-K1a – Abschnitt „Lokale Umgebung & Oberflächentests" in PROJECT-CONTEXT.md – entfällt: das Factory-Repo hat keine App-Umgebung.)

# ─── Release-Manifest (Factory-ADR-063 Q1, Factory-Issue #10) ────────────────────────────────
# factory-release-manifest.sh <ref> erzeugt das Manifest factory-release.json: Seite `factory` laut OWNERSHIP.md AM TAG,
# Pfad + SHA-256 je Blob (`git show <ref>:<pfad>`), nach Pfad sortiert (LC_ALL=C), unabhängig vom Arbeitsbaum.
echo ""
echo "Release-Manifest (Factory-Issue #10):"
RM_SCRIPT_10="$SCRIPTS_DIR/factory-release-manifest.sh"
assert_true "$([ -f "$RM_SCRIPT_10" ]; echo $?)" "Release-Manifest: scripts/factory-release-manifest.sh vorhanden"
if [ -f "$RM_SCRIPT_10" ] && command -v jq >/dev/null 2>&1; then
  TMP_RM_10="$(mktemp -d)"
  mkdir -p "$TMP_RM_10/scripts/checks" "$TMP_RM_10/docs/factory" "$TMP_RM_10/zz"
  cp "$RM_SCRIPT_10" "$TMP_RM_10/scripts/"; cp "$CHECKS_DIR/ownership-check.sh" "$TMP_RM_10/scripts/checks/"
  cat > "$TMP_RM_10/docs/factory/OWNERSHIP.md" <<'EOT'
| factory | `scripts/**` | Skripte |
| factory | `zz/b.txt` | Datei b |
| factory | `zz/a.txt` | Datei a |
| project | `README.md` | Projekt |
| project | `docs/factory/OWNERSHIP.md` | Tabelle |
EOT
  printf 'inhalt-a\n' > "$TMP_RM_10/zz/a.txt"; printf 'inhalt-b\n' > "$TMP_RM_10/zz/b.txt"; printf 'projekt\n' > "$TMP_RM_10/README.md"
  git -C "$TMP_RM_10" init -q -b main
  git -C "$TMP_RM_10" add -A
  git -C "$TMP_RM_10" -c user.email=t@t.com -c user.name=t commit -q -m init
  git -C "$TMP_RM_10" tag v9.9.9
  commit_rm_10="$(git -C "$TMP_RM_10" rev-parse HEAD)"
  # Arbeitsbaum NACH dem Tag verändern: das Manifest liest den Blob am Tag, nicht die Datei auf der Platte.
  printf 'geaendert\n' > "$TMP_RM_10/zz/a.txt"
  out_rm_10="$(cd "$TMP_RM_10" && bash scripts/factory-release-manifest.sh v9.9.9 2>&1)"; rc_rm_10=$?
  assert_exit 0 "$rc_rm_10" "Release-Manifest: Lauf gegen einen Tag endet mit Exit 0"
  assert_true "$(printf '%s' "$out_rm_10" | jq -e . >/dev/null 2>&1; echo $?)" "Release-Manifest: die Ausgabe ist gültiges JSON"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.schema')" = 1 ]; echo $?)" "Release-Manifest: schema = 1"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.repo')" = "nothra/dev-factory" ]; echo $?)" "Release-Manifest: repo = nothra/dev-factory"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.version')" = "v9.9.9" ]; echo $?)" "Release-Manifest: version = der Tag"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.commit')" = "$commit_rm_10" ]; echo $?)" "Release-Manifest: commit = die 40-stellige Commit-ID des Tags"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.files | map(.path) | join(",")')" = "scripts/checks/ownership-check.sh,scripts/factory-release-manifest.sh,zz/a.txt,zz/b.txt" ]; echo $?)" \
    "Release-Manifest: files = genau die Seite factory, nach Pfad sortiert (Projekt-Dateien fehlen)"
  sha_a_rm_10="$(git -C "$TMP_RM_10" show v9.9.9:zz/a.txt | shasum -a 256 | cut -d' ' -f1)"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.files[] | select(.path == "zz/a.txt") | .sha256')" = "$sha_a_rm_10" ]; echo $?)" \
    "Release-Manifest: sha256 stammt vom Blob am Tag (nicht vom geänderten Arbeitsbaum)"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.files[] | select(.path == "zz/a.txt") | .sha256')" != "$(shasum -a 256 < "$TMP_RM_10/zz/a.txt" | cut -d' ' -f1)" ]; echo $?)" \
    "Release-Manifest (Diskriminierung): der Hash weicht vom veränderten Arbeitsbaum ab"
  assert_true "$([ "$(printf '%s' "$out_rm_10" | jq -r '.files | map(.sha256) | map(test("^[0-9a-f]{64}$")) | all')" = true ]; echo $?)" "Release-Manifest: jeder Hash hat 64 Hex-Zeichen"
  # Der Modus von ownership-check.sh hängt am Arbeitsbaum (factory.lock im FACTORY_DIR); das Manifest liest aber die Tabelle AM TAG.
  # Ein Lock im Arbeitsbaum darf die Dateiliste des Tags nicht verändern (Review-Fund Iteration 1/2).
  printf '{"schema":1,"files":[{"path":"zz/b.txt","sha256":"0"}]}' > "$TMP_RM_10/factory.lock"
  out_lock_rm_10="$(cd "$TMP_RM_10" && bash scripts/factory-release-manifest.sh v9.9.9 2>&1)"; rc_lock_rm_10=$?
  assert_exit 0 "$rc_lock_rm_10" "Release-Manifest: Lauf mit factory.lock im Arbeitsbaum endet mit Exit 0"
  assert_true "$([ "$(printf '%s' "$out_lock_rm_10" | jq -r '.files | map(.path) | join(",")')" = "scripts/checks/ownership-check.sh,scripts/factory-release-manifest.sh,zz/a.txt,zz/b.txt" ]; echo $?)" \
    "Release-Manifest: ein factory.lock im Arbeitsbaum ändert die Dateiliste des Tags nicht (Tabellenmodus erzwungen)"
  rm -f "$TMP_RM_10/factory.lock"
  # Fail-closed
  (cd "$TMP_RM_10" && bash scripts/factory-release-manifest.sh v0.0.0-gibt-es-nicht >/dev/null 2>&1)
  assert_exit 2 "$?" "Release-Manifest: unbekannte Referenz → Exit 2 (fail-closed)"
  (cd "$TMP_RM_10" && bash scripts/factory-release-manifest.sh >/dev/null 2>&1)
  assert_exit 2 "$?" "Release-Manifest: ohne Referenz → Exit 2"
  git -C "$TMP_RM_10" rm -q --cached docs/factory/OWNERSHIP.md
  git -C "$TMP_RM_10" -c user.email=t@t.com -c user.name=t commit -q -m "ohne tabelle"
  git -C "$TMP_RM_10" tag v9.9.8
  (cd "$TMP_RM_10" && bash scripts/factory-release-manifest.sh v9.9.8 >/dev/null 2>&1)
  assert_exit 2 "$?" "Release-Manifest: Tag ohne OWNERSHIP.md → Exit 2 (fail-closed)"
  rm -rf "$TMP_RM_10"
else
  [ -f "$RM_SCRIPT_10" ] || true
  command -v jq >/dev/null 2>&1 || echo "  • Release-Manifest: Verhaltenstests übersprungen (jq fehlt)"
fi

# ─── Release-Prüfung und release.yml (Factory-ADR-063 D6/Q1, Factory-Issue #10) ──────────────────
# factory-release-check.sh <tag>: Version in FACTORY.md == Tag und ein CHANGELOG-Abschnitt zum Tag (fail-closed);
# --notes <tag> gibt genau diesen Abschnitt aus (Release Notes). release.yml verdrahtet beides mit dem Manifest.
echo ""
echo "Release-Prüfung (Factory-Issue #10):"
RC_SCRIPT_10="$SCRIPTS_DIR/factory-release-check.sh"
assert_true "$([ -f "$RC_SCRIPT_10" ]; echo $?)" "Release-Prüfung: scripts/factory-release-check.sh vorhanden"
if [ -f "$RC_SCRIPT_10" ]; then
  TMP_RC_10="$(mktemp -d)"; mkdir -p "$TMP_RC_10/docs/factory"
  printf '# Development Factory · v1.2.3\n\ntext\n' > "$TMP_RC_10/docs/factory/FACTORY.md"
  printf '# Changelog\n\n## Unreleased\n\n- später\n\n## v1.2.3 – 2026-01-01\n\n### Breaking\n\n- keine\n\n## v1.2.2 – 2025-12-01\n\n- alt\n' > "$TMP_RC_10/CHANGELOG.md"
  rc_10() { FACTORY_DIR="$TMP_RC_10" bash "$RC_SCRIPT_10" "$@"; }
  rc_10 v1.2.3 >/dev/null 2>&1
  assert_exit 0 "$?" "Release-Prüfung: Version und CHANGELOG-Abschnitt passen zum Tag → Exit 0"
  out_rc_10="$(rc_10 v1.2.4 2>&1)"; rc_rc_10=$?
  assert_exit 1 "$rc_rc_10" "Release-Prüfung: Tag ≠ Version in FACTORY.md → Exit 1"
  assert_contains_286 "$out_rc_10" 'v1.2.3' "Release-Prüfung: die Meldung nennt die Version aus FACTORY.md"
  printf '# Development Factory · v1.2.4\n' > "$TMP_RC_10/docs/factory/FACTORY.md"
  out_rc_10="$(rc_10 v1.2.4 2>&1)"; rc_rc_10=$?
  assert_exit 1 "$rc_rc_10" "Release-Prüfung: Version passt, aber kein CHANGELOG-Abschnitt zum Tag → Exit 1"
  assert_contains_286 "$out_rc_10" 'CHANGELOG' "Release-Prüfung: die Meldung nennt den fehlenden CHANGELOG-Abschnitt"
  rc_10 1.2.3 >/dev/null 2>&1
  assert_exit 2 "$?" "Release-Prüfung: ein Tag ohne führendes v → Exit 2 (Aufruffehler)"
  rc_10 >/dev/null 2>&1
  assert_exit 2 "$?" "Release-Prüfung: ohne Tag → Exit 2"
  printf '# Development Factory · v1.2.3\n' > "$TMP_RC_10/docs/factory/FACTORY.md"
  notes_rc_10="$(rc_10 --notes v1.2.3 2>&1)"; rc_rc_10=$?
  assert_exit 0 "$rc_rc_10" "Release-Prüfung: --notes liefert den Abschnitt zum Tag"
  assert_contains_286 "$notes_rc_10" '### Breaking' "Release-Prüfung: die Notes enthalten den Abschnitt „Breaking“"
  assert_absent "$notes_rc_10" 'später' "Release-Prüfung: die Notes enthalten keinen fremden Abschnitt (Unreleased)"
  assert_absent "$notes_rc_10" 'alt' "Release-Prüfung: die Notes enden vor dem nächsten Abschnitt"
  assert_absent "$notes_rc_10" '## v1.2.3' "Release-Prüfung: die Überschrift des Abschnitts ist nicht Teil der Notes"
  rc_10 --notes v9.9.9 >/dev/null 2>&1
  assert_exit 1 "$?" "Release-Prüfung: --notes ohne Abschnitt → Exit 1"
  rm -rf "$TMP_RC_10"
fi


# ─── Hook-Umgebung: GIT_DIR & Co. schlagen nicht in Wegwerf-Repos durch (Factory-Issue #6) ───────
# Läuft die Suite als commands.test aus dem pre-push-Hook eines Worktrees, exportiert Git GIT_DIR/GIT_WORK_TREE/
# GIT_INDEX_FILE – ohne Neutralisierung ändern die Wegwerf-Repos der Tests den echten Worktree (Branch, Remote, Dateien).
echo ""
echo "Hook-Umgebung (Factory-Issue #6): Suite-Helfer neutralisieren repo-lokale Git-Variablen:"
TMP_ENV_6="$(mktemp -d)"
git init -q "$TMP_ENV_6/decoy"
git init -q "$TMP_ENV_6/probe"
env_toplevel_6="$(GIT_DIR="$TMP_ENV_6/decoy/.git" GIT_WORK_TREE="$TMP_ENV_6/decoy" GIT_INDEX_FILE="$TMP_ENV_6/decoy/.git/index" \
  bash -c 'source "$1/tests/lib/assert-helpers.sh"; cd "$2" && git rev-parse --show-toplevel' _ "$CHECKS_DIR" "$TMP_ENV_6/probe")"
assert_true "$([ "$(cd "$env_toplevel_6" && pwd -P)" = "$(cd "$TMP_ENV_6/probe" && pwd -P)" ]; echo $?)" \
  "Hook-Umgebung: mit gesetztem GIT_DIR löst git nach dem Sourcen der Helfer das Wegwerf-Repo auf, nicht das Original"
for var_env_6 in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY; do
  left_env_6="$(env "$var_env_6=/nicht/da" bash -c 'source "$1/tests/lib/assert-helpers.sh"; printf %s "${!2-unset}"' _ "$CHECKS_DIR" "$var_env_6")"
  assert_true "$([ "$left_env_6" = unset ]; echo $?)" "Hook-Umgebung: $var_env_6 ist nach dem Sourcen der Helfer nicht mehr gesetzt"
done
rm -rf "$TMP_ENV_6"

# ─── Factory-Issue #23: Abholen, factory.lock, Integritäts-Gate ───────────────────────────────────
source "$CHECKS_DIR/tests/factory-lock-tests.sh" || {
  echo "run-tests: Testgruppe nicht ladbar: $CHECKS_DIR/tests/factory-lock-tests.sh (fail-closed)" >&2
  exit 2
}

# ─── Ergebnis ────────────────────────────────────────────────────────────────
print_summary
