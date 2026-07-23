#!/usr/bin/env bash
# config-validation-check.sh — fail-closed Validierung der geschichteten Factory-Config.
#
# Verwendung: config-validation-check.sh [<defaults>] [<override>]
#   Default: factory.defaults.yml [* factory.config.yml] im Repo-Root.
#   Exit 0 = gültig · ≠ 0 = ungültig (Grund auf stderr).
#
# Schließt die "stilles-Defaulting"-Lücke (ADR-009 §B, ADR-010): ein Tippfehler
# (max_turn statt max_turns), ein unbekannter Key oder eine absurde Turn-Zahl im
# Override soll laut abbrechen, nicht heimlich auf den Default zurückfallen.
#
# Regeln (alle fail-closed):
#   1. YAML-Parsefehler (defaults oder override) → fail
#   2. Unbekannte Keys: jeder Override-Blatt-Pfad muss in den Defaults existieren
#      (die Defaults SIND die erlaubte Oberfläche → keine zweite Schema-Liste, ADR-010)
#   3. schemaVersion: Integer == Defaults-Wert; weicht der Override ab → fail + Upgrade-Hinweis
#   4. Werte-Constraints (effektive Config): tier ∈ model_tiers,
#      max_turns Integer in [1, MAX_TURNS_CEILING]
#
# MAX_TURNS_CEILING ist Gate-Policy (ADR-009 §6 / ADR-010), bewusst NICHT in der
# merge-baren Config — sonst könnte ein Override sein eigenes Maximum anheben und
# den Guard aushebeln.
set -uo pipefail

MAX_TURNS_CEILING=50

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULTS="${1:-$REPO_ROOT/factory.defaults.yml}"
OVERRIDE="${2:-$REPO_ROOT/factory.config.yml}"

fail() { echo "config-validation: $*" >&2; exit 1; }

command -v yq >/dev/null 2>&1 || fail "yq nicht gefunden (Factory-Prerequisite, ADR-009 §A)."
[ -f "$DEFAULTS" ] || fail "Defaults-Datei fehlt: $DEFAULTS"

# Alle Blatt-Pfade (Skalare) einer YAML-Datei, ein Pfad pro Zeile (z.B. skills.implement.tier).
leaf_paths() { yq eval '.. | select(tag != "!!map" and tag != "!!seq") | path | join(".")' "$1" 2>/dev/null; }

# 1. YAML-Parse + schemaVersion-Typ der Defaults (Single Source of Truth).
yq eval '.' "$DEFAULTS" >/dev/null 2>&1 || fail "Defaults sind kein gültiges YAML: $DEFAULTS"
[ "$(yq eval '.schemaVersion | tag' "$DEFAULTS" 2>/dev/null)" = "!!int" ] \
  || fail "schemaVersion in den Defaults ist kein Integer: $DEFAULTS"
expected_sv="$(yq eval '.schemaVersion' "$DEFAULTS")"

if [ -n "$OVERRIDE" ] && [ -f "$OVERRIDE" ]; then
  # 1b. YAML-Parse des Overrides.
  yq eval '.' "$OVERRIDE" >/dev/null 2>&1 || fail "Override ist kein gültiges YAML: $OVERRIDE"

  # 2. Unbekannte Keys: Override-Blatt-Pfade ⊆ Defaults-Blatt-Pfade.
  defaults_paths="$(leaf_paths "$DEFAULTS")"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    grep -qxF -- "$path" <<< "$defaults_paths" \
      || fail "unbekannter Key im Override: '$path' (nicht in den Defaults — Tippfehler? Ein neuer Knopf gehört in factory.defaults.yml, nicht in den Override)."
  done < <(leaf_paths "$OVERRIDE")

  # 3. schemaVersion-Mismatch (nur prüfen, wenn der Override ihn setzt).
  if [ "$(yq eval 'has("schemaVersion")' "$OVERRIDE")" = "true" ]; then
    [ "$(yq eval '.schemaVersion | tag' "$OVERRIDE")" = "!!int" ] \
      || fail "schemaVersion im Override ist kein Integer."
    ov_sv="$(yq eval '.schemaVersion' "$OVERRIDE")"
    [ "$ov_sv" = "$expected_sv" ] \
      || fail "schemaVersion-Mismatch: Override=$ov_sv, erwartet=$expected_sv. Override gegen das aktuelle Template-Schema aktualisieren."
  fi

  effective="$(yq eval-all '. as $item ireduce ({}; . * $item)' "$DEFAULTS" "$OVERRIDE")"
else
  effective="$(cat "$DEFAULTS")"
fi

# 4. Werte-Constraints gegen die effektive (gemergte) Config.
tier_keys="$(printf '%s' "$effective" | yq eval '.model_tiers | keys | .[]' - 2>/dev/null)"

# 4a. tier ∈ model_tiers (über alle skills + default).
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  name="${entry%%=*}"; tier="${entry#*=}"
  grep -qxF -- "$tier" <<< "$tier_keys" \
    || fail "ungültiges tier '$tier' bei '$name' (erlaubt: $(echo $tier_keys | tr '\n' ' '))."
done < <(printf '%s' "$effective" | yq eval '(.skills | to_entries | .[] | .key + "=" + (.value.tier // "")), ("default=" + (.default.tier // ""))' -)

# 4b. max_turns Integer in [1, MAX_TURNS_CEILING].
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  name="${entry%%=*}"; max_turns="${entry#*=}"
  case "$max_turns" in
    ''|*[!0-9]*) fail "max_turns bei '$name' ist kein positiver Integer: '$max_turns'." ;;
  esac
  if [ "$max_turns" -lt 1 ] || [ "$max_turns" -gt "$MAX_TURNS_CEILING" ]; then
    fail "max_turns bei '$name' = $max_turns liegt außerhalb [1, $MAX_TURNS_CEILING] (Gate-Policy, ADR-009 §6)."
  fi
done < <(printf '%s' "$effective" | yq eval '(.skills | to_entries | .[] | .key + "=" + (.value.max_turns | tostring)), ("default=" + (.default.max_turns | tostring))' -)

# 4c. tier_by_size (nur wo gesetzt, ADR-038): signal ∈ {diff, proxy}, threshold
#     positiver Integer. Additiv zu 4a — das statische tier bleibt separat geprüft.
#     Format je Zeile: <skill>=<signal>|<threshold> (fehlende Felder → "" bzw. "null"
#     → fallen unten in die Integer-/Enum-Ablehnung, F3).
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  name="${entry%%=*}"; rest="${entry#*=}"
  signal="${rest%%|*}"; threshold="${rest#*|}"
  case "$signal" in
    diff|proxy) ;;
    *) fail "ungültiges tier_by_size.signal '$signal' bei '$name' (erlaubt: diff, proxy)." ;;
  esac
  case "$threshold" in
    ''|*[!0-9]*) fail "tier_by_size.threshold bei '$name' ist kein positiver Integer: '$threshold'." ;;
  esac
  [ "$threshold" -ge 1 ] \
    || fail "tier_by_size.threshold bei '$name' = $threshold muss >= 1 sein (Gate-Policy, ADR-038)."
done < <(printf '%s' "$effective" | yq eval '.skills | to_entries | .[] | select(.value.tier_by_size) | .key + "=" + (.value.tier_by_size.signal // "") + "|" + (.value.tier_by_size.threshold | tostring)' -)

exit 0
