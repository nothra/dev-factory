#!/usr/bin/env bash
# factory-lock-66-tests.sh – Testgruppe Factory-Issue #66: Netz des Fetch-Containers abschotten (Factory-ADR-063, Nachtrag
# 2026-11-21 E35–E40) – Regelsatz samt Reihenfolge, eigenes Netz, IPv6 aus, Lebenszyklus (Reste, Abräumen), Fail-closed in beiden
# Modi, Netz-Probe des Smoke-Jobs, Doku-Guards; je tragender Eigenschaft ein Mutationsbeleg (E40 b).
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-66-tests.sh
# Weder Docker noch root nötig: Fake-docker/-sudo/-iptables im PATH protokollieren argv und bilden Ketten und Netz als Dateien
# nach; für die Probe ein Fake-curl „im Container" (lib/factory-lock-fixtures.sh, fetch_fakes_41).

set -uo pipefail

TESTS_DIR_66="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib_66 in assert-helpers test-groups factory-lock-fixtures; do
  # shellcheck source=/dev/null
  source "$TESTS_DIR_66/lib/$lib_66.sh" || { echo "$(basename "$0"): Helfer-Lib nicht ladbar: lib/$lib_66.sh (fail-closed)" >&2; exit 2; }
done

# Ohne yq entfällt die Gruppe still: die Skip-Zeile für #23/#24/#37 schreibt factory-lock-23-tests.sh
[ "$HAS_YQ" -eq 1 ] || { test_group_finish; exit $?; }
factory_lock_setup
fetch_fakes_41
unset GITHUB_ACTIONS GITHUB_OUTPUT
echo ""
echo "Factory-Issue #66: Netz des Fetch-Containers abschotten:"

# Erwarteter Regelsatz (E36) – im Test festgeschrieben, nicht aus dem Skript gelesen. Je Kette von oben (Kettenanfang) nach unten.
EXP_INPUT_66='-i factory-fetch0 -j REJECT'
EXP_DOCKER_USER_66='-i factory-fetch0 -d 168.63.129.16/32 -p udp --dport 53 -j RETURN
-i factory-fetch0 -d 168.63.129.16/32 -p tcp --dport 53 -j RETURN
-i factory-fetch0 -d 168.63.129.16/32 -j REJECT
-i factory-fetch0 -d 169.254.0.0/16 -j REJECT'
FOREIGN_RULE_66='-i docker0 -j ACCEPT'
HINT_66='passwortloses sudo und iptables'
GATEWAY_66="$FAKE_GATEWAY_66"
PORT_66=18066
BASE_66="$(printf 'a%.0s' $(seq 40))"

# ── Läufe gegen die Fakes ────────────────────────────────────────────────────────────────────────────────────────────
N_66=0
# st_66 – frischer Fake-Zustand; setzt D66 (Zustand), R66 (Projektwurzel), O66 (Ausgabeverzeichnis, noch nicht angelegt)
st_66() {
  N_66=$((N_66 + 1)); D66="$T23/s66-$N_66"; R66="$D66/root"; O66="$D66/out"
  mkdir -p "$R66" "$D66/chains"; : > "$D66/calls.log"; : > "$D66/chains/INPUT"; : > "$D66/chains/DOCKER-USER"
  printf 'https://github.com\n' > "$D66/reachable"
  printf '00000000000000000000000000000001 01 80 10 80       lo\n' > "$D66/if_inet6"
}
# run_66 <iso|smoke> [<skript>] [<out-mode>] – Modus fetch-isolated bzw. fetch-smoke im Zustand D66; setzt out_66/rc_66.
# Den Host-Lauscher (python3, curl) bekommt nur fetch-smoke in den PATH.
run_66() {
  local path="$FAKE_41:$PATH" args
  if [ "$1" = iso ]; then
    printf '%s\n' "${3:-file}" > "$D66/out-mode"; args=(fetch-isolated v1.1.0 "$BASE_66" "$O66")
  else
    printf '%s\n' "${3:-smoke}" > "$D66/out-mode"; args=(fetch-smoke "$O66"); path="$FAKE_HOST_66:$path"
  fi
  # 9>&-: ein fd 9 der Test-Umgebung darf die Lock-Prüfer (lock-at-*) nicht grün färben
  out_66="$(FACTORY_DIR="$R66" PATH="$path" FAKE_DOCKER_STATE="$D66" FAKE_CTR_66="$FAKE_CTR_66" bash "${2:-$UPD_24}" "${args[@]}" 2>&1 9>&-)"; rc_66=$?
}
# fresh_66 <iso|smoke> [<skript>] [<out-mode>] – st_66 + run_66
fresh_66() { st_66; run_66 "$@"; }

