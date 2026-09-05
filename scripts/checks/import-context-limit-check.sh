#!/usr/bin/env bash
# import-context-limit-check.sh – Deckel für den @import-Dauerkontext (ADR-047 §4)
#
# Summiert die Zeilen von CLAUDE.md und – rekursiv – aller per `@pfad` eingebundenen Dateien
# und vergleicht die Summe gegen MAX_IMPORT_LINES. Dieser Kontext wird bei JEDER Session und
# JEDEM Pipeline-Schritt vollständig geladen; ohne Deckel wächst er unbemerkt zurück – genau
# das ist nach ADR-037 passiert (der Lessons-Index von ~80 auf 341 Zeilen, Befund aus #319).
# Eine Prosa-Konvention hat dort nicht gehalten, deshalb hier ein Gate.
#
# ── Was als Referenz gilt ────────────────────────────────────────────────────────────────────
#
# Claude Code lädt `@pfad` nicht nur als eigene Zeile, sondern auch mitten in Prosa und mit
# Markdown-Dekoration. Empirisch belegt (Review zu #319, `claude --print` mit Marker-Datei und
# Negativkontrolle ohne `@`): geladen werden u. a. `@docs/x.md`, `**@docs/x.md**`,
# `_@docs/x.md_` und `>@docs/x.md`. Ein Deckel, der nur alleinstehende Zeilen zählt, wäre per
# Prosa-Zeile lautlos umgehbar – also fail-open gegen den eigenen Zweck. Erkannt werden daher:
#
#   1. **Referenz-Zeile:** Die Zeile besteht (bis auf umgebende Leerzeichen) aus `@<pfad>`,
#      enthält kein weiteres `@` – und der Pfad ist **einwortig**. Diese Form wird immer
#      gezählt, auch wenn die Datei fehlt: nur so ist der Check fail-closed, sonst umgeht eine
#      Umbenennung den Deckel lautlos.
#      Enthält der Rest der Zeile Leerzeichen, ist die Form ambig – ein umgebrochener
#      Prosa-Absatz kann zufällig mit `@` beginnen. Dann gilt Regel 2, damit eine Prosa-Zeile
#      den Push nicht mit „Datei nicht lesbar: <ganzer Satz>" blockiert. Ein echter Pfad **mit**
#      Leerzeichen zählt weiterhin, sobald er auflöst.
#
#   2. **Inline-Referenz:** Jedes `@`-Token einer Zeile, das auf eine **lesbare Datei** auflöst.
#      Vorangestellte Dekoration (`**`, `_`, `>`, Klammern, Backticks) und angehängte
#      Satzzeichen werden abgeschnitten. Die Auflösungs-Bedingung ist notwendig, weil sich ein
#      Import sonst nicht von Prosa unterscheiden lässt – real steht in `CLAUDE.md` der Satzteil
#      „nicht @importiert (ADR-037)", der kein Import ist.
#
# ── Bekannte Grenzen (bewusst) ───────────────────────────────────────────────────────────────
#
# * Regel 2 ist **nicht** fail-closed: eine Inline-Referenz auf eine gelöschte Datei fällt still
#   weg. Das ist die Kehrseite davon, Prosa nicht als Import zu zählen. Fail-closed bleibt allein
#   Regel 1 – die Form, in der die echten Imports stehen.
# * Ungewöhnliche Einbettungen (typografische Anführungszeichen, Dekoration hinter dem Pfad ohne
#   passendes Zeichen in der Trimm-Liste) können ungezählt bleiben. Der Deckel deckt die Formen
#   ab, die im Repo vorkommen und für die das Ladeverhalten belegt ist – nicht beweisbar jede.
# * Pfade werden gegen die Projektwurzel aufgelöst, nicht gegen die importierende Datei. Heute
#   ohne Fall, weil keine importierte Datei selbst importiert.
# * **Confinement:** Ein Kandidat, der aus der Projektwurzel herausführt (absolut oder mit
#   `..`-Segment), wird abgelehnt – als Referenz-Zeile fail-closed mit Meldung, als Inline-Token
#   still übergangen. Ein `@import` dieses Repos ist immer wurzelrelativ; ohne die Regel war der
#   Deckel ein Zeilenzahl-Orakel über beliebige lesbare Dateien der Maschine
#   (Security-Review zu #319).
# * **Ausgabe:** Abgeleitete Pfade gehen nie durch `echo -e`, sondern über `printf %s`. Sonst
#   werden `\033`-Sequenzen aus dem Dateiinhalt zu echten Steuerzeichen und ein präparierter
#   Pfad kann die Gate-Ausgabe der übrigen Checks überschreiben (Security-Review zu #319).
# * **Zeilenzahl:** Lässt sie sich nicht ermitteln, ist der Check rot. `$((total + ""))` ist in
#   bash kein Fehler, sondern `+ 0` – ohne Integer-Guard hätte eine fehlgeschlagene Zählung das
#   Gate still grün gemacht.
# * Gezählt werden Zeilen per `awk END{print NR}` – auch eine Datei ohne Schluss-Newline zählt
#   vollständig (`wc -l` unterzählte sie um 1; ein Gate, das die Schluss-Newline erzwingt, gibt
#   es nicht: `.prettierignore` deckt `docs/` und `CLAUDE.md`).
#
# Projektwurzel: FACTORY_DIR (Tests/Override), sonst zwei Ebenen über scripts/checks/.

