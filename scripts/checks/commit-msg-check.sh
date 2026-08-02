#!/usr/bin/env bash
# commit-msg-check.sh – Flag-Guard für Commit-Messages (#262)
#
# Wird ausgeführt: git commit (über .git/hooks/commit-msg), aufgerufen mit dem Pfad zur
# Commit-Message-Datei als $1 – genau so, wie Git den Hook aufruft.
#
# Blockiert genau einen Fehlgriff: eine Message, die in Wahrheit ein CLI-Flag ist.
# `git commit -m --help` zeigt keine Hilfe an, sondern nimmt `--help` wörtlich als
# Commit-Message (so entstand Commit 2a27728 auf chore/252). Alles andere passiert
# unverändert – insbesondere Messages, die nur mit `-` beginnen (`-x`) oder ein Flag im
# Fließtext erwähnen. Eine allgemeine Formatprüfung (Conventional Commits) und die
# Leer-Prüfung sind bewusst NICHT Teil dieses Hooks (Scope: spec-262).
#
# Exit-Kontrakt: 0 = Message passiert, 1 = fachliche Ablehnung (Flag erkannt),
# 2 = Infrastruktur-Fehler (kein/leeres Argument, Message-Datei nicht lesbar). Beides
# blockiert den Commit; die Trennung macht im Log unterscheidbar, WARUM.
#
# Fail-closed: fehlendes Argument oder nicht lesbare Message-Datei → Abbruch (exit ≠ 0),
# kein stilles Durchwinken.

set -euo pipefail

RED='\033[0;31m'
NC='\033[0m'

MESSAGE_FILE="${1:-}"

if [ -z "$MESSAGE_FILE" ]; then
  echo -e "${RED}✗${NC} commit-msg-check: kein Pfad zur Commit-Message-Datei übergeben (fail-closed)." >&2
  exit 2
fi

if [ ! -r "$MESSAGE_FILE" ]; then
  echo -e "${RED}✗${NC} commit-msg-check: Commit-Message-Datei '$MESSAGE_FILE' nicht lesbar (fail-closed)." >&2
  exit 2
fi

# Git entfernt die Kommentarzeilen des Editor-Templates erst NACH diesem Hook (`--cleanup`).
# Auf dem Editor-Pfad (`git commit` ohne `-m`, `-e`, `--amend`, Merge, `-t <template>`) enthält
# die Datei also z. B. `--help\n\n# Please enter the commit message …` – ohne Filterung wäre
# der Guard dort blind (empirisch verifiziert mit git 2.50: der Hook sieht die Kommentare, der
# Commit entstand mit Message `--help`). Deshalb erst Kommentarzeilen verwerfen, dann trimmen.
# Der Kommentar-Präfix ist konfigurierbar (`core.commentString` ab git 2.45, sonst
# `core.commentChar`); Default `#`.
COMMENT_PREFIX='#'
for config_key in core.commentString core.commentChar; do
  if configured_prefix="$(git config --get "$config_key" 2>/dev/null)" && [ -n "$configured_prefix" ]; then
    # `auto` lässt Git den Präfix pro Message aus einer Kandidatenliste wählen – welcher es
    # war, steht nirgends. Dann beim Default bleiben: der Guard greift auf dem Editor-Pfad
    # nur, wenn Git tatsächlich `#` gewählt hat (dokumentierte Restlücke, ADR-042).
    [ "$configured_prefix" = "auto" ] || COMMENT_PREFIX="$configured_prefix"
    break
  fi
done

MESSAGE=""
while IFS= read -r message_line || [ -n "$message_line" ]; do
  # Git zählt eine Zeile nur als Kommentar, wenn der Präfix am Zeilenanfang steht (kein
  # führender Whitespace). Der quotierte Variablen-Teil verhindert Glob-Interpretation.
  case "$message_line" in
    # Scissors-Zeile (bei `--cleanup=scissors` bzw. `-v`/`--verbose`): alles ab hier gehört
    # nicht zur Message, auch wenn es KEINEN Kommentar-Präfix trägt – der verbose-Diff hängt
    # unpräfigiert direkt darunter (empirisch mit git 2.50 belegt: ohne diesen Abbruch bliebe
    # der Diff in MESSAGE stehen und der Trim-Vergleich griffe nicht mehr).
    "$COMMENT_PREFIX"*'>8'*) break ;;
    "$COMMENT_PREFIX"*) continue ;;
  esac
  MESSAGE="$MESSAGE$message_line
"
done < "$MESSAGE_FILE"

# Umgebenden Whitespace (inkl. Zeilenumbrüche) entfernen: `git commit -m` hängt ein \n an,
# und ein versehentliches Leerzeichen soll den Guard nicht aushebeln. Verglichen wird
# danach exakt – kein Regex, damit es keine BSD/GNU-Portabilitätsfalle gibt.
TRIMMED="${MESSAGE#"${MESSAGE%%[![:space:]]*}"}"
TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"

if [ "$TRIMMED" = "--help" ] || [ "$TRIMMED" = "-h" ]; then
  echo -e "${RED}✗${NC} commit-msg-check: Die Commit-Message sieht aus wie ein CLI-Flag ('$TRIMMED') – Commit blockiert." >&2
  echo "     Vermutlich war eine Hilfe-Ausgabe gemeint; git nimmt das Flag wörtlich als Message." >&2
  echo '     Bitte eine echte Commit-Message angeben, z. B.: git commit -m "feat: ..."' >&2
  exit 1
fi

exit 0