# ── Prüfer ───────────────────────────────────────────────────────────────────────────────────────────────────────────
# rules_at_run_66 – beim Container-Start bestanden genau die Regeln aus E36 in dieser Reihenfolge am Kettenanfang (DNS-Ausnahme
# vor der Sperre von 168.63.129.16), und das Netz existierte; eine fremde Regel bleibt dahinter stehen
rules_at_run_66() {
  local foreign="${1:-}" want_du="$EXP_DOCKER_USER_66"
  [ -z "$foreign" ] || want_du="$want_du"$'\n'"$foreign"
  [ -e "$D66/net-at-run" ] && [ "$(cat "$D66/chains-at-run/INPUT")" = "$EXP_INPUT_66" ] \
    && [ "$(cat "$D66/chains-at-run/DOCKER-USER")" = "$want_du" ]
}
# net_create_ok_66 – Netz mit festem Bridge-Namen, ohne IPv6/--internal (E35)
net_create_ok_66() {
  printf '%s\0' network create --driver bridge -o com.docker.network.bridge.name=factory-fetch0 factory-fetch | cmp -s - "$D66/net-create.argv"
}
# run_net_opts_66 – docker run hängt am eigenen Netz und schaltet IPv6 ab (E35, E37); unabhängig vom exakten Vergleich in #41
run_net_opts_66() {
  tr '\0' '\n' < "$D66/run.argv" | awk '
    p == "--network" && $0 == "factory-fetch" { net = 1 }
    p == "--sysctl" && $0 == "net.ipv6.conf.all.disable_ipv6=1" { v6 = 1 }
    { p = $0 } END { exit !(net && v6) }'
}
# setup_before_container_66 – Netz, Regeln und danach ihre Prüfung per -C stehen im Protokoll vor build, build vor run (E39);
# nach build wird keine Regel mehr gesetzt
setup_before_container_66() {
  awk '
    /^network-create$/ && !build { net = NR } /^iptables -I / { if (build) late = 1; ins = NR } /^iptables -C / && ins && !build { chk = NR }
    /^build$/ && !build { build = NR } /^run$/ && !run { run = NR }
    END { exit !(net && ins && chk > ins && build && run && !late && build < run) }' "$D66/calls.log"
}
# cleaned_66 [<fremde-regel>] – nach dem Lauf: keine Regel aus E36 mehr, Netz entfernt; eine fremde Regel bleibt
cleaned_66() {
  [ ! -e "$D66/net" ] && [ ! -s "$D66/chains/INPUT" ] && [ "$(cat "$D66/chains/DOCKER-USER")" = "${1:-}" ]
}
# ok_run_66 <iso|smoke> [<skript>] – grüner Lauf mit Sperre: Regeln beim Start, Netz, Optionen, Reihenfolge, Abräumen
ok_run_66() {
  fresh_66 "$@"
  [ "$rc_66" -eq 0 ] && rules_at_run_66 && net_create_ok_66 && run_net_opts_66 && setup_before_container_66 && cleaned_66
}
# refused_66 <schalter> – rot mit Hinweis auf sudo/iptables, weder Build noch Container, kein Artefakt, nichts bleibt stehen
# (E39, AK3). Mit kaputtem -C findet auch das Abräumen keine Regel – dort entfällt nur diese letzte Prüfung.
refused_66() {
  [ "$rc_66" -eq 1 ] && grep -qF -- "$HINT_66" <<< "$out_66" && ! grep -qxE 'build|run' "$D66/calls.log" \
    && [ ! -e "$O66/update.bundle" ] && [ ! -e "$O66/smoke.txt" ] && { [ "$1" = fail-ipt-C ] || cleaned_66; }
}
# fail_66 <iso|smoke> <schalter> [<skript>] – Lauf mit gesetztem Fake-Schalter; Exit 0 = refused_66
fail_66() { st_66; : > "$D66/$2"; run_66 "$1" "${3:-}"; refused_66 "$2"; }

# ── AK1/AK2/E35–E37: Sperre wirkt in beiden Modi ─────────────────────────────────────────────────────────────────────
for mode_66 in iso smoke; do
  ok_run_66 "$mode_66"; assert_exit 0 "$?" "#66 AK1.1–AK1.4/E35–E37 ($mode_66): beim Container-Start stehen INPUT-Sperre des Hosts, DNS-Ausnahme vor Sperre von 168.63.129.16 und Sperre von 169.254.0.0/16 an factory-fetch0; Netz factory-fetch, IPv6 aus, danach abgeräumt"
