#!/usr/bin/env bash
# sync-issues.sh – Invariante: jede tasks/task-<id>-*.md hat ein GitHub-Issue #<id>.
#
# Konvention (ADR-013): Die GitHub-Issue-Nummer IST die Task-ID. Issues und PRs teilen
# auf GitHub denselben Nummernraum – eine bestimmte Nummer lässt sich nicht nachträglich
# erzwingen. Neue Tasks entstehen deshalb Issue-first (start-work.sh). Dieses Skript ist
# das Sicherheitsnetz/Audit: es prüft die Invariante und kann fehlende Issues anlegen.
#
# Verwendung:
#   bash scripts/sync-issues.sh            # --check (Default): read-only, exit 1 bei Drift
#   bash scripts/sync-issues.sh --create   # fehlende Issues anlegen
#   bash scripts/sync-issues.sh --create --dry-run   # zeigt an, mutiert nicht
#
# Konfiguration:
#   FACTORY_REPO   owner/repo (Default: GITHUB_REPOSITORY o. aus der Git-Remote)
#   GH_TOKEN       Token mit issues:read (bzw. :write für --create)
#
# Exit-Codes:
#   0  synchron (bzw. --create erfolgreich)
#   1  Drift (--check: mind. ein Task ohne Issue) oder nicht auflösbarer Nummern-Mismatch
#   2  Aufruf-/Umgebungsfehler (gh fehlt, Repo unbekannt)

set -uo pipefail

FACTORY_DIR="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TASKS_DIR="$FACTORY_DIR/tasks"

MODE="check"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --create)  MODE="create" ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unbekanntes Argument: $arg" >&2; exit 2 ;;
  esac
done

log() { echo "[sync-issues] $*"; }

command -v gh >/dev/null 2>&1 || { log "gh nicht gefunden – Sync nicht möglich."; exit 2; }

# Zentraler Issue-Seam (ADR-018) – kein eigener gh-Direktaufruf zur Issue-Anlage mehr.
# Relativ zum Skript-Ort sourcen (FACTORY_DIR kann per Env auf einen anderen Baum zeigen).
# shellcheck source=scripts/lib/create-issue.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/create-issue.sh"

# ── Repo-Slug (Env bevorzugt, sonst aus der Git-Remote) ───────────────────────
repo_slug() {
  if [ -n "${FACTORY_REPO:-}" ]; then printf '%s' "$FACTORY_REPO"; return; fi
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then printf '%s' "$GITHUB_REPOSITORY"; return; fi
  local url path
  url=$(git -C "$FACTORY_DIR" remote get-url origin 2>/dev/null || echo "")
  path=$(printf '%s' "$url" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
  printf '%s' "$path"
}
REPO="$(repo_slug)"
[ -n "$REPO" ] || { log "Repo unbekannt (FACTORY_REPO/GITHUB_REPOSITORY/Remote leer)."; exit 2; }

# issue_exists <nummer> – 0 wenn ein Issue mit der Nummer existiert (egal welcher State)
issue_exists() {
  gh issue view "$1" --repo "$REPO" --json number >/dev/null 2>&1
}

# ── Tasks einsammeln (task-<id>-*.md → id) ────────────────────────────────────
missing=""     # Task-IDs ohne Issue
checked=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")
  id=$(printf '%s' "$base" | sed -E 's/^task-([0-9]+)-.*/\1/')
  # Nur numerische IDs (die Konvention); alles andere überspringen wir laut.
  case "$id" in ''|*[!0-9]*) log "übersprungen (keine numerische Task-ID): $base"; continue ;; esac
  checked=$((checked + 1))
  if issue_exists "$id"; then
    [ "$MODE" = check ] && log "OK: Task #${id} ↔ Issue #${id}"
  else
    # Newline-getrennt akkumulieren (nicht space-getrennt): Pfade können Leerzeichen
    # enthalten (Bug #8) – die spätere Iteration liest zeilenweise.
    if [ -z "$missing" ]; then missing="${id}:${f}"; else missing="${missing}"$'\n'"${id}:${f}"; fi
  fi
done < <(find "$TASKS_DIR" -maxdepth 1 -name 'task-*.md' 2>/dev/null | sort)

# ── Auswertung ────────────────────────────────────────────────────────────────
if [ -z "$missing" ]; then
  log "Synchron: alle ${checked} Task(s) haben ein Issue-Pendant."
  exit 0
fi

if [ "$MODE" = check ]; then
  log "DRIFT: folgende Tasks haben KEIN GitHub-Issue:"
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    id="${entry%%:*}"; log "  - Task #${id} (Issue #${id} fehlt)"
  done <<< "$missing"
  log "Beheben: bash scripts/sync-issues.sh --create   (oder Issue manuell anlegen)"
  exit 1
fi

# ── --create: fehlende Issues anlegen ─────────────────────────────────────────
rc=0
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  id="${entry%%:*}"; f="${entry#*:}"
  # Titel aus der ersten H1-Zeile der Task-Datei; Fallback auf Dateinamen.
  title=$(grep -m1 '^# ' "$f" 2>/dev/null | sed -E 's/^# +//')
  [ -n "$title" ] || title="Task ${id}"
  body="Automatisch aus \`$(basename "$f")\` angelegt (sync-issues.sh). Task-ID = Issue-Nummer (ADR-013)."
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] würde Issue für Task #${id} anlegen: \"${title}\""
    continue
  fi
  # Über den Seam anlegen (ADR-018): mindestens das Art-Label 'enhancement' (Default,
  # Override via FACTORY_ISSUE_LABEL) – behebt die frühere label-lose Anlage.
  art_label="${FACTORY_ISSUE_LABEL:-enhancement}"
  newnum=$(create_issue "$title" "$body" "$art_label") || newnum=""
  if [ -z "$newnum" ]; then
    log "FEHLER: Issue für Task #${id} konnte nicht angelegt werden."; rc=1; continue
  fi
  if [ "$newnum" = "$id" ]; then
    log "Angelegt: Issue #${newnum} für Task #${id}"
  else
    # Nummern-Mismatch ist auf GitHub nicht auflösbar (Nummer nicht erzwingbar).
    log "MISMATCH: Task #${id} → GitHub vergab #${newnum}. Bitte Task-Datei/Branch auf #${newnum} umbenennen"
    log "          oder Issue #${newnum} schließen und die Task-ID an eine freie Nummer angleichen."
    rc=1
  fi
done <<< "$missing"
exit $rc