set -uo pipefail

ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Obergrenze in Zeilen für CLAUDE.md + rekursiv alle @-eingebundenen Dateien.
# Herleitung (ADR-047 §4 – keine Magic Number): Ist-Stand direkt nach der Umstellung aus #319
# = 863 Zeilen; + 25 % Puffer = 1.079; aufgerundet auf das nächste Vielfache von 50 = 1.100.
# Der Puffer trägt legitime Regel-Ergänzungen, ohne den nächsten Wildwuchs zu decken. Wer die
# Grenze anhebt, trifft eine bewusste Entscheidung – und pflegt diese Herleitung mit (ein Test
# rechnet die Konstante gegen die hier genannte Basis nach).
MAX_IMPORT_LINES=1100

ENTRY_FILE="CLAUDE.md"
SELF_PATH="scripts/checks/import-context-limit-check.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
NL=$'\n'

cd "$ROOT" 2>/dev/null || {
  echo -e "${RED}✗${NC} import-context-limit-check: Projektwurzel nicht erreichbar: $ROOT"
  exit 1
}

if [ ! -f "$ENTRY_FILE" ] || [ ! -r "$ENTRY_FILE" ]; then
  echo -e "${RED}✗${NC} import-context-limit-check: Einstiegsdatei fehlt oder ist nicht lesbar: $ENTRY_FILE"
  echo "     Erwartet in der Projektwurzel '$ROOT' (fail-closed)."
  exit 1
fi