done
# AK1.5: Regeln liegen auf dem Host und werden mit sudo -n gesetzt – nie im Container (der hat kein CAP_NET_ADMIN, #41 prüft cap-drop ALL)
# via_sudo_66 – jeder iptables-Aufruf lief über „sudo -n“ (der Fake-sudo protokolliert ihn vor dem iptables-Fake)
via_sudo_66() {
  local n_ipt n_sudo
  n_ipt="$(grep -cE '^iptables -' "$D66/calls.log")"; n_sudo="$(grep -cx 'sudo -n iptables' "$D66/calls.log")"
  [ "$n_ipt" -gt 0 ] && [ "$n_ipt" = "$n_sudo" ] && ! grep -qx sudo-ohne-n "$D66/calls.log"
}
fresh_66 iso
assert_true "$(grep -qx 'iptables -I INPUT' "$D66/calls.log" && via_sudo_66 && ! tr '\0' '\n' < "$D66/run.argv" | grep -qE '^(--cap-add|--privileged)'; echo $?)" \
  "#66 AK1.5: Regeln per sudo -n iptables auf dem Host, der Container bekommt keine Netz-Rechte"
mutant_37 66-ohne-sudo 's#^host_iptables\(\) \{ sudo -n iptables "\$@"; \}#host_iptables() { iptables "$@"; }#'
fresh_66 iso "$MUT37"; assert_true "$(! via_sudo_66; echo $?)" "#66 AK4.2 (Mutation): iptables ohne sudo → derselbe Prüfer ist rot"

# ── E40 b: Mutationsbelege für Regelsatz, Reihenfolge, Netz, Optionen ────────────────────────────────────────────────
mut_ok_66() { # <name> <sed-ausdruck> [<modus>] – Mutante → ok_run_66 rot
  mutant_37 "66-$1" "$2"; ok_run_66 "${3:-iso}" "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): $1 → derselbe Prüfer ist rot"
}
mut_ok_66 input-regel-fehlt '/^  "INPUT -i /d'
mut_ok_66 imds-ziel-fehlt '/169\.254\.0\.0\/16 -j REJECT"$/d'
mut_ok_66 wireserver-ziel-fehlt '/168\.63\.129\.16\/32 -j REJECT"$/d'
mut_ok_66 dns-ausnahme-nach-sperre 's#for \(\(i = \$\{\#FETCH_NET_RULES\[@\]\} - 1; i >= 0; i--\)\)#for ((i = 0; i < ${\#FETCH_NET_RULES[@]}; i++))#'
mut_ok_66 dns-ausnahme-fuer-alle-ports 's#-p udp --dport 53 -j RETURN#-j RETURN#'
mut_ok_66 fremde-bridge 's#^FETCH_BRIDGE="factory-fetch0"#FETCH_BRIDGE="docker0"#'
mut_ok_66 ohne-network 's#--network "\$FETCH_NETWORK" ##'
mut_ok_66 ohne-sysctl 's#--sysctl net\.ipv6\.conf\.all\.disable_ipv6=1 ##'
mut_ok_66 netz-mit-ipv6 's#network create --driver bridge#network create --ipv6 --driver bridge#'
mut_ok_66 isolated-ohne-sperre '/^mode_fetch_isolated\(\)/,/^\}/s#^  setup_fetch_network$#  :#'
mut_ok_66 smoke-ohne-sperre '/^mode_fetch_smoke\(\)/,/^\}/s#^  setup_fetch_network$#  :#' smoke
mut_ok_66 sperre-nach-container-start '/^mode_fetch_isolated\(\)/,/^\}/s#^  setup_fetch_network$#  :#; s#^  require_single_bundle "\$OUT_DIR"$#  setup_fetch_network; require_single_bundle "$OUT_DIR"#'
mut_ok_66 ohne-abraeumen 's#^  \[ -z "\$FETCH_NET_ACTIVE" \] \|\| teardown_fetch_network$#  true#'

