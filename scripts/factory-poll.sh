#!/usr/bin/env bash
# factory-poll.sh – Async-Trigger (ADR-008, Option A: Scheduled-Poll).
#
# Läuft in einem GitHub Actions Scheduled Workflow. Sucht Issues mit Label
# `factory::run` und startet für das älteste die Factory-Pipeline – fail-closed
# hinter einem dreiteiligen Budget-Guard, mit Label-State-Maschine gegen
# Doppel-Trigger.
#
# Verwendung: bash scripts/factory-poll.sh [--dry-run]
#   --dry-run  trifft alle Entscheidungen, mutiert aber nichts und startet
#              run-pipeline.sh nicht (für Tests + CI-Probelauf).
#
# Konfiguration (Repository-Variablen / Env):
#   FACTORY_MAX_RUNS_PER_DAY   harte Tageskappe (Default 5)
#   FACTORY_RUN_TIMEOUT        Sekunden, ab denen ein hängender `running`-Lauf als
#                              verwaist gilt und zurückgesetzt wird (Default 3600)
#   FACTORY_REPO               owner/repo (Default: GITHUB_REPOSITORY o. aus Remote)
#   GH_TOKEN                   Token mit issues:write (von GitHub Actions gesetzt)
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

# ── Repo-Slug ermitteln (Env bevorzugt, sonst aus der Git-Remote) ─────────────
repo_slug() {
  if [ -n "${FACTORY_REPO:-}" ]; then printf '%s' "$FACTORY_REPO"; return; fi
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then printf '%s' "$GITHUB_REPOSITORY"; return; fi
  local url path
  url=$(git -C "$FACTORY_DIR" remote get-url origin 2>/dev/null || echo "")
  # Protokoll+Host abstreifen (git@host: oder https://host/), .git entfernen → owner/repo
  path=$(printf '%s' "$url" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
  printf '%s' "$path"
}
REPO="$(repo_slug)"

# Dünne API-Wrapper – in Tests via PATH-Stub für `gh` mockbar. Rückgabe ist rohes
# JSON (Array), das der Aufrufer via jq auswertet (count_open, Auswahl, Flip-Verify).
#   list_issues <label> [such-zusatz]  – offene Issues mit Label als JSON-Array
list_issues() {
  local search="label:\"$1\" state:open ${2:-}"
  gh issue list --repo "$REPO" --search "$search" \
    --json number,createdAt,updatedAt --limit 100 2>/dev/null
}

# count_open <label> [such-zusatz] – Anzahl offener Issues mit Label, oder "ERR"
# bei nicht-numerischer Antwort (API-Fehler) → Aufrufer blockt fail-closed.
count_open() {
  local out
  out=$(list_issues "$1" "${2:-}" | jq 'length' 2>/dev/null)
  case "$out" in ''|*[!0-9]*) echo "ERR" ;; *) echo "$out" ;; esac
}

# set_labels <number> <add> <remove> – Label-Transition (Mutation)
set_labels() {
  gh issue edit "$1" --repo "$REPO" --add-label "$2" --remove-label "$3" >/dev/null 2>&1
}

# ensure_task_file <issue-nr> – stellt die lokale Task-Datei her (Issue → Task, ADR-013).
# Der Async-Trigger startet aus einem Issue; run-pipeline.sh verlangt aber eine
# tasks/task-<id>-*.md. Fehlt sie, materialisieren wir sie aus Titel/Body des Issues,
# committen und pushen sie (best-effort), damit Sync in beide Richtungen hält.
# (Der Feature-Branch/PR-Fluss des eigentlichen Codes bleibt V-1/ADR-008 – separat.)
ensure_task_file() {
  local id="$1"
  local existing
  existing=$(find "$FACTORY_DIR/tasks" -maxdepth 1 -name "task-${id}-*.md" 2>/dev/null | head -1)
  [ -n "$existing" ] && return 0
  local meta title body slug file
  meta=$(gh issue view "$id" --repo "$REPO" --json title,body 2>/dev/null)
  title=$(printf '%s' "$meta" | jq -r '.title // ""' 2>/dev/null)
  body=$(printf '%s' "$meta" | jq -r '.body // ""' 2>/dev/null)
  [ -n "$title" ] || title="Task ${id}"
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-50)
  [ -n "$slug" ] || slug="task-${id}"
  file="$FACTORY_DIR/tasks/task-${id}-${slug}.md"
  mkdir -p "$FACTORY_DIR/tasks"
  {
    printf '# Task %s: %s\n\n' "$id" "$title"
    printf '## Status\n- [ ] In Bearbeitung\n- [ ] Fertig / PR erstellt\n\n'
    printf '## Beschreibung\n%s\n\n' "$body"
    printf -- '---\nAus GitHub-Issue #%s materialisiert (factory-poll, ADR-013).\n' "$id"
  } > "$file"
  log "Task-Datei aus Issue #${id} materialisiert: $(basename "$file")"
  git -C "$FACTORY_DIR" add "$file" >/dev/null 2>&1
  git -C "$FACTORY_DIR" -c user.email=factory@local -c user.name=factory-poll \
    commit -q -m "chore: Task ${id} aus Issue materialisieren" >/dev/null 2>&1
  git -C "$FACTORY_DIR" push origin HEAD >/dev/null 2>&1 \
    || log "Hinweis: Push der Task-Datei #${id} fehlgeschlagen (kein Remote/Recht) – lokal committet."
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
  for id in $(list_issues "factory::running" "updated:<${cutoff}" | jq -r '.[].number' 2>/dev/null); do
    if [ "$DRY_RUN" = true ]; then
      log "[dry-run] würde verwaisten running-Lauf #${id} (> ${RUN_TIMEOUT}s) → factory::interrupted zurücksetzen"
    else
      set_labels "$id" "factory::interrupted" "factory::running"
      log "Verwaisten running-Lauf #${id} → factory::interrupted (Stale-Reaper, > ${RUN_TIMEOUT}s)"
    fi
  done
