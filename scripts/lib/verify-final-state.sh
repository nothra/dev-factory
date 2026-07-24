#!/usr/bin/env bash
# verify-final-state.sh – sourcebare Lib: deterministische Endzustands-Verifikation
# der Pipeline (ADR-040), agenten-signal-unabhängiger Backstop vor der Erfolgs-Ausgabe.
#
# Zwei Funktionen, getrennt nach reiner Entscheidung vs. I/O (Muster:
# scripts/lib/tier-select.sh select_tier ↔ measure_size) – so ist die Entscheidungslogik
# ohne echtes Repo/GitHub im Test-Harness prüfbar, und git/gh sind über den I/O-Wrapper
# austauschbar (PATH-Shim / repo_dir-Parameter):
#
#   evaluate_final_state <tree_status> <unpushed> <pr_shepherd> <pr_state> <is_draft> <auto_merge>
#     Reine Entscheidung über bereits erhobene Fakten. Druckt bei Verletzung den konkreten
#     realen Zustand auf stdout und liefert Exit 1; bei erfülltem Endzustand Exit 0 (leerer
#     stdout). Fail-closed: nicht verwertbare/leere Fakten gelten als NICHT verifiziert.
#       tree_status : "clean" | alles andere (= dirty)
#       unpushed    : Anzahl ungepushter Commits (0 = ok); nicht-numerisch (kein Upstream,
#                     git-Fehler) → nicht verifizierbar
#       pr_shepherd : "true" → zusätzliche PR-Invarianten; sonst nur git-Invarianten
#       pr_state    : PR-Status (z. B. OPEN/MERGED); leer → gh nicht verwertbar (fail-closed)
#       is_draft    : "true" wenn PR noch Draft
#       auto_merge  : "set" wenn Auto-Merge scharfgeschaltet (autoMergeRequest != null)
#
#   verify_final_state <branch> <pr_shepherd> [repo_dir]
#     I/O-Wrapper: erhebt die Fakten über git/gh (git-Invarianten immer, gh nur bei
#     pr_shepherd=true) und delegiert an evaluate_final_state. Exit/stdout wie dort.
#     Fail-closed: kein origin/<branch>-Tracking oder fehlgeschlagener git/gh-Aufruf →
#     nicht verifiziert (nie stilles „Erfolg" bei unklarer Lage).
#
# Nur POSIX-Regex/portables Shell, macOS/BSD + GNU/Alpine (clean-code.md „Portabilität").

# Reine Entscheidung über die erhobenen Fakten. Reihenfolge = Meldungs-Priorität.
evaluate_final_state() {
  local tree_status="$1" unpushed="$2" pr_shepherd="$3" pr_state="$4" is_draft="$5" auto_merge="$6"

  # Beide Modi (1/2): Working Tree sauber.
  if [ "$tree_status" != "clean" ]; then
    printf 'Working Tree nicht sauber (uncommittete Änderungen)'
    return 1
  fi

  # Beide Modi (2/2): keine ungepushten Commits. Nicht-numerisch (kein Upstream / git-Fehler)
  # → fail-closed „nicht verifizierbar", nicht „nichts zu pushen" (F1/F2).
  case "$unpushed" in
    ''|*[!0-9]*)
      printf 'Push-Zustand nicht verifizierbar (kein origin-Tracking oder git-Fehler)'
      return 1
      ;;
  esac
  if [ "$unpushed" -ne 0 ]; then
    printf 'Ungepushte Commits auf dem Feature-Branch (%s)' "$unpushed"
    return 1
  fi

  # Kein PR_SHEPHERD: git-Invarianten genügen (AK2).
  [ "$pr_shepherd" = "true" ] || return 0

  # PR_SHEPHERD: PR-Zustand muss verwertbar sein (leer = gh-Fehler → fail-closed, F1).
  if [ -z "$pr_state" ]; then
    printf 'PR-Zustand nicht verifizierbar (gh-Aufruf ohne verwertbaren Wert)'
    return 1
  fi
  # Gemergt zählt als Erfolg (AK6) – dann sind Draft/Auto-Merge irrelevant.
  if [ "$pr_state" = "MERGED" ]; then
    return 0
  fi
  # Noch Draft → blockiert (AK3).
  if [ "$is_draft" = "true" ]; then
    printf 'PR noch Draft'
    return 1
  fi
  # Weder gemergt noch Auto-Merge scharf → blockiert (AK4). Auto-Merge scharf = Erfolg (AK5).
  if [ "$auto_merge" != "set" ]; then
    printf 'PR weder gemergt noch Auto-Merge scharfgeschaltet'
    return 1
  fi
  return 0
}

# I/O-Wrapper: Fakten über git/gh erheben und an evaluate_final_state delegieren.
verify_final_state() {
  local branch="$1" pr_shepherd="$2" repo_dir="${3:-${FACTORY_DIR:-.}}"
  local tree_status unpushed pr_state="" is_draft="" auto_merge=""

  # Working Tree: unstaged UND staged sauber (gleiche Semantik wie preflight_checks).
  if git -C "$repo_dir" diff --quiet 2>/dev/null && \
     git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
    tree_status="clean"
  else
    tree_status="dirty"
  fi

  # Ungepushte Commits: origin/<branch> muss existieren, sonst fail-closed (F2).
  # Leerer Branch (git-Fehler beim Aufrufer) oder "HEAD" (detached HEAD) → kein verwertbares
  # Upstream → fail-closed, statt gegen origin/HEAD (den Default-Branch) aufzulösen.
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    unpushed="NO_UPSTREAM"
  elif git -C "$repo_dir" rev-parse --verify --quiet "origin/${branch}^{commit}" >/dev/null 2>&1; then
    unpushed="$(git -C "$repo_dir" rev-list --count "origin/${branch}..HEAD" 2>/dev/null)"
    [ -n "$unpushed" ] || unpushed="ERROR"   # git-Fehler → nicht-numerisch → fail-closed (F1)
  else
    unpushed="NO_UPSTREAM"
  fi

  # PR-Zustand nur bei PR_SHEPHERD=true (gh-Abhängigkeit sonst vermeiden, ADR-040).
  if [ "$pr_shepherd" = "true" ]; then
    local gh_line auto_flag
    # Ein atomarer gh-Aufruf, TSV über gh-eigenes -q (kein externes jq nötig).
    # Fehlgeschlagener Aufruf → leere Zeile → pr_state bleibt leer → fail-closed (F1).
    # HINWEIS (Test-Coverage): Der gh-Stub im Test-Harness bildet diese TSV fest nach; die
    # -q-Filterausdruck-Semantik (Feldreihenfolge, --json-Feldnamen, @tsv) läuft mangels echtem
    # gh NICHT im Harness und ist nur durch Codelesen gegen die gh-CLI-Doku abgesichert.
    gh_line="$( ( cd "$repo_dir" 2>/dev/null && \
      gh pr view --json isDraft,state,autoMergeRequest \
        -q '[.isDraft, .state, (.autoMergeRequest != null)] | @tsv' ) 2>/dev/null )" || gh_line=""
    IFS=$'\t' read -r is_draft pr_state auto_flag <<<"$gh_line"
    if [ "$auto_flag" = "true" ]; then auto_merge="set"; else auto_merge="none"; fi
  fi

  evaluate_final_state "$tree_status" "$unpushed" "$pr_shepherd" "$pr_state" "$is_draft" "$auto_merge"
}