# ── E39/AK3: Fail-closed, beide Modi ─────────────────────────────────────────────────────────────────────────────────
for mode_66 in iso smoke; do
  fail_66 "$mode_66" fail-net-create; assert_exit 0 "$?" "#66 AK3/F1 ($mode_66): docker network create scheitert → rot mit Hinweis, kein Build, kein Container"
  fail_66 "$mode_66" fail-ipt-I; assert_exit 0 "$?" "#66 AK3/F1 ($mode_66): iptables -I scheitert → rot, kein Container"
  fail_66 "$mode_66" fail-ipt-C; assert_exit 0 "$?" "#66 AK3/F1 ($mode_66): Prüfung per iptables -C scheitert → rot, kein Container"
  fail_66 "$mode_66" noop-ipt-I; assert_exit 0 "$?" "#66 AK3/E36 ($mode_66): iptables -I meldet Erfolg, Regel fehlt aber → die Prüfung per -C fängt es, rot"
  fail_66 "$mode_66" no-docker-user; assert_exit 0 "$?" "#66 AK3/E39 ($mode_66): Kette DOCKER-USER fehlt → rot, kein Container"
  fail_66 "$mode_66" no-sudo; assert_exit 0 "$?" "#66 AK3/F1 ($mode_66): kein passwortloses sudo → rot, kein Container"
  fail_66 "$mode_66" no-iptables; assert_exit 0 "$?" "#66 AK3/F1 ($mode_66): iptables fehlt → rot, kein Container"
done
mut_fail_66() { # <name> <schalter> <sed-ausdruck> – Mutante → derselbe Fehlerfall ist nicht mehr fail-closed
  mutant_37 "66-$1" "$3"; fail_66 iso "$2" "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): $1 → derselbe Fehlerfall ist nicht mehr rot"
}
mut_fail_66 netz-fehler-ignoriert fail-net-create 's#\|\| die "Docker-Netz#|| true "Docker-Netz#'
mut_fail_66 pruefung-ignoriert noop-ipt-I 's#\|\| die "Regel nach dem Setzen#|| true "Regel nach dem Setzen#'
mut_fail_66 setzen-und-pruefen-ignoriert fail-ipt-I 's#\|\| die "Regel (nicht setzbar|nach dem Setzen)#|| true "Regel \1#'
# sudo ohne -n wartete auf einem Runner ohne passwortloses sudo auf ein Passwort, statt zu scheitern – der Fake verweigert es
mutant_37 66-sudo-ohne-n 's#sudo -n iptables#sudo iptables#'
ok_run_66 iso "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): sudo ohne -n → derselbe Prüfer ist rot"
assert_true "$(grep -qx sudo-ohne-n "$D66/calls.log"; echo $?)" "#66 E36 (Mutation, Voraussetzung): der Fake hat den Aufruf ohne -n erkannt"

# ── E38/F4: Reste früherer Läufe, fremde Regeln, Abräumen ────────────────────────────────────────────────────────────
# Reste: Regeln doppelt, Netz vorhanden, dazu eine fremde Regel in DOCKER-USER (anderer Container auf einem langlebigen Runner)
stale_66() {
  st_66; : > "$D66/net"
  { printf '%s\n' "$EXP_INPUT_66" "$EXP_INPUT_66"; } > "$D66/chains/INPUT"
  { printf '%s\n' "$EXP_DOCKER_USER_66" "$FOREIGN_RULE_66" "$EXP_DOCKER_USER_66"; } > "$D66/chains/DOCKER-USER"
}
stale_ok_66() { # <modus> [<skript>]
  stale_66; run_66 "$@"
  [ "$rc_66" -eq 0 ] && rules_at_run_66 "$FOREIGN_RULE_66" && cleaned_66 "$FOREIGN_RULE_66"
}
for mode_66 in iso smoke; do
  stale_ok_66 "$mode_66"; assert_exit 0 "$?" "#66 F4/E38 ($mode_66): Reste eines früheren Laufs → wiederholbar grün, jede Regel genau einmal; fremde Regel bleibt unberührt"
done
mutant_37 66-ohne-reste-abraeumen 's#^  remove_fetch_rules; remove_fetch_network$#  :#'
stale_ok_66 iso "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): ohne Abräumen der Reste vor dem Anlegen ist derselbe Prüfer rot"
# Abräumen auch nach einem Fehler im Container
st_66; : > "$D66/fail-run"; run_66 iso
assert_true "$([ "$rc_66" -eq 1 ] && rules_at_run_66 && cleaned_66; echo $?)" "#66 E38: Container scheitert → rot, Regeln und Netz trotzdem abgeräumt"
# Fehler beim Abräumen: nur Warnung, Ergebnis bleibt grün
for sw_66 in fail-ipt-D fail-net-rm; do
  st_66; : > "$D66/$sw_66"; run_66 iso
  assert_true "$([ "$rc_66" -eq 0 ] && grep -qF 'nicht abgeräumt' <<< "$out_66"; echo $?)" "#66 E38: $sw_66 beim Abräumen → nur Warnung, Exit 0"
done
# Ohne Docker wird nichts eingerichtet (Reihenfolge E39: require_docker zuerst)
st_66; : > "$D66/fail-info"; run_66 iso
assert_true "$([ "$rc_66" -eq 1 ] && [ "$(cat "$D66/calls.log")" = info ]; echo $?)" "#66 E39: ohne Docker weder Netz noch Regeln"

