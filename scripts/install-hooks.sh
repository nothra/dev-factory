#!/usr/bin/env bash
# install-hooks.sh – installiert bzw. aktualisiert die Git-Hooks dieses Repos (ADR-042)
#
# Verwendung: bash scripts/install-hooks.sh
#
# Einzige Quelle für den Inhalt der Hooks (pre-commit, pre-push, commit-msg). Für neue
# Projekte ruft `init-factory.sh` dieses Skript auf; für bereits initialisierte Repos ist
# es der Retrofit-Weg – `init-factory.sh` läuft dort nie ein zweites Mal (ADR-042).
#
# Idempotent: jeder Lauf schreibt denselben kanonischen Inhalt und setzt das
# Ausführbar-Bit. Beliebig oft aufrufbar, auch über einen veralteten Hook-Stand hinweg.
#
# Die Hooks landen im gemeinsamen Git-Verzeichnis (`git rev-parse --git-common-dir`) und
# gelten damit sofort für alle Worktrees dieses Repos – keine Pro-Worktree-Installation.
#
# Fail-closed: kein git-Repository oder gesetztes `core.hooksPath` → Abbruch (exit ≠ 0),
# damit ein fehlgeschlagenes Retrofit nicht als „Hooks aktiv" durchgeht.

set -euo pipefail

# Bewusst NICHT über `${FACTORY_DIR:-…}` überschreibbar wie in den Nachbarskripten: ein
# Hook-Installer soll nur in das Repo schreiben, aus dem er selbst stammt – nie per Env-Var
# in ein fremdes `.git`.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if ! GIT_COMMON_DIR="$(git -C "$REPO_DIR" rev-parse --git-common-dir 2>/dev/null)"; then
  echo -e "${RED}✗${NC} install-hooks: '$REPO_DIR' ist kein git-Repository – keine Hooks installiert (fail-closed)." >&2
  exit 1
fi

# `--git-common-dir` liefert je nach Aufrufort einen relativen Pfad (typisch ".git") –
# relativ zu dem per `-C` gesetzten Verzeichnis, hier also zum Repo-Wurzelverzeichnis.
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$REPO_DIR/$GIT_COMMON_DIR" ;;
esac

# Ist `core.hooksPath` gesetzt (z. B. durch husky), führt Git AUSSCHLIESSLICH Hooks aus
# diesem Verzeichnis aus – eine Installation nach `.git/hooks` wäre wirkungslos, das Repo
# hielte sich aber für geschützt. Fail-closed abbrechen statt fremde Hook-Verwaltung zu
# überschreiben; die Entscheidung ist bewusst dem Menschen überlassen (ADR-042).
if HOOKS_PATH_CONFIG="$(git -C "$REPO_DIR" config --get core.hooksPath 2>/dev/null)" &&
  [ -n "$HOOKS_PATH_CONFIG" ]; then
  # Scope mitnennen: `--get` liest auch global/system – ein blanker Hinweis auf
  # `git config --unset` würde sonst auf den falschen Scope zeigen.
  HOOKS_PATH_ORIGIN="$(git -C "$REPO_DIR" config --show-origin --get core.hooksPath 2>/dev/null | cut -f1 || true)"
  echo -e "${RED}✗${NC} install-hooks: 'core.hooksPath' ist auf '$HOOKS_PATH_CONFIG' gesetzt (${HOOKS_PATH_ORIGIN:-Herkunft unbekannt}) – Git führt nur Hooks aus diesem Verzeichnis aus." >&2
  echo "     Keine Hooks installiert (fail-closed). Entweder die Option im genannten Scope entfernen" >&2
  echo "     ('git config --unset core.hooksPath', ggf. mit --global/--system) oder die Factory-Checks" >&2
  echo "     in '$HOOKS_PATH_CONFIG' einbinden (pre-commit, pre-push, commit-msg)." >&2
  exit 2
fi

HOOKS_DIR="$GIT_COMMON_DIR/hooks"
mkdir -p "$HOOKS_DIR"

# install_hook <hook-name> <hook-rumpf>
install_hook() {
  local hook_name="$1" hook_body="$2"
  # Eigene Zeilen: `local a=… b="$a"` expandiert alle Wörter VOR der Zuweisung – unter
  # `set -u` wäre `$hook_name` dort noch unbound.
  local hook_file="$HOOKS_DIR/$hook_name"
  local hook_content
  hook_content="$(printf '#!/usr/bin/env bash\n%s\n' "$hook_body")"
  # Ein vorhandener Hook wird ersetzt – bei abweichendem Inhalt sichtbar melden, damit ein
  # fremder (manuell oder von einem Tool angelegter) Hook nicht still verloren geht.
  if [ -e "$hook_file" ] && [ "$(cat -- "$hook_file")" != "$hook_content" ]; then
    echo -e "  ${YELLOW}⚠${NC}  vorhandener $hook_name Hook wird durch den Factory-Stand ersetzt"
  fi
  printf '%s\n' "$hook_content" > "$hook_file"
  chmod +x "$hook_file"
  echo -e "  ${GREEN}✓${NC} $hook_name Hook installiert"
}

# Die Hooks laufen mit dem Repo-Wurzelverzeichnis als Arbeitsverzeichnis (Git-Kontrakt),
# deshalb genügen relative Pfade auf die Check-Skripte.
install_hook pre-commit 'bash scripts/checks/pre-commit.sh'
install_hook pre-push 'bash scripts/checks/pre-push.sh'
# Der Hook gilt dank gemeinsamem Git-Verzeichnis sofort für ALLE Worktrees und Branches –
# auch für solche, die `commit-msg-check.sh` noch nicht enthalten (vor dem Merge von #262
# angelegte Worktrees, ältere Feature-Branches, `git bisect`). Dort würde ein harter Aufruf
# jeden Commit mit „No such file or directory" blockieren. Deshalb eine bewusste
# Fail-open-Ausnahme ausschließlich für den Nicht-vorhanden-Fall (ADR-042 §Consequences);
# existiert das Skript, entscheidet weiterhin allein sein fail-closed Ergebnis.
# Mehrzeiliger Rumpf als Heredoc (nicht als gequotetes Argument), damit der Hook-Code
# zusammenhängend lesbar bleibt.
COMMIT_MSG_BODY="$(
  cat <<'HOOK_BODY'
CHECK="scripts/checks/commit-msg-check.sh"
[ -f "$CHECK" ] || exit 0
bash "$CHECK" "$1"
HOOK_BODY
)"
install_hook commit-msg "$COMMIT_MSG_BODY"

echo -e "${GREEN}Git-Hooks aktuell${NC} – $HOOKS_DIR"
