#!/usr/bin/env bash
# test-groups.sh – Testgruppen der Suite als parallele Teilprozesse (Factory-ADR-066)
#
# Wird gesourct, nie direkt ausgeführt – von der Suite (Start und Sammeln) und von jeder Testgruppe (Ergebnis schreiben).
# Setzt die Zähler PASS/FAIL aus lib/assert-helpers.sh voraus.
#
# Ergebnisvertrag (D3/D4): Eine Gruppe schreibt ihre Ausgabe in ein Log und als einzige Zeile `RESULT <pass> <fail>` in
# eine eigene Ergebnisdatei. Fehlt die Datei, ist sie nicht wohlgeformt oder endet die Gruppe mit Exit ≠ 0 ohne rote
# Assertion, zählt sie als genau eine rote Assertion mit Namen und Grund – ein fehlendes Teilergebnis ist nie grün.
# FACTORY_SELF_TEST_SERIAL=1 (D6): derselbe Ablauf, aber jede Gruppe wird sofort nach dem Start abgewartet.

# Seite der Gruppe: Pfad der Ergebnisdatei aus der Umgebung übernehmen und die Variable entfernen, damit kein getestetes
# Skript (Kindprozess der Gruppe) die Datei kennt und das Ergebnis überschreiben kann.
TEST_GROUP_RESULT_FILE="${FACTORY_TEST_GROUP_RESULT:-}"
unset FACTORY_TEST_GROUP_RESULT

TEST_GROUPS_DIR=""
TEST_GROUP_NAMES=()
TEST_GROUP_PIDS=()
TEST_GROUP_RCS=()

# test_group_run <skript> <präfix> – läuft im Hintergrund: Gruppe starten, ihren Exit-Status nach <präfix>.rc schreiben.
# Der Status kommt aus einer Datei statt aus `wait <pid>` der Suite: die Suite startet bis zum Sammeln Zehntausende Prozesse,
# und wird die PID einer längst beendeten Gruppe wiederverwendet, verwirft bash deren Status (`wait` meldet dann 127).
# TERM an den Wrapper wird an die Gruppe weitergereicht; erst ihr echtes Ende schreibt den Status.
test_group_run() {
  local child forwarded=0 rc
  FACTORY_TEST_GROUP_RESULT="$2.result" bash "$1" > "$2.log" 2>&1 &
  child=$!
  trap 'forwarded=1; kill -TERM "$child" 2>/dev/null' TERM
  wait "$child"; rc=$?
  [ "$forwarded" -eq 0 ] || { wait "$child"; rc=$?; }
  printf '%s\n' "$rc" > "$2.rc.tmp" && mv "$2.rc.tmp" "$2.rc"
}

# test_group_start <name> <skript> – Gruppe als eigenen bash-Prozess im Hintergrund starten (seriell: sofort abwarten)
test_group_start() {
  local name="$1" script="$2" i="${#TEST_GROUP_NAMES[@]}"
  if [ -z "$TEST_GROUPS_DIR" ]; then
    TEST_GROUPS_DIR="$(mktemp -d)" || { echo "test_group_start: kein Temp-Verzeichnis (fail-closed)" >&2; exit 2; }
  fi
  test_group_run "$script" "$TEST_GROUPS_DIR/$i" &
  TEST_GROUP_PIDS[$i]=$!
  TEST_GROUP_NAMES[$i]="$name"
  TEST_GROUP_RCS[$i]=""
  if [ "${FACTORY_SELF_TEST_SERIAL:-}" = 1 ]; then
    test_group_wait "$i"
  fi
}

# test_group_wait <index> – auf das Ende der Gruppe warten und ihren Exit-Status aus der Datei übernehmen (fehlt sie: leer)
test_group_wait() {
  wait "${TEST_GROUP_PIDS[$1]}" 2>/dev/null
  TEST_GROUP_RCS[$1]="$(cat "$TEST_GROUPS_DIR/$1.rc" 2>/dev/null)"
  [ -n "${TEST_GROUP_RCS[$1]}" ] || TEST_GROUP_RCS[$1]="?"
}

# test_group_failed <name> <grund> – die Gruppe zählt als eine rote Assertion
test_group_failed() {
  FAIL=$((FAIL + 1))
  echo -e "  ${RED}✗${NC} Testgruppe $1: $2 – zählt als rot (Factory-ADR-066 D4)"
}