# ── W1 (Security-Review): verwaister Container am Netz – erst er, dann die Regeln ─────────────────────────────────────
# Entfernte der Lauf die Regeln, obwohl ein Container am Netz hing, lief der ungesperrt weiter (und `network rm` scheiterte).
# rm_before_D_66 <ab-zeile> – ab dieser Zeile im Protokoll steht `docker rm` vor dem ersten `iptables -D`
rm_before_D_66() {
  awk -v from="$1" '$0 == from { on = 1 } on && /^rm$/ && !r { r = NR } on && /^iptables -D / && !d { d = NR } END { exit !(r && d && r < d) }' "$D66/calls.log"
}
# orphan_setup_66 [<skript>] – Rest eines abgestürzten Laufs: Container am Netz, Regeln noch da; der neue Lauf räumt erst ihn ab
orphan_setup_66() {
  stale_66; : > "$D66/orphan"; run_66 iso "$@"
  [ "$rc_66" -eq 0 ] && rm_before_D_66 info && [ ! -e "$D66/orphan" ] && rules_at_run_66 "$FOREIGN_RULE_66" && cleaned_66 "$FOREIGN_RULE_66"
}
orphan_setup_66; assert_exit 0 "$?" "#66 W1: Container am Netz aus einem früheren Lauf → zuerst entfernt, dann Regeln und Netz; Lauf grün, Sperre beim Start gesetzt"
mutant_37 66-ohne-container-abraeumen 's#^  remove_fetch_containers || die .*$#  :#'
orphan_setup_66 "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): ohne Entfernen der Container beim Abräumen der Reste ist derselbe Prüfer rot"
mutant_37 66-regeln-vor-container 's#^  remove_fetch_containers || die .*$#  :#; s#^  remove_fetch_rules; remove_fetch_network$#  remove_fetch_rules; remove_fetch_containers; remove_fetch_network#'
orphan_setup_66 "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): Regeln vor den Containern entfernt (alte Reihenfolge) → derselbe Prüfer ist rot"
# Container nicht entfernbar → rot, Regeln bleiben stehen (fail-closed), kein Container
st_66; : > "$D66/net"; : > "$D66/orphan"; : > "$D66/fail-rm"; printf '%s\n' "$EXP_INPUT_66" > "$D66/chains/INPUT"; run_66 iso
assert_true "$([ "$rc_66" -eq 1 ] && grep -qF 'Container' <<< "$out_66" && ! grep -qx run "$D66/calls.log" && [ "$(cat "$D66/chains/INPUT")" = "$EXP_INPUT_66" ]; echo $?)" "#66 W1: Container am Netz nicht entfernbar → rot, Regeln bleiben stehen, kein Container"
# Der Container überlebt den Lauf (Signal): der Abbau entfernt ihn vor den Regeln
orphan_teardown_66() { # [<skript>]
  st_66; : > "$D66/orphan-after-run"; run_66 iso "$@"
  [ "$rc_66" -eq 0 ] && rm_before_D_66 run && [ ! -e "$D66/orphan" ] && cleaned_66
}
orphan_teardown_66; assert_exit 0 "$?" "#66 W1: Container überlebt den Lauf → beim Abbau zuerst entfernt, dann Regeln und Netz"
mutant_37 66-abbau-ohne-container 's#^  remove_fetch_containers || { warn .*$#  :#'
orphan_teardown_66 "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): Abbau ohne Entfernen der Container → derselbe Prüfer ist rot"
# Entfernen scheitert beim Abbau: Regeln bleiben stehen (fail-safe), Warnung
st_66; : > "$D66/orphan-after-run"; : > "$D66/fail-rm"; run_66 iso
assert_true "$([ "$rc_66" -eq 0 ] && grep -qF 'Container' <<< "$out_66" && [ "$(cat "$D66/chains/INPUT")" = "$EXP_INPUT_66" ]; echo $?)" "#66 W1: Container beim Abbau nicht entfernbar → Warnung, Regeln bleiben stehen (fail-safe)"

# ── E41: ein fetch-Lauf je Docker-Host (host-weiter Lock) ───────────────────────────────────────────────────────────
# lock_first_66 – der Lock kommt direkt nach require_docker, vor jedem Netz- oder iptables-Aufruf; Wartezeit begrenzt, fd 9
lock_first_66() {
  awk '/^flock$/ && !lock { lock = NR; after_info = (prev == "info") } /^(network-|iptables |sudo -n )/ && !first { first = NR }
       { prev = $0 } END { exit !(lock && after_info && first > lock) }' "$D66/calls.log" \
    && [ "$(tr '\0' ' ' < "$D66/flock.argv")" = "-w 900 9 " ]
}
for mode_66 in iso smoke; do
  fresh_66 "$mode_66"; assert_true "$([ "$rc_66" -eq 0 ] && lock_first_66; echo $?)" "#66 E41 ($mode_66): host-weiter Lock vor Netz und Regeln"
