#!/usr/bin/env bash
# factory-poll.sh – Async-Trigger (ADR-008, Option A: Scheduled-Poll).
#
# Läuft in einer GitLab Scheduled Pipeline. Sucht Issues mit Label `factory::run`
# und startet für das älteste die Factory-Pipeline – fail-closed hinter einem
# dreiteiligen Budget-Guard, mit Label-State-Maschine gegen Doppel-Trigger.
#
# Verwendung: bash scripts/factory-poll.sh [--dry-run]
#   --dry-run  trifft alle Entscheidungen, mutiert aber nichts und startet
#              run-pipeline.sh nicht (für Tests + CI-Probelauf).
#
# Konfiguration (CI/CD-Variablen):
#   FACTORY_MAX_RUNS_PER_DAY   harte Tageskappe (Default 5)
#   FACTORY_RUN_TIMEOUT        Sekunden, ab denen ein hängender `running`-Lauf als
#                              verwaist gilt und zurückgesetzt wird (Default 3600)
#   FACTORY_PROJECT            Projekt-ID/Pfad (Default: CI_PROJECT_ID o. aus Remote)
#
# Budget-Guard (ADR-008, nicht verhandelbar – greift VOR dem ersten Claude-Lauf):
#   1. Eintrittstür   : nur Issues mit Label `factory::run`
#   2. Concurrency = 1: läuft bereits ein `factory::running`-Issue → Abbruch
#   3. Tageskappe     : done + interrupted + running von HEUTE >= Kappe → Abbruch
# Ein `interrupted` Lauf hat bereits Sessions verbraucht und zählt deshalb mit.
# Kann der Guard seinen Zustand nicht ermitteln (API-Fehler), wird LAUT geblockt
# (exit 3, roter Job) – nicht still durchgewinkt.
#
# Label-State: factory::run → factory::running → factory::done | ::interrupted | ::failed
#
# Hinweis: bewusst `set -uo pipefail` OHNE `-e` – API-Aufrufe dürfen fehlschlagen
# und werden explizit ausgewertet (count_open → "ERR"), statt das Skript hart zu beenden.

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MAX_RUNS="${FACTORY_MAX_RUNS_PER_DAY:-5}"
RUN_TIMEOUT="${FACTORY_RUN_TIMEOUT:-3600}"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

log() { echo "[factory-poll] $*"; }
die_clean()   { log "$*"; exit 0; }                        # nichts zu tun – kein Fehler
die_blocked() { log "BLOCKED (fail-closed): $*"; exit 3; }  # Zustand unklar → laut, roter Job

# ── Projekt-Pfad ermitteln (CI-Variable bevorzugt, sonst aus der Git-Remote) ──
project_id() {
  if [ -n "${FACTORY_PROJECT:-}" ]; then printf '%s' "$FACTORY_PROJECT"; return; fi
  if [ -n "${CI_PROJECT_ID:-}" ]; then printf '%s' "$CI_PROJECT_ID"; return; fi
  local url path
  url=$(git -C "$FACTORY_DIR" remote get-url origin 2>/dev/null || echo "")
  path=$(printf '%s' "$url" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
  printf '%s' "$path" | sed 's#/#%2F#g'
}
PROJECT="$(project_id)"

# Dünne API-Wrapper – in Tests via PATH-Stub für `glab` mockbar.
api() { glab api "projects/${PROJECT}/$1" 2>/dev/null; }

# count_open <label> [extra-query] – Anzahl offener Issues mit Label, oder "ERR"
# bei nicht-numerischer Antwort (API-Fehler) → Aufrufer blockt fail-closed.
count_open() {
  local out
  out=$(api "issues?labels=$1&state=opened&per_page=100${2:-}" | jq 'length' 2>/dev/null)
  case "$out" in ''|*[!0-9]*) echo "ERR" ;; *) echo "$out" ;; esac
}

[ "$DRY_RUN" = true ] && log "DRY-RUN – keine Mutationen, kein Pipeline-Start"

