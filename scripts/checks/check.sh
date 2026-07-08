#!/usr/bin/env bash
# check.sh – Zentraler Check-Dispatcher
#
# Wird durch Claude Code Hooks aufgerufen (.claude/settings.json).
# Routet zu spezifischen Check-Funktionen basierend auf Event-Typ und Input.
#
# Tool-Input-Kontrakt (siehe ADR-003):
#   Claude Code übergibt den Hook-Input als JSON über stdin – NICHT über eine
#   Env-Var. Dieses Skript ist die einzige Stelle, die das JSON parst; Sub-Checks
#   bekommen den fertigen Befehls-String als $1 und parsen selbst kein JSON.
#
# Verwendung: bash scripts/checks/check.sh <event-type>
#   (Hook-JSON kommt über stdin; pre-commit/pre-push/completion brauchen keins)
#
# Performance-Ziel: < 50ms für einfache Checks (kein Overhead durch Tool-Calls)

set -euo pipefail

CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT_TYPE="${1:-}"

# Kein Check bei leerem Event
[ -z "$EVENT_TYPE" ] && exit 0

# ─── Tool-Input aus stdin lesen (nur für Tool-Events) ────────────────────────
# Claude Code liefert das Hook-JSON über stdin; der Bash-Befehl steht unter
# .tool_input.command. Ohne stdin-Daten oder ohne jq bleibt TOOL_INPUT leer –
# dann greifen die Checks nicht, blockieren den Nutzer aber auch nicht.
TOOL_INPUT=""

read_tool_input() {
  # Nicht von einem Terminal lesen – das würde interaktiv blockieren.
  [ -t 0 ] && return 0
  local hook_json
  hook_json="$(cat)" || return 0
  [ -z "$hook_json" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  TOOL_INPUT="$(printf '%s' "$hook_json" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
}

# Optionaler Sub-Check: wird nur ausgeführt, wenn das Skript existiert.
# Fehlt es (z.B. auf einem Branch ohne dieses Feature), wird nicht blockiert.
run_optional_check() {
  local script="$CHECKS_DIR/$1"; shift
  [ -f "$script" ] || return 0
  bash "$script" "$@"
}

case "$EVENT_TYPE" in
  "pre-tool")
    read_tool_input
    # Branch-Naming bei Branch-Erstellung (checkout -b/-B, switch -c/-C)
    if echo "$TOOL_INPUT" | grep -qE 'checkout -[bB]|switch -[cC]'; then
      run_optional_check branch-name-check.sh "$TOOL_INPUT" || exit 1
    fi

    # Kontext-Snapshot + main/master-Guard vor invasiven Git-Operationen
    if echo "$TOOL_INPUT" | grep -qE 'git (commit|push|rebase|reset|merge|cherry-pick|tag)'; then
      run_optional_check git-context-check.sh "$TOOL_INPUT" || exit 1
    fi
    ;;

  "post-tool")
    read_tool_input
    # (derzeit keine aktiven Post-Checks)
    ;;

  "pre-commit")
    bash "$CHECKS_DIR/pre-commit.sh" || exit 1
    ;;

  "pre-push")
    bash "$CHECKS_DIR/pre-push.sh" || exit 1
    ;;

  "completion")
    bash "$CHECKS_DIR/completion-check.sh" || exit 1
    ;;

  *)
    # Unbekannter Event-Typ – ignorieren, nicht blockieren
    exit 0
    ;;
esac
