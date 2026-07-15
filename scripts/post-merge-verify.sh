#!/usr/bin/env bash
# post-merge-verify.sh – verifiziert das Verhalten in der ECHTEN Umgebung nach
# dem Merge. CI-grün ≠ Produktion-grün (ADR-007).
#
# Verwendung: bash scripts/post-merge-verify.sh [<task-id>]
#
# Konfiguration (CI/CD-Variablen) – zwei Check-Arten, CMD hat Vorrang vor URL:
#   FACTORY_HEALTHCHECK_CMD       Beliebiger Smoke-Test; Exit-Code = Urteil (0 = OK).
#                                 Für nicht-HTTP-Projekte (CLI, Worker) oder mehrstufige
#                                 Szenarien. Hat Vorrang, wenn gesetzt.
#   FACTORY_HEALTHCHECK_URL       HTTP-Healthcheck-URL (der bequeme Default).
#                                 ⚠ NICHT auf .../api/health zeigen: Dieser Job läuft beim
#                                 main-Push parallel zum Deploy-Gate, also VOR dem Promote
#                                 main→production. Ein /api/health-Check träfe den
#                                 Vor-Promote-Stand → Fehlalarme. Der autoritative
#                                 Post-Deploy-Healthcheck liegt im Deploy-Gate (nach dem
#                                 Promote), nicht hier (ADR-017 §Alternatives).
#   FACTORY_HEALTHCHECK_STATUS    Erwarteter HTTP-Status für die URL (Default: 200).
#   FACTORY_HEALTHCHECK_RETRIES   Zusätzliche Versuche nach dem ersten (Default 3) –
#                                 fängt Deploy-Lag ab (#24): direkt nach dem Merge ist
#                                 das Deployment evtl. noch nicht live.
#   FACTORY_HEALTHCHECK_INTERVAL  Basis-Wartezeit zwischen Versuchen in Sekunden
#                                 (Default 10), linearer Backoff (10s, 20s, 30s …).
#
# Erfolg beim ersten Versuch bleibt schnell (kein künstliches Warten). Erst wenn
# alle Versuche scheitern → POST_MERGE_FAIL-Interrupt (ADR-004) und roter Job.
#
# Bewusste "skip vs. fail"-Entscheidung (ADR-007): Anders als lint/test ist die
# Post-Merge-Verifikation NICHT universell – ist weder URL noch CMD gesetzt, wird
# übersprungen (laute Warnung, exit 0), nicht fail-closed.

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TASK_ID="${1:-post-merge}"
CMD="${FACTORY_HEALTHCHECK_CMD:-}"
URL="${FACTORY_HEALTHCHECK_URL:-}"
EXPECT="${FACTORY_HEALTHCHECK_STATUS:-200}"
RETRIES="${FACTORY_HEALTHCHECK_RETRIES:-3}"
INTERVAL="${FACTORY_HEALTHCHECK_INTERVAL:-10}"

LAST_REASON=""

# fail <grund> – einheitliche Eskalation: Interrupt protokollieren + rot beenden
fail() {
  echo "✗ Post-Merge-Verifikation fehlgeschlagen: $1"
  bash "$FACTORY_DIR/scripts/raise-interrupt.sh" "$TASK_ID" POST_MERGE_FAIL \
    "Post-Merge-Verifikation fehlgeschlagen: $1" \
    "Deployment prüfen, ggf. Rollback, dann erneut verifizieren" >/dev/null
  echo "→ POST_MERGE_FAIL-Interrupt protokolliert (tasks/interrupt-log.jsonl)"
  exit 1
}

# check_once – ein Verifikationsversuch. 0 = OK; sonst LAST_REASON gesetzt.
# CMD hat Vorrang vor URL.
check_once() {
  if [ -n "$CMD" ]; then
    # && statt if/fi: sonst ist $? nach dem if (ohne else) 0 statt des CMD-Exit-Codes
    eval "$CMD" && return 0
    LAST_REASON="Command '${CMD}' endete mit exit $?"
    return 1
  fi
  local status
  # curl gibt bei Verbindungs-/Timeout-Fehler selbst "000" aus (+ non-zero) – kein
  # "|| echo 000" (doppelter Wert); Leerwert über ${:-000} abfangen.
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" 2>/dev/null)
  status=${status:-000}
  if [ "$status" = "$EXPECT" ]; then return 0; fi
  LAST_REASON="${URL} → HTTP ${status} (erwartet ${EXPECT})"
  return 1
}

if [ -z "$CMD" ] && [ -z "$URL" ]; then
  echo "⚠  Weder FACTORY_HEALTHCHECK_CMD noch FACTORY_HEALTHCHECK_URL gesetzt –"
  echo "   Post-Merge-Verifikation übersprungen. Eine der beiden als CI/CD-Variable setzen."
  exit 0
fi

[ -n "$CMD" ] && echo "→ Post-Merge-Smoke-Command: ${CMD}" \
              || echo "→ Post-Merge-Healthcheck: $URL (erwartet HTTP $EXPECT)"

# Retry/Poll gegen Deploy-Lag (#24): 1 + RETRIES Versuche, linearer Backoff.
total=$((RETRIES + 1))
attempt=1
while :; do
  if check_once; then
    echo "✓ Verifikation OK (Versuch ${attempt}/${total})"
    exit 0
  fi
  if [ "$attempt" -ge "$total" ]; then
    fail "${LAST_REASON} (nach ${total} Versuch(en))"
  fi
  wait=$((INTERVAL * attempt))
  echo "… Versuch ${attempt}/${total} fehlgeschlagen (${LAST_REASON}) – warte ${wait}s (Deploy-Lag?)"
  sleep "$wait"
  attempt=$((attempt + 1))
done