done
# busy_66 <modus> [<skript>] – ein anderer Lauf hält den Lock und hat Netz und Regeln gesetzt: rot, sein Zustand bleibt unberührt
busy_66() {
  st_66; : > "$D66/net"; : > "$D66/flock-busy"
  printf '%s\n' "$EXP_INPUT_66" > "$D66/chains/INPUT"; printf '%s\n' "$EXP_DOCKER_USER_66" > "$D66/chains/DOCKER-USER"
  run_66 "$@"
  [ "$rc_66" -eq 1 ] && grep -qF 'anderer fetch-Lauf' <<< "$out_66" && [ -e "$D66/net" ] \
    && [ "$(cat "$D66/chains/INPUT")" = "$EXP_INPUT_66" ] && [ "$(cat "$D66/chains/DOCKER-USER")" = "$EXP_DOCKER_USER_66" ] \
    && ! grep -qE '^(network-(create|rm)|iptables -[ID] |build$|run$)' "$D66/calls.log"
}
for mode_66 in iso smoke; do
  busy_66 "$mode_66"; assert_exit 0 "$?" "#66 E41/E39 ($mode_66): Lock gehalten (paralleler Lauf auf demselben Docker-Host) → rot, Netz und Regeln des anderen Laufs unberührt, kein Container"
done
mut_busy_66() { # <name> <sed-ausdruck> – Mutante → der parallele Lauf zerstört die Sperre des anderen
  mutant_37 "66-$1" "$2"; busy_66 iso "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): $1 → derselbe Prüfer ist rot"
}
mut_busy_66 ohne-lock 's#^  acquire_fetch_lock$#  :#'
mut_busy_66 lock-fehler-ignoriert 's#\|\| die "host-weiter Lock#|| true "host-weiter Lock#'
mut_busy_66 abraeumen-vor-lock 's#^  acquire_fetch_lock$#  FETCH_NET_ACTIVE=1; acquire_fetch_lock#'
# lock_held_66 – fd 9 ist beim Container-Start und beim Abräumen des Netzes noch offen: gehalten bis zum Prozessende
lock_held_66() { [ "$(cat "$D66/lock-at-run" 2>/dev/null)" = 1 ] && [ "$(cat "$D66/lock-at-net-rm" 2>/dev/null)" = 1 ]; }
for mode_66 in iso smoke; do
  fresh_66 "$mode_66"; assert_true "$([ "$rc_66" -eq 0 ] && lock_held_66; echo $?)" "#66 E41 ($mode_66): Lock über Container und Abräumen gehalten"
done
mutant_37 66-lock-vor-container-frei '/^mode_fetch_isolated\(\)/,/^\}/s#^  setup_fetch_network$#  setup_fetch_network; exec 9>\&-#'
fresh_66 iso "$MUT37"; assert_true "$(! lock_held_66; echo $?)" "#66 AK4.2 (Mutation): Lock vor dem Container freigegeben → derselbe Prüfer ist rot"
# Der Lauscher der Smoke-Probe läuft im Hintergrund und erbt fd 9 nicht – sonst hielte er den Lock über das Skriptende hinaus
fresh_66 smoke; assert_true "$([ "$rc_66" -eq 0 ] && [ "$(cat "$D66/lock-at-listener")" = 0 ]; echo $?)" "#66 E41: der Lauscher erbt den Lock nicht"
mutant_37 66-lauscher-erbt-lock 's#2>&1 9>&- &$#2>\&1 \&#'
fresh_66 smoke "$MUT37"; assert_true "$([ "$(cat "$D66/lock-at-listener")" = 1 ]; echo $?)" "#66 AK4.2 (Mutation): Lauscher ohne 9>&- → derselbe Prüfer ist rot"

