#!/usr/bin/env bash
# pr-closes-keyword-check.sh – CI-Gate: PR-Body muss ein Issue per Closing-Keyword schließen.
#
# Hintergrund (git-workflow.md, wiederholt bei nothra/tch-gastro-services#71/#74/#76/#78 beobachtet):
# Ein PR schließt sein Issue nur dann automatisch, wenn der PR-*Body* ein
# GitHub-Closing-Keyword mit Issue-Referenz enthält (z. B. "Closes #78"). Eine
# bloße Erwähnung im Titel ("… (nothra/tch-gastro-services#78)") oder ein deutsches "Behebt nothra/tch-gastro-services#78" lässt das
# Issue nach dem Merge offen zurück – start-work.sh legt dann später erneut einen
# redundanten Worktree für das vermeintlich offene Issue an.
#
# Dieses Gate liest den PR-Body aus $PR_BODY (in CI: github.event.pull_request.body)
# und schlägt fail-closed fehl, wenn kein Closing-Keyword mit #<nr>-Referenz vorkommt.
#
# GitHub-Closing-Keywords (case-insensitiv): close/closes/closed, fix/fixes/fixed,
# resolve/resolves/resolved. Referenzform: das im Projekt konventionelle "#<issue-nr>"
# (start-work.sh setzt genau das) – die URL-/owner/repo#-Form ist bewusst nicht
# abgedeckt, um die Konvention einheitlich zu halten.
#
# Ausnahme (Factory-ADR-063 E14): der Update-PR des Workflows factory-update.yml hat kein Issue. Er
# kommt ohne Keyword durch, wenn der Head-Branch chore/factory-update ist UND aus demselben Repo
# stammt ($PR_HEAD_REF, $PR_HEAD_REPO, $PR_BASE_REPO aus CI) – ein Fork-PR mit gleichem Namen bleibt
# geprüft. Hygiene-Gate, keine Sicherheitsgrenze: wer pushen darf, kann die Ausnahme nutzen.
#
# Nur POSIX-ERE (clean-code.md: portabel, kein PCRE) – läuft lokal (macOS/BSD)
# und in CI (GNU) identisch.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PR_BODY="${PR_BODY:-}"

is_update_pr() {
  [ "${PR_HEAD_REF:-}" = "chore/factory-update" ] &&
  [ -n "${PR_BASE_REPO:-}" ] && [ "${PR_HEAD_REPO:-}" = "$PR_BASE_REPO" ]
}

if is_update_pr; then
  echo -e "${GREEN}✓${NC} Update-PR der Factory (chore/factory-update, selbes Repo) – kein Issue nötig."
  exit 0
fi

# Wortgrenze + Keyword + optionaler Doppelpunkt + Whitespace + #<nr>.
# grep -i macht das Muster case-insensitiv; -E aktiviert ERE.
CLOSES_PATTERN='(^|[^[:alnum:]])(close[sd]?|fix(es|ed)?|resolve[sd]?):?[[:space:]]+#[0-9]+'

# Here-String statt Pipe: vermeidet den SIGPIPE-Falschrot, den `printf | grep -q`
# unter `set -o pipefail` auslösen kann (bash-gotchas.md).
if grep -iqE "$CLOSES_PATTERN" <<< "$PR_BODY"; then
  echo -e "${GREEN}✓${NC} PR-Body enthält ein Closing-Keyword mit Issue-Referenz."
  exit 0
fi

echo -e "${RED}✗ PR-Body enthält kein Closing-Keyword mit Issue-Referenz.${NC}"
echo "  Ein gemergter PR muss sein Issue automatisch schließen (git-workflow.md)."
echo "  Ergänze im PR-Body eine Zeile, z. B.:  Closes #<issue-nr>"
echo "  Erlaubt: Closes / Fixes / Resolves (auch -s / -d / -ed) + #<nr>."
echo "  Eine bloße Erwähnung wie \"(#123)\" oder \"Behebt #123\" reicht NICHT."
exit 1