fi

# ── Guard 2: Concurrency = 1 (running einmal abfragen, später wiederverwenden) ──
running=$(count_open "factory::running")
[ "$running" = "ERR" ] && die_blocked "GitHub-API nicht erreichbar (running-Abfrage)."
[ "$running" -gt 0 ] && die_clean "Es läuft bereits ein Lauf (factory::running=${running}) – Abbruch (Concurrency=1)."

# ── Guard 3: Tageskappe = done + interrupted + running von heute (K-1) ──────────
today=$(date -u +%Y-%m-%d)
done_today=$(count_open "factory::done" "updated:>=${today}")
intr_today=$(count_open "factory::interrupted" "updated:>=${today}")
{ [ "$done_today" = "ERR" ] || [ "$intr_today" = "ERR" ]; } && die_blocked "GitHub-API nicht erreichbar (Tageskappe)."
rt=$(( running + done_today + intr_today ))
[ "$rt" -ge "$MAX_RUNS" ] && die_clean "Tageskappe erreicht (${rt}/${MAX_RUNS}: done+interrupted+running heute) – Abbruch."

# ── Guard 1 + Auswahl: ältestes Issue mit factory::run ──────────────────────────
issue=$(list_issues "factory::run" | jq -r 'sort_by(.createdAt) | .[0].number // empty' 2>/dev/null)
[ -z "$issue" ] && die_clean "Kein Issue mit Label factory::run – nichts zu tun."

log "Nächster Lauf: Issue #${issue} (${rt}/${MAX_RUNS} heute)"

if [ "$DRY_RUN" = true ]; then
  if [ -z "$(find "$FACTORY_DIR/tasks" -maxdepth 1 -name "task-${issue}-*.md" 2>/dev/null | head -1)" ]; then
    log "[dry-run] würde Task-Datei für Issue #${issue} aus Titel/Body materialisieren"
  fi
  log "[dry-run] würde: factory::run→factory::running, run-pipeline.sh ${issue}, dann →done/interrupted/failed"
  exit 0
fi

# State: run → running (vor dem Start, damit der nächste Poll dieses Issue nicht sieht)
set_labels "$issue" "factory::running" "factory::run"

# W-1: Flip verifizieren – nur triggern, wenn das Lock-Label wirklich sitzt.
flip=$(gh issue view "$issue" --repo "$REPO" --json labels 2>/dev/null \
  | jq -r '([.labels[].name] | index("factory::running")) // "no"' 2>/dev/null)
[ "$flip" = "no" ] && die_blocked "Label-Flip auf factory::running für #${issue} nicht bestätigt – kein Trigger."

# Issue → Task-Datei sicherstellen (ADR-013), bevor run-pipeline sie verlangt.
ensure_task_file "$issue"

# Trigger – die eigentliche Factory-Pipeline für diese Task-ID
if bash "$FACTORY_DIR/scripts/run-pipeline.sh" "$issue"; then
  set_labels "$issue" "factory::done" "factory::running"
  log "Issue #${issue} → factory::done"
else
  rc=$?
  # W-2: Interrupt (menschliche Entscheidung) vs. echter Fehler unterscheiden.
  # Ein Interrupt hinterlässt das Sentinel; ein Crash/Schritt-Fehler nicht.
  if [ -f "$FACTORY_DIR/tasks/INTERRUPT-${issue}.md" ]; then
    set_labels "$issue" "factory::interrupted" "factory::running"
    log "Issue #${issue} → factory::interrupted (menschliche Entscheidung nötig)"
  else
    set_labels "$issue" "factory::failed" "factory::running"
    log "Issue #${issue} → factory::failed (Pipeline-Fehler, exit ${rc})"
  fi
fi