# ── E40 c/AK4.3: Netz-Probe des Smoke-Jobs ───────────────────────────────────────────────────────────────────────────
# Der Host startet den Lauscher auf dem Gateway, reicht Gateway und Port in den Container und räumt den Lauscher ab
fresh_66 smoke
listener_gone_66() { local pid n; pid="$(cat "$D66/listener.pid" 2>/dev/null)" || return 1; for n in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
assert_true "$([ "$rc_66" -eq 0 ] && tr '\0' ' ' < "$D66/listener.argv" | grep -qF -- "-m http.server --bind $GATEWAY_66 " \
  && [ "$(tr '\0' ' ' < "$D66/run-pos.argv")" = "_ $GATEWAY_66 $PORT_66 " ] && listener_gone_66; echo $?)" \
  "#66 E40 c: Lauscher auf dem Gateway von factory-fetch, Gateway und Port als Positionsargumente in den Container, Lauscher danach beendet"
st_66; : > "$D66/fail-listener"; run_66 smoke
assert_true "$([ "$rc_66" -eq 1 ] && grep -qF 'Gegenprobe' <<< "$out_66" && ! grep -qx run "$D66/calls.log" && cleaned_66; echo $?)" \
  "#66 E40 c: Gegenprobe scheitert (Host erreicht den Lauscher nicht) → rot, kein Container – die Probe hätte keine Aussage"
gateway_refused_66() { # <gateway-ausgabe> [<skript>] – 0 = Smoke rot mit Meldung, kein Container
  st_66; printf '%s\n' "$1" > "$D66/gateway"; run_66 smoke "${2:-}"
  [ "$rc_66" -eq 1 ] && grep -qF 'Gateway' <<< "$out_66" && ! grep -qx run "$D66/calls.log"
}
gateway_refused_66 ''; assert_exit 0 "$?" "#66 E39: Gateway für die Smoke-Probe nicht ermittelbar → Smoke-Job rot"
gateway_refused_66 '0.0.0.0 --directory /'; assert_exit 0 "$?" "#66 E39: Gateway keine IPv4-Adresse → Smoke-Job rot, bevor der Lauscher startet"
mutant_37 66-gateway-ohne-form 's#\|\| die "Gateway von#|| true "Gateway von#'
gateway_refused_66 '0.0.0.0 --directory /' "$MUT37"; assert_exit 1 "$?" "#66 AK4.2 (Mutation): ohne Formprüfung des Gateways ist derselbe Fall nicht mehr rot"

# Das Smoke-Skript selbst (out-mode probe: läuft echt, curl im Container erreicht nur, was in reachable steht)
probe_66() { # [<ziel, das erreichbar ist>] [<skript>] – Exit von fetch-smoke
  st_66; [ -z "${1:-}" ] || printf '%s\n' "$1" >> "$D66/reachable"; run_66 smoke "${2:-}" probe; return "$rc_66"
}
probe_66; assert_exit 0 "$?" "#66 AK4.3: Probe grün, wenn Gateway, 169.254.169.254 und 168.63.129.16 unerreichbar sind und github.com erreichbar ist"
assert_true "$(grep -E 'https://github\.com$' "$D66/ctr-curl.log" | grep -qF -- '--retry'; echo $?)" "#66 Q5: HTTPS zu github.com mit curl --retry"
probe_66 "http://$GATEWAY_66:$PORT_66/"; assert_exit 1 "$?" "#66 AK4.3: Gateway des Hosts erreichbar → Smoke-Job rot"
probe_66 http://169.254.169.254/; assert_exit 1 "$?" "#66 AK4.3: IMDS 169.254.169.254 erreichbar → Smoke-Job rot"
probe_66 http://168.63.129.16/; assert_exit 1 "$?" "#66 AK4.3: WireServer 168.63.129.16 erreichbar → Smoke-Job rot"
st_66; : > "$D66/reachable"; run_66 smoke "" probe; assert_exit 1 "$rc_66" "#66 AK4.3/F3: github.com nicht erreichbar → Smoke-Job rot"
st_66; printf 'fe800000000000000000000000000001 02 40 20 80     eth0\n' >> "$D66/if_inet6"; run_66 smoke "" probe
assert_exit 1 "$rc_66" "#66 AK1.4/E37: IPv6-Adresse außer lo im Container → Smoke-Job rot"
st_66; rm -f "$D66/if_inet6"; run_66 smoke "" probe; assert_exit 0 "$rc_66" "#66 AK1.4/E37: gar kein IPv6 im Container → erfüllt"
mut_probe_66() { # <name> <sed-ausdruck> <erreichbares-ziel> – Mutante des Smoke-Skripts → derselbe Fall wird grün
  mutant_37 "66-$1" "$2"; probe_66 "$3" "$MUT37"; assert_exit 0 "$?" "#66 AK4.2 (Mutation): $1 → derselbe Fall ist nicht mehr rot"
}
mut_probe_66 probe-ohne-gateway 's#&& blocked "http://\$1:\$2/" ##' "http://$GATEWAY_66:$PORT_66/"
mut_probe_66 probe-ohne-imds 's#&& blocked http://169\.254\.169\.254/ ##' http://169.254.169.254/
mut_probe_66 probe-ohne-wireserver 's#&& blocked http://168\.63\.129\.16/ ##' http://168.63.129.16/
# Gesperrt heißt abgewiesen (REJECT → curl-Exit 7), nicht bloß unerreichbar: ein Timeout belegt die Regel nicht
timeout_66() { # <ziel> [<skript>] – Exit von fetch-smoke, wenn <ziel> in den Timeout läuft
  st_66; printf '%s\n' "$1" > "$D66/timeout"; run_66 smoke "${2:-}" probe; return "$rc_66"
}
for target_66 in "http://$GATEWAY_66:$PORT_66/" http://169.254.169.254/ http://168.63.129.16/; do
  timeout_66 "$target_66"; assert_exit 1 "$?" "#66 AK4.3: $target_66 läuft in den Timeout statt abgewiesen zu werden → Smoke-Job rot (Regel nicht belegt)"
  assert_true "$(grep -qF "$target_66 → curl-Exit 28" <<< "$out_66"; echo $?)" "#66 AK4.3: die Meldung nennt Ziel und curl-Exit (${target_66})"
done
mutant_37 66-probe-jeder-fehler 's#^FETCH_SMOKE_SCRIPT=.blocked\(\) \{.*$#FETCH_SMOKE_SCRIPT='"'"'blocked() { ! curl -s -o /dev/null --max-time 5 "$1"; }#'
timeout_66 http://169.254.169.254/ "$MUT37"; assert_exit 0 "$?" "#66 AK4.2 (Mutation): jeder curl-Fehler gilt als gesperrt → derselbe Fall ist nicht mehr rot"

# ── AK5: Doku-Guards ─────────────────────────────────────────────────────────────────────────────────────────────────
ops_ok_66() { # $1 = geglätteter Text von OPERATING.md
  local p
  for p in 'vom Host und von den Link-Local-Diensten' 'passwortloses `sudo` und `iptables`' 'Nachtrag 2026-11-21' 'Restrisiko im Netz' \
    'nur ein `fetch` je Docker-Host' 'greift der Lock **nicht**'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
}
adr_ok_66() { # $1 = geglätteter Text von ADR-063
  local p
  for p in 'Status: Accepted (2026-11-21' '**Ersetzt** durch den Nachtrag 2026-11-21 (#66,' 'Präzisiert im Nachtrag 2026-11-21 (#66)' 'E40 · Tests (ergänzt E34).' \
    'E41 · Ein fetch-Lauf je Docker-Host' '*Gemeinsamer Docker-Daemon, getrenntes `/tmp`:*' '*Namen je Lauf statt Lock (zu E41):*'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
}
sec_ok_66() { grep -qF -- '**Ablage: #66**' "$1" && ! grep -qF -- 'Ablage (ADR-043, Zweifelsregel → Issue): offen.' "$1"; }
ops_66="$(tr '\n' ' ' < "$FACTORY_ROOT/docs/factory/OPERATING.md" | tr -s ' ')"
adr_66="$(tr '\n' ' ' < "$FACTORY_ROOT/docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md" | tr -s ' ')"
ops_ok_66 "$ops_66"; assert_exit 0 "$?" "#66 AK5.2: OPERATING.md §0.6 nennt die Netz-Sperre, die Voraussetzung (passwortloses sudo, iptables) und das Restrisiko"
ops_ok_66 "$(strip_literal_37 "$ops_66" 'passwortloses `sudo` und `iptables`')"; assert_exit 1 "$?" "#66 AK5.2 (Mutation): ohne die Voraussetzung ist derselbe Guard rot"
adr_ok_66 "$adr_66"; assert_exit 0 "$?" "#66 AK5.1: ADR-063 Nachtrag 2026-11-21 Accepted, E31 Q3 und Restrisiko 2 verweisen auf #66"
adr_ok_66 "$(strip_literal_37 "$adr_66" '**Ersetzt** durch den Nachtrag 2026-11-21 (#66,')"; assert_exit 1 "$?" "#66 AK5.1 (Mutation): ohne den Verweis in E31 ist derselbe Guard rot"
# security-41.md liegt unter tasks/ (Seite project) – nur prüfen, wo es sie gibt (konsumenten-neutral)
sec_66="$FACTORY_ROOT/tasks/security-41.md"
if [ -f "$sec_66" ]; then
  sec_ok_66 "$sec_66"; assert_exit 0 "$?" "#66 AK5.3: tasks/security-41.md, Hinweis „Netz“ verweist auf #66"
fi

factory_lock_template_unchanged
test_group_finish; exit $?
