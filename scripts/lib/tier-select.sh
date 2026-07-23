#!/usr/bin/env bash
# tier-select.sh – sourcebare Lib: größenabhängige Modell-Tier-Wahl (ADR-038).
#
# Zwei reine, testbare Funktionen (Muster: scripts/lib/report-verdict.sh) – so lässt
# sich die Größen→Tier-Logik OHNE echten claude-Lauf im Test-Harness prüfen:
#
#   select_tier <size> <threshold> <fallback_tier>
#     → druckt "heavy"/"light" bzw. den Fallback-Tier auf stdout:
#         - size ODER threshold leer/nicht-numerisch → fallback_tier
#                                       (Fail-Safe, F1/F2: kein stilles Downgrade)
#         - size >= threshold          → heavy
#         - size <  threshold          → light
#
#   measure_size <signal> <task_id> [repo_dir]
#     → druckt eine nicht-negative Zahl (Größe) auf stdout, sonst NICHTS (leer):
#         diff  → added+deleted summiert über `git diff --numstat origin/main...HEAD`
#                 (Drei-Punkt/Merge-Base misst nur die Branch-eigenen Änderungen und
#                 nutzt das aktuelle origin/main statt des evtl. zurückliegenden lokalen
#                 main; Binärdateien mit numstat "-" werden übersprungen).
#         proxy → Anzahl AK-Checkboxen ("- [ ]"/"- [x]") im Abschnitt
#                 "## Akzeptanzkriterien" der Spec docs/specs/spec-<id>-*.md.
#       Nicht bestimmbar (git-/fetch-Fehler, fehlende Spec/fehlender Abschnitt) → leerer
#       stdout → der Aufrufer fällt über select_tier auf den Fail-Safe-Tier zurück.
#     → Exit immer 0; der Aufrufer entscheidet am (nicht-)leeren stdout.
#
# Nur POSIX-Regex/awk, portabel macOS/BSD + GNU/Alpine (clean-code.md „Portabilität").

# Reine Entscheidung: size + threshold → Tier, mit Fail-Safe auf den statischen Tier.
select_tier() {
  local size="$1" threshold="$2" fallback_tier="$3"
  # Fail-Safe: Größe ODER Schwelle nicht bestimmbar (leer/nicht-numerisch) → statischer Tier.
  # Deckt F1/F2 ab, ohne dass der Aufrufer den Nicht-Bestimmbarkeits-Fall kennen muss. Die
  # Schwelle wird symmetrisch abgesichert, damit ein nicht-numerischer threshold NICHT still
  # auf light kippt (`[ -ge ]` würde sonst falsy → light) – kein stilles Downgrade.
  case "$size" in
    ''|*[!0-9]*) printf '%s' "$fallback_tier"; return 0 ;;
  esac
  case "$threshold" in
    ''|*[!0-9]*) printf '%s' "$fallback_tier"; return 0 ;;
  esac
  if [ "$size" -ge "$threshold" ]; then
    printf 'heavy'
  else
    printf 'light'
  fi
  return 0
}

# Diff-Größe: Netto geänderte Zeilen der Branch-eigenen Commits gegen origin/main.
_measure_diff() {
  local repo_dir="$1"
  # best effort: aktuelles origin/main holen. Offline/kein Remote → ignorieren, der
  # anschließende diff entscheidet über Bestimmbarkeit.
  git -C "$repo_dir" fetch --quiet origin main >/dev/null 2>&1 || true
  local numstat
  # git-Fehler (kein origin/main, kaputtes Repo) → leerer stdout → Fail-Safe heavy (F1).
  numstat="$(git -C "$repo_dir" diff --numstat origin/main...HEAD 2>/dev/null)" || return 0
  [ -z "$numstat" ] && { printf '0'; return 0; }
  # Summe added+deleted; Binärdateien (numstat-Spalten "-") überspringen.
  printf '%s\n' "$numstat" | awk '
    $1 == "-" || $2 == "-" { next }
    { sum += $1 + $2 }
    END { print sum + 0 }'
  return 0
}

# Proxy-Größe: Anzahl AK-Checkboxen im Akzeptanzkriterien-Abschnitt der Spec.
_measure_proxy() {
  local task_id="$1" repo_dir="$2"
  local spec
  spec="$(find "$repo_dir/docs/specs" -name "spec-${task_id}-*.md" 2>/dev/null | head -1)"
  # Keine Spec-Datei → leerer stdout → Fail-Safe heavy (F2).
  { [ -n "$spec" ] && [ -f "$spec" ]; } || return 0
  # Zählt "- ["-Zeilen zwischen "## Akzeptanzkriterien" und der nächsten "## "-Überschrift.
  # `found` unterscheidet "Abschnitt fehlt" (→ leer → Fail-Safe) von "Abschnitt da, 0 Boxen".
  awk '
    /^## Akzeptanzkriterien/ { inblock = 1; found = 1; next }
    /^## / { inblock = 0 }
    inblock && /^- \[/ { count++ }
    END { if (found) print count + 0 }' "$spec" 2>/dev/null
  return 0
}

# Dispatcher: Signal → Messfunktion. Unbekanntes Signal → leer (Fail-Safe).
measure_size() {
  local signal="$1" task_id="$2" repo_dir="${3:-${FACTORY_DIR:-.}}"
  case "$signal" in
    diff)  _measure_diff "$repo_dir" ;;
    proxy) _measure_proxy "$task_id" "$repo_dir" ;;
    *)     : ;;
  esac
  return 0
}