# candidates_of <datei> – gibt je Zeile einen Kandidaten aus, als `<art>\t<pfad>`:
#   S = Referenz-Zeile (Regel 1) → wird unbedingt gezählt, fehlende Datei ist rot
#   T = Inline-Kandidat (Regel 2) → wird nur gezählt, wenn er auflöst
# Ein awk-Lauf je Datei statt einer Prozess-Pipeline je Zeile/Token: bei ~860 Zeilen war die
# Zeilen-Variante messbar teurer (2,9 s gegen 0,03 s) und verlangte eine unquotierte
# Command-Substitution, die zusätzlich der Pathname-Expansion unterlag.
candidates_of() {
  awk '
    {
      line = $0
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)

      # Regel 1: ganze Zeile ist @<pfad>, kein weiteres @
      if (line ~ /^@./ && index(substr(line, 2), "@") == 0) {
        rest = substr(line, 2)
        if (rest !~ /[[:space:]]/) { print "S\t" rest; next }
        print "T\t" rest   # mit Leerzeichen: nur zählen, wenn es wirklich ein Pfad ist
      }

      # Regel 2: jedes @-Token der Zeile, mit und ohne abgeschnittene Satzzeichen/Dekoration
      n = split($0, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        t = tok[i]
        sub(/^[^@]*@/, "@", t)          # führende Dekoration: **, _, >, (, `, [ …
        if (t !~ /^@./) continue
        cand = substr(t, 2)
        print "T\t" cand
        trimmed = cand
        gsub(/[]*_`".,;:!?)}]+$/, "", trimmed)
        if (trimmed != "" && trimmed != cand) print "T\t" trimmed
      }
    }
  ' "./$1"
}

# repo_relative <pfad> – 0, wenn der Pfad innerhalb der Projektwurzel bleibt.
# Ein `@import` dieses Repos ist immer wurzelrelativ. Ein absoluter Pfad oder ein `..`-Segment
# ist deshalb entweder ein Fehler – oder der Weg, den Deckel als Zeilenzahl-Orakel über beliebige
# lesbare Dateien der Maschine zu missbrauchen (`@/etc/passwd` zählte vorher mit und erschien in
# der Beiträger-Liste; Security-Review zu #319).
repo_relative() {
  case "$1" in
    /*) return 1 ;;
    ..|../*|*/../*|*/..) return 1 ;;
    *) return 0 ;;
  esac
}

# enqueue_refs_of <datei> – hängt die Referenzen der Datei an die Worklist `pending` an.
# Wertet den S/T-Kontrakt von candidates_of aus: S kommt unbedingt in die Liste (eine fehlende
# Datei soll später rot werden), T nur, wenn der Pfad wirklich auf eine lesbare Datei zeigt.
# Mutiert bewusst die globale Worklist – der Heredoc hält die Leseschleife in der aktuellen
# Shell, eine Pipe täte das nicht (Subshell) und der Anhang ginge verloren.
enqueue_refs_of() {
  local kind cand
  while IFS="$(printf '\t')" read -r kind cand; do
    [ -n "${cand:-}" ] || continue
    case "$kind" in
      S)
        if repo_relative "$cand"; then
          pending="${pending:+$pending$NL}$cand"
        else
          printf '%b %s\n' "${RED}✗${NC} import-context-limit-check:" \
            "Referenz außerhalb der Projektwurzel: $cand (fail-closed)"
          failed=1
        fi
        ;;
      T) repo_relative "$cand" && [ -f "$cand" ] && [ -r "$cand" ] &&
           pending="${pending:+$pending$NL}$cand" ;;
    esac
  done <<CANDIDATES
$(candidates_of "$1")
CANDIDATES
}

# Worklist als newline-getrennter String statt Array: bash 3.2 (macOS) bricht unter `set -u`
# beim Expandieren leerer Arrays ab – der Check läuft lokal UND in CI.
pending="$ENTRY_FILE"
seen=""
total=0
failed=0
breakdown=""

while [ -n "$pending" ]; do
  rel="${pending%%$NL*}"
  case "$pending" in
    *"$NL"*) pending="${pending#*"$NL"}" ;;
    *) pending="" ;;
  esac

  # Zyklen und Doppelzählung abfangen (a.md → b.md → a.md).
  case "$NL$seen$NL" in
    *"$NL$rel$NL"*) continue ;;
  esac
  seen="$seen$NL$rel"

  if [ ! -f "$rel" ] || [ ! -r "$rel" ]; then
    printf '%b %s\n' "${RED}✗${NC} import-context-limit-check:" \
      "referenzierte Datei nicht lesbar: $rel (fail-closed)"
    failed=1
    continue
  fi

  lines="$(awk 'END { print NR }' "./$rel" 2>/dev/null)" || lines=""
  case "$lines" in
    ''|*[!0-9]*)
      printf '%b %s\n' "${RED}✗${NC} import-context-limit-check:" \
        "Zeilenzahl nicht ermittelbar: $rel (fail-closed)"
      failed=1
      continue
      ;;
  esac
  total=$((total + lines))
  breakdown="$breakdown$(printf '%6d  %s' "$lines" "$rel")$NL"

  enqueue_refs_of "$rel"
done

if [ "$failed" -eq 1 ]; then
  echo "     Beheben: die oben genannte Ursache beseitigen – Referenz korrigieren oder entfernen,"
  echo "     bzw. das Zählwerkzeug (awk) prüfen. Bis dahin bleibt der Deckel fail-closed."
  exit 1
fi

if [ "$total" -gt "$MAX_IMPORT_LINES" ]; then
  echo -e "${RED}✗${NC} @import-Dauerkontext zu groß: $total Zeilen (Grenze: $MAX_IMPORT_LINES, ADR-047 §4)"
  printf '%s' "$breakdown" | sort -rn | sed 's/^/     /'
  echo "     Beheben: verdichten oder auslagern (Volltext → docs/factory/lessons/, Trigger in CLAUDE.md)."
  echo "     Grenze anheben ist eine bewusste Entscheidung: MAX_IMPORT_LINES in $SELF_PATH samt Herleitung anpassen."
  exit 1
fi

echo -e "${GREEN}✓${NC} @import-Dauerkontext: $total von $MAX_IMPORT_LINES Zeilen"
exit 0