# ── W-1: verwaiste `running`-Läufe zurücksetzen. CI-Kill/Timeout o. eine
# fehlgeschlagene Mutation lassen ein Issue sonst dauerhaft auf running → der
# Concurrency-Guard wedged jeden weiteren Poll. Cutoff portabel (GNU/busybox
# `-d @`, BSD `-r`).
now_epoch=$(date -u +%s)
cutoff=$(date -u -d "@$((now_epoch - RUN_TIMEOUT))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -r "$((now_epoch - RUN_TIMEOUT))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
if [ -n "$cutoff" ]; then
  for id in $(api "issues?labels=factory::running&state=opened&updated_before=${cutoff}&per_page=100" | jq -r '.[].iid' 2>/dev/null); do
    if [ "$DRY_RUN" = true ]; then
      log "[dry-run] würde verwaisten running-Lauf #${id} (> ${RUN_TIMEOUT}s) → factory::interrupted zurücksetzen"
    else
      api "issues/${id}?add_labels=factory::interrupted&remove_labels=factory::running" >/dev/null
      log "Verwaisten running-Lauf #${id} → factory::interrupted (Stale-Reaper, > ${RUN_TIMEOUT}s)"
    fi
  done
fi

# ── Guard 2: Concurrency = 1 (running einmal abfragen, später wiederverwenden) ──
running=$(count_open "factory::running")
[ "$running" = "ERR" ] && die_blocked "GitLab-API nicht erreichbar (running-Abfrage)."
[ "$running" -gt 0 ] && die_clean "Es läuft bereits ein Lauf (factory::running=${running}) – Abbruch (Concurrency=1)."

# ── Guard 3: Tageskappe = done + interrupted + running von heute (K-1) ──────────
today=$(date -u +%Y-%m-%d)
done_today=$(count_open "factory::done" "&updated_after=${today}T00:00:00Z")
intr_today=$(count_open "factory::interrupted" "&updated_after=${today}T00:00:00Z")
{ [ "$done_today" = "ERR" ] || [ "$intr_today" = "ERR" ]; } && die_blocked "GitLab-API nicht erreichbar (Tageskappe)."
rt=$(( running + done_today + intr_today ))
[ "$rt" -ge "$MAX_RUNS" ] && die_clean "Tageskappe erreicht (${rt}/${MAX_RUNS}: done+interrupted+running heute) – Abbruch."

# ── Guard 1 + Auswahl: ältestes Issue mit factory::run ──────────────────────────
issue=$(api "issues?labels=factory::run&state=opened&order_by=created_at&sort=asc&per_page=1" \
  | jq -r '.[0].iid // empty' 2>/dev/null)
[ -z "$issue" ] && die_clean "Kein Issue mit Label factory::run – nichts zu tun."

log "Nächster Lauf: Issue #${issue} (${rt}/${MAX_RUNS} heute)"

if [ "$DRY_RUN" = true ]; then
  log "[dry-run] würde: factory::run→factory::running, run-pipeline.sh ${issue}, dann →done/interrupted/failed"
  exit 0
fi

# State: run → running (vor dem Start, damit der nächste Poll dieses Issue nicht sieht)
api "issues/${issue}?add_labels=factory::running&remove_labels=factory::run" >/dev/null

# W-1: Flip verifizieren – nur triggern, wenn das Lock-Label wirklich sitzt.
flip=$(api "issues/${issue}" | jq -r '([.labels[]] | index("factory::running")) // "no"' 2>/dev/null)
[ "$flip" = "no" ] && die_blocked "Label-Flip auf factory::running für #${issue} nicht bestätigt – kein Trigger."

# Trigger – die eigentliche Factory-Pipeline für diese Task-ID
if bash "$FACTORY_DIR/scripts/run-pipeline.sh" "$issue"; then
  api "issues/${issue}?add_labels=factory::done&remove_labels=factory::running" >/dev/null
  log "Issue #${issue} → factory::done"
else
  rc=$?
  # W-2: Interrupt (menschliche Entscheidung) vs. echter Fehler unterscheiden.
  # Ein Interrupt hinterlässt das Sentinel; ein Crash/Schritt-Fehler nicht.
  if [ -f "$FACTORY_DIR/tasks/INTERRUPT-${issue}.md" ]; then
    api "issues/${issue}?add_labels=factory::interrupted&remove_labels=factory::running" >/dev/null
    log "Issue #${issue} → factory::interrupted (menschliche Entscheidung nötig)"
  else
    api "issues/${issue}?add_labels=factory::failed&remove_labels=factory::running" >/dev/null
    log "Issue #${issue} → factory::failed (Pipeline-Fehler, exit ${rc})"
  fi
fi
