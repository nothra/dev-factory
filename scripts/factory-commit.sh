#!/usr/bin/env bash
# factory-commit.sh – Commit/Push-Seam für non-interaktive Stage-3-Sub-Agenten (ADR-019).
#
#   bash scripts/factory-commit.sh "<commit-message>"
#
# Kapselt „commit + push des aktuellen Feature-Branches" an EINER auditierbaren,
# fail-closed Stelle. Läuft über die bestehende `Bash(bash scripts/*)`-Erlaubnis –
# es braucht KEINE git-Schreib-Permission in .claude/settings.json (ADR-019 §1).
#
# Ablauf:  git add -A → git commit -m "<message>" → git push
#          (Neuanlage eines Tracking-Refs via `-u origin HEAD`, wenn kein Upstream).
#
# Fail-closed (Exit ≠ 0, klare Meldung, nichts committet/gepusht):
#   - kein git-Arbeitsbaum, detached HEAD
#   - aktueller Branch ist main/master (doppelt gesichert zu scripts/checks/pre-push.sh)
#   - keine/leere Commit-Message oder Zusatz-Argumente (kein --force/Force-Push-Einfallstor)
#   - `git push` scheitert → der non-zero Exit wird weitergereicht (kein stiller
#     „committed, aber nicht gepusht"-Zustand)
#
# Robust (Exit 0, kein Pipeline-Abbruch):
#   - „nichts zu committen" ist kein harter Fehler – ein änderungsloser Skill-Schritt
#     soll die Pipeline nicht abbrechen.
#
# Force-Push und destruktive Operationen (`reset --hard` o. Ä.) sind bewusst NICHT
# Teil dieses Skripts. Diagnostik geht auf stderr.

set -euo pipefail

err() { echo "factory-commit: $*" >&2; }

# Genau ein Argument: die Commit-Message. Mehr Argumente wären ein Einfallstor für
# Flags (etwa --force) → fail-closed abweisen. Die Message-Verantwortung (Conventional-
# Commit-Präfix) bleibt beim aufrufenden Skill (ADR-019 §1).
if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  err 'genau ein Argument erwartet: die Commit-Message. Aufruf: factory-commit.sh "<message>"'
  exit 2
fi
COMMIT_MESSAGE="$1"

# Kein Arbeitsbaum – kein Branch, den wir pushen könnten (fail-closed).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "kein git-Arbeitsbaum – nichts zu committen/pushen (fail-closed)."
  exit 3
fi

# Aktuellen Branch ermitteln; detached HEAD ist kein Feature-Branch → fail-closed.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
if [ "$BRANCH" = "HEAD" ]; then
  err "detached HEAD – kein Feature-Branch zum Pushen (fail-closed)."
  exit 3
fi

# Nie auf main/master committen/pushen (doppelt gesichert zu pre-push.sh).
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  err "aktueller Branch ist '$BRANCH' – Commit/Push auf main/master ist nicht erlaubt (fail-closed). Bitte auf einem Feature-Branch arbeiten."
  exit 4
fi

git add -A

# Nichts zu committen? Kein harter Fehler – die Pipeline soll nicht abbrechen, nur
# weil ein Schritt keine Änderungen produziert hat (ADR-019 §1).
if git diff --cached --quiet; then
  err "nichts zu committen auf '$BRANCH' – übersprungen."
  exit 0
fi

git commit -m "$COMMIT_MESSAGE"

# Pushen. Ohne Upstream (frischer Branch) das Tracking-Ref neu anlegen, sonst normaler
# Push. Kein --force. Schlägt der Push fehl, reicht `set -e` den non-zero Exit weiter →
# kein stiller „committed, aber nicht gepusht"-Zustand.
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin HEAD
fi

err "committet und gepusht auf '$BRANCH'."
exit 0