# test_group_merge <name> <exit> <ergebnisdatei> – Ergebnis einer beendeten Gruppe auf PASS/FAIL addieren (fail-closed)
test_group_merge() {
  local name="$1" rc="$2" file="$3" content re='^RESULT ([0-9]+) ([0-9]+)$' pass fail
  if ! [[ "$rc" =~ ^[0-9]+$ ]]; then
    test_group_failed "$name" "abgebrochen, kein Exit-Status"; return
  fi
  if [ ! -f "$file" ]; then
    test_group_failed "$name" "abgebrochen, kein Ergebnis (Exit $rc)"; return
  fi
  content="$(cat "$file")"
  if ! [[ "$content" =~ $re ]]; then
    test_group_failed "$name" "Ergebnis nicht wohlgeformt (Exit $rc)"; return
  fi
  pass=$((10#${BASH_REMATCH[1]})); fail=$((10#${BASH_REMATCH[2]}))
  if [ "$rc" -ne 0 ] && [ "$fail" -eq 0 ]; then
    test_group_failed "$name" "Exit $rc ohne rote Assertion"; return
  fi
  PASS=$((PASS + pass)); FAIL=$((FAIL + fail))
}

# test_groups_collect – in Startreihenfolge auf jede Gruppe warten, ihr Log zusammenhängend ausgeben, Ergebnis addieren
test_groups_collect() {
  local i=0 rc
  while [ "$i" -lt "${#TEST_GROUP_NAMES[@]}" ]; do
    [ -n "${TEST_GROUP_RCS[$i]}" ] || test_group_wait "$i"
    rc="${TEST_GROUP_RCS[$i]}"
    cat "$TEST_GROUPS_DIR/$i.log"
    test_group_merge "${TEST_GROUP_NAMES[$i]}" "$rc" "$TEST_GROUPS_DIR/$i.result"
    i=$((i + 1))
  done
  test_groups_cleanup
}

# test_groups_cleanup – laufende Gruppen beenden und abwarten, Logs und Ergebnisdateien entfernen (D5; idempotent)
test_groups_cleanup() {
  local i=0
  while [ "$i" -lt "${#TEST_GROUP_PIDS[@]}" ]; do
    if [ -z "${TEST_GROUP_RCS[$i]}" ]; then
      kill -TERM "${TEST_GROUP_PIDS[$i]}" 2>/dev/null
      wait "${TEST_GROUP_PIDS[$i]}" 2>/dev/null
      TEST_GROUP_RCS[$i]=143
    fi
    i=$((i + 1))
  done
  [ -z "$TEST_GROUPS_DIR" ] || rm -rf "$TEST_GROUPS_DIR"
  TEST_GROUPS_DIR=""
}

# test_groups_trap – Aufräumen bei Ende und Abbruch der Suite (Ctrl-C/TERM endet rot, F5)
test_groups_trap() {
  trap 'test_groups_cleanup' EXIT
  trap 'test_groups_cleanup; trap - EXIT; exit 130' INT
  trap 'test_groups_cleanup; trap - EXIT; exit 143' TERM
}

# test_group_finish – Abschluss einer Gruppe: als Teilprozess das Ergebnis schreiben, allein gestartet die Fußzeile;
# der Rückgabewert (0 nur ohne Rot) ist der Exit-Code der Gruppe. Die Dauer hilft beim Zuordnen langsamer Gruppen.
test_group_finish() {
  echo "  • Testgruppe $(basename "$0" .sh): ${SECONDS} s"
  if [ -n "$TEST_GROUP_RESULT_FILE" ]; then
    printf 'RESULT %s %s\n' "$PASS" "$FAIL" > "$TEST_GROUP_RESULT_FILE"
    [ "$FAIL" -eq 0 ]
  else
    print_summary
  fi
}

# test_group_trap <verzeichnis> – Teilprozess räumt sein Temp-Verzeichnis beim Ende auf, auch bei TERM (D5)
test_group_trap() {
  TEST_GROUP_TMP="$1"
  trap 'chmod -R u+w "$TEST_GROUP_TMP" 2>/dev/null; rm -rf "$TEST_GROUP_TMP"' EXIT
  trap 'exit 143' TERM
}
