#!/usr/bin/env bash
# factory-lock-41-tests.sh – Testgruppe Factory-Issue #41: Release-Code des Jobs `fetch` läuft im unprivilegierten Container
# (Factory-ADR-063, Nachtrag 2026-11-20 E28–E34) – Verdrahtung, docker-run-Argumente, Rückweg, Sperre von `fetch` in CI,
# Ende-zu-Ende über eine Container-Nachbildung, Smoke-Modus, Doku-Guards; je tragender Eigenschaft ein Mutationsbeleg.
#
# Läuft als eigener Teilprozess der Suite scripts/checks/tests/run-tests.sh (Factory-ADR-066) und ist allein startbar:
#   bash scripts/checks/tests/factory-lock-41-tests.sh
# Docker wird nicht gebraucht: ein Fake-`docker` im PATH protokolliert argv und spielt die Ausgabe des Containers nach (E34 b/c).
# Fixtures und Helfer: lib/factory-lock-fixtures.sh.

set -uo pipefail

TESTS_DIR_41="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib_41 in assert-helpers test-groups factory-lock-fixtures; do
  # shellcheck source=/dev/null
  source "$TESTS_DIR_41/lib/$lib_41.sh" || { echo "$(basename "$0"): Helfer-Lib nicht ladbar: lib/$lib_41.sh (fail-closed)" >&2; exit 2; }
done

# Ohne yq entfällt die Gruppe still: die Skip-Zeile für #23/#24/#37 schreibt factory-lock-23-tests.sh
[ "$HAS_YQ" -eq 1 ] || { test_group_finish; exit $?; }
factory_lock_setup
factory_lock_setup_24
world_23 basis41   # U23/R23 für env_23 in den Argument-Tests (die Abholung selbst läuft dort nur im Fake)
echo ""
echo "Factory-Issue #41: Release-Code im Container (Runtime-Token abschirmen):"

# Erwarteter Aufruf (E31) – im Test festgeschrieben, nicht aus dem Skript gelesen: eine Änderung im Skript fällt hier auf.
IMAGE_41="factory-update-fetch:local"
SCRIPT_41='cp -a /src/. /tmp/work && bash /tmp/work/scripts/factory-update.sh fetch "$1" "$2" /out/update.bundle'
RUN_LINE_41='bash scripts/factory-update.sh fetch-isolated "$VERSION" "$BASE_SHA" "$RUNNER_TEMP/fetch-out"'
SMOKE_LINE_41='bash scripts/factory-update.sh fetch-smoke "$RUNNER_TEMP/fetch-smoke"'
YQ_41="$(command -v yq)"
CI_WF_41="$FACTORY_ROOT/.github/workflows/factory-ci.yml"

# Fakes für docker, sudo und iptables (lib/factory-lock-fixtures.sh); FAKE_HOST_66 nur für fetch-smoke (Lauscher der Netz-Probe, #66)
fetch_fakes_41
# docker_calls_41 <calls.log> – das Protokoll ohne genau die bekannten Zeilen der Netz-Sperre (#66: Lock, Netz, Regeln, Container am Netz – ps/rm; die prüft
# factory-lock-66-tests.sh); jeder andere Aufruf (exec, cp, pull …) bleibt im exakten Vergleich stehen
docker_calls_41() {
  grep -vxE 'flock|ps|rm|network-(inspect|create|rm)|sudo -n iptables|iptables -[ICD] (INPUT|DOCKER-USER)' "$1" | tr '\n' ' '
}

# fd_41 <name> <out-mode> – frischer Zustand des Fakes; setzt FD_41 (Zustand), RT_41 (RUNNER_TEMP), OUT_41, ROOT_41 (Checkout)
fd_41() {
  FD_41="$T23/fd-$1"; RT_41="$FD_41/rt"; OUT_41="$RT_41/fetch-out"; ROOT_41="${ROOT_41_OVERRIDE:-$FD_41/root}"
  mkdir -p "$FD_41" "$RT_41/_runner_file_commands" "$FD_41/root"; : > "$FD_41/calls.log"; printf '%s\n' "$2" > "$FD_41/out-mode"
}
# iso_41 [<skript>] – Modus fetch-isolated wie im Job fetch: CI-Umgebung samt Runner-Dateien und Runtime-Token (Worst Case: auch
# FACTORY_SYNC_TOKEN); setzt out_41/rc_41
iso_41() {
  out_41="$(env_23 "$ROOT_41" env PATH="$FAKE_41:$PATH" FAKE_DOCKER_STATE="$FD_41" GITHUB_ACTIONS=true RUNNER_TEMP="$RT_41" \
    GITHUB_ENV="$RT_41/_runner_file_commands/set_env_41" GITHUB_PATH="$RT_41/_runner_file_commands/add_path_41" \
    GITHUB_OUTPUT="$RT_41/_runner_file_commands/set_output_41" GITHUB_STEP_SUMMARY="$RT_41/_runner_file_commands/step_summary_41" \
    ACTIONS_RUNTIME_TOKEN=runtime-token-41 ACTIONS_CACHE_URL=https://cache.invalid/ FACTORY_SYNC_TOKEN="$GOOD_TOKEN_24" \
    bash "${1:-$UPD_24}" fetch-isolated "${VER_41-v1.1.0}" "${BASE_41-$(printf 'a%.0s' $(seq 40))}" "$OUT_41")"; rc_41=$?
}

# ── E31: Argumente von docker run ────────────────────────────────────────────────────────────────────────────────────
# run_exact_41 <argv> <root> <out> <version> <base> – argv ist genau der Aufruf aus E31, ergänzt um Netz und IPv6-Sperre aus
# E35/E37 (#66) (jede Zusatzoption macht ihn rot)
run_exact_41() {
  printf '%s\0' run --rm --network factory-fetch --sysctl net.ipv6.conf.all.disable_ipv6=1 --cap-drop ALL --security-opt no-new-privileges --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$2:/src:ro" -v "$3:/out" -v "$YQ_41:/usr/local/bin/yq:ro" "$IMAGE_41" bash -c "$SCRIPT_41" _ "$4" "$5" | cmp -s - "$1"
}
# run_forbidden_free_41 <argv> – unabhängige Prüfung: keine Sonderrechte, keine Runner-Dateien/Token, genau drei Mounts, ein -e,
# genau ein Netz (getrennt übergebenes --network factory-fetch, E35) und genau ein --sysctl (IPv6 aus, E37)
run_forbidden_free_41() {
  local x n_v=0 n_e=0 n_net=0 n_sys=0 p prev=""
  while IFS= read -r -d '' x; do
    # getrennt übergebenes --security-opt <wert>: nur no-new-privileges ist erlaubt (systempaths=unconfined u. a. nicht)
    [ "$prev" != --security-opt ] || [ "$x" = no-new-privileges ] || return 1
    # getrennt übergebenes --network <wert>: nur das eigene Netz (host, bridge, none, container:… nicht)
    [ "$prev" != --network ] || [ "$x" = factory-fetch ] || return 1
    # getrennt übergebenes --sysctl <wert>: nur IPv6 aus
    [ "$prev" != --sysctl ] || [ "$x" = net.ipv6.conf.all.disable_ipv6=1 ] || return 1
    prev="$x"
    case "$x" in
      --network) n_net=$((n_net + 1)) ;;
      --sysctl) n_sys=$((n_sys + 1)) ;;
      --privileged*|--pid*|--ipc*|--uts*|--userns*|--cgroupns*|--network*|--net|--net=*|--cap-add*|--device*|--env-file*|--mount*) return 1 ;;
      --volumes-from*|--security-opt=*|--sysctl*|--group-add*|--add-host*|*docker.sock*|*seccomp*|*apparmor*|*ACTIONS_*|*GITHUB_*|*TOKEN*) return 1 ;;
      "$RT_41:"*) return 1 ;;
      -v|--volume) n_v=$((n_v + 1)) ;;
      -e|--env) n_e=$((n_e + 1)) ;;
    esac
    for p in runtime-token-41 "$GOOD_TOKEN_24" _runner_file_commands; do [[ "$x" != *"$p"* ]] || return 1; done
  done < "$1"
  [ "$n_v" = 3 ] && [ "$n_e" = 1 ] && [ "$n_net" = 1 ] && [ "$n_sys" = 1 ]
}
# dockerfile_ok_41 – Image: Basis per Digest, nur die vier Pakete, Build ohne Kontext (E30)
dockerfile_ok_41() {
  printf '%s\0' build -t "$IMAGE_41" - | cmp -s - "$FD_41/build.argv" || return 1
  [ "$(wc -l < "$FD_41/Dockerfile" | tr -d ' ')" = 2 ] || return 1
  grep_in "$(sed -n 1p "$FD_41/Dockerfile")" -qxE 'FROM debian:[a-z]+-slim@sha256:[0-9a-f]{64}' || return 1
  [ "$(sed -n 2p "$FD_41/Dockerfile")" = 'RUN apt-get update && apt-get install -y --no-install-recommends git jq curl ca-certificates && rm -rf /var/lib/apt/lists/*' ]
}
# args_ok_41 [<skript>] – fetch-isolated mit Fake (Ausgabe: reguläre Datei): grün, Reihenfolge info → build → run, Aufruf genau E31
args_ok_41() {
  fd_41 "args$((N_24 += 1))" file; iso_41 "${1:-}"
  [ "$rc_41" -eq 0 ] && [ "$(docker_calls_41 "$FD_41/calls.log")" = 'info build run ' ] && dockerfile_ok_41 \
    && run_exact_41 "$FD_41/run.argv" "$ROOT_41" "$OUT_41" v1.1.0 "$(printf 'a%.0s' $(seq 40))" && run_forbidden_free_41 "$FD_41/run.argv"
}
args_ok_41; assert_exit 0 "$?" "#41 AK1.2–AK1.4/E31: docker run genau mit E31 (cap-drop ALL, no-new-privileges, Runner-UID, nur HOME, drei Mounts), Image aus gepinnter Basis ohne Kontext"
# Mutationsbelege: Mutant des Skripts → derselbe Prüfer rot
mut_args_41() { mutant_37 "41-$1" "$2"; args_ok_41 "$MUT37"; assert_exit 1 "$?" "#41 AK4.2 (Mutation): $1 → derselbe Prüfer ist rot"; }
mut_args_41 ohne-cap-drop 's#--cap-drop ALL ##'
mut_args_41 ohne-no-new-privileges 's#--security-opt no-new-privileges ##'
mut_args_41 privileged 's#--cap-drop ALL #--cap-drop ALL --privileged #'
mut_args_41 pid-host 's#--cap-drop ALL #--cap-drop ALL --pid=host #'
mut_args_41 network-host 's#--cap-drop ALL #--cap-drop ALL --network=host #'
mut_args_41 cap-add 's#--cap-drop ALL #--cap-drop ALL --cap-add SYS_PTRACE #'
mut_args_41 docker-socket 's#-e HOME=/tmp#-e HOME=/tmp -v /var/run/docker.sock:/var/run/docker.sock#'
mut_args_41 runner-datei-als-variable 's#-e HOME=/tmp#-e HOME=/tmp -e GITHUB_ENV#'
mut_args_41 actions-variable 's#-e HOME=/tmp#-e HOME=/tmp -e ACTIONS_RUNTIME_TOKEN#'
mut_args_41 env-file 's#-e HOME=/tmp#-e HOME=/tmp --env-file "$GITHUB_ENV"#'
mut_args_41 runner-temp-eingebunden 's#-e HOME=/tmp#-e HOME=/tmp -v "$RUNNER_TEMP:/rt"#'
mut_args_41 als-root 's#--user "\$\(id -u\):\$\(id -g\)"#--user 0:0#'
mut_args_41 checkout-schreibbar 's#:/src:ro#:/src#'
mut_args_41 image-ohne-digest 's#^(FETCH_BASE_IMAGE="debian:[a-z]+-slim)@sha256:[0-9a-f]+"#\1"#'
mut_args_41 build-mit-kontext 's#docker build -t "\$FETCH_IMAGE" -#docker build -t "$FETCH_IMAGE" -f - .#'
# Ein zusätzlicher, tolerierter docker-Aufruf fällt im Protokollvergleich auf (der Filter für #66 nimmt nur bekannte Zeilen heraus)
mut_args_41 zusaetzlicher-docker-aufruf 's#^  fetch_dockerfile \| docker build#  docker pull "$FETCH_BASE_IMAGE" >/dev/null 2>\&1 || true; fetch_dockerfile | docker build#'
# Der Digest ist ein echter Pin, kein Platzhalter aus lauter Nullen (die Form allein belegt nichts)
digest_real_41() { ! grep -qE '^FETCH_BASE_IMAGE=".*@sha256:0{64}"$' "$1" && grep -qE '^FETCH_BASE_IMAGE="debian:[a-z]+-slim@sha256:[0-9a-f]{64}"$' "$1"; }
digest_real_41 "$UPD_24"; assert_exit 0 "$?" "#41 AK1.4: FETCH_BASE_IMAGE trägt einen echten Digest (kein Nullen-Platzhalter)"
sed -E 's#@sha256:[0-9a-f]{64}"#@sha256:'"$(printf '0%.0s' $(seq 64))"'"#' "$UPD_24" > "$T23/m41-digest.sh"
digest_real_41 "$T23/m41-digest.sh"; assert_exit 1 "$?" "#41 AK1.4 (Mutation): Platzhalter-Digest → derselbe Prüfer ist rot"
# Der unabhängige Verbots-Prüfer allein (falls der exakte Vergleich einmal mitgezogen würde)
fd_41 fv1 file; iso_41; run_forbidden_free_41 "$FD_41/run.argv"; assert_exit 0 "$?" "#41 AK1.2/AK1.3: Verbots-Prüfer grün am echten Aufruf"
for bad_41 in --privileged --pid=host --network=host "--network host" "--network bridge" "--network none" "--network container:x" \
  "--sysctl kernel.shm_rmid_forced=1" --add-host=x:1.2.3.4 --cap-add=ALL "-v /var/run/docker.sock:/var/run/docker.sock" "--env-file x" "-e ACTIONS_RUNTIME_TOKEN" "-v $RT_41:/rt" --cgroupns=host "--security-opt systempaths=unconfined"; do
  { tr '\0' '\n' < "$FD_41/run.argv" | sed -n 1p; printf '%s\n' $bad_41; tr '\0' '\n' < "$FD_41/run.argv" | sed '1d'; } | tr '\n' '\0' > "$FD_41/bad.argv"
  run_forbidden_free_41 "$FD_41/bad.argv"; assert_exit 1 "$?" "#41 AK4.2 (Mutation): Verbots-Prüfer erkennt „${bad_41}“"
done
# Wertprüfung isoliert (#66): der Wert von --network bzw. --sysctl wird ersetzt, die Anzahl bleibt gleich
for swap_41 in 's#^factory-fetch$#host#' 's#^net\.ipv6\.conf\.all\.disable_ipv6=1$#net.ipv6.conf.all.disable_ipv6=0#'; do
  tr '\0' '\n' < "$FD_41/run.argv" | sed "$swap_41" | tr '\n' '\0' > "$FD_41/swap.argv"
  assert_true "$(! cmp -s "$FD_41/run.argv" "$FD_41/swap.argv"; echo $?)" "#41 Mutation „${swap_41}“: der Aufruf ist verändert (Voraussetzung)"
  run_forbidden_free_41 "$FD_41/swap.argv"; assert_exit 1 "$?" "#41 AK4.2 (Mutation): Verbots-Prüfer erkennt den ersetzten Wert „${swap_41}“"
done

# Der feste Pfad im Container-Skript und die Konstante, gegen die der Rückweg prüft, bleiben gleich (sonst fiele es erst in E32 auf)
bundle_const_ok_41() { # <skript>
  local c; c="$(sed -n 's/^FETCH_BUNDLE="\(.*\)"$/\1/p' "$1")"
  [ -n "$c" ] && grep -qE "^FETCH_CONTAINER_SCRIPT=.* /out/${c}'\$" "$1"
}
bundle_const_ok_41 "$UPD_24"; assert_exit 0 "$?" "#41 E32: FETCH_BUNDLE und der Ausgabepfad im Container-Skript stimmen überein"
mutant_37 41-bundle-name 's#^FETCH_BUNDLE="update.bundle"#FETCH_BUNDLE="other.bundle"#'
bundle_const_ok_41 "$MUT37"; assert_exit 1 "$?" "#41 AK4.2 (Mutation): abweichender Bundle-Name → derselbe Prüfer ist rot"

# ── E32/E33: Rückweg und Fail-closed (Spec F1–F4) ────────────────────────────────────────────────────────────────────
# ret_41 <out-mode> [<skript>] – Exit von fetch-isolated bei dieser Container-Ausgabe
ret_41() { fd_41 "ret$((N_24 += 1))" "$1"; iso_41 "${2:-}"; return "$rc_41"; }
ret_41 file; assert_exit 0 "$?" "#41 E32: genau eine reguläre Datei update.bundle → grün"
ret_41 none; assert_exit 1 "$?" "#41 F3: kein Bundle → rot (kein Artefakt, publish läuft nicht)"
ret_41 symlink; assert_exit 1 "$?" "#41 F4: Symlink statt Bundle → rot (nichts von außerhalb des Ausgabeverzeichnisses)"
assert_contains_286 "$out_41" 'genau die reguläre Datei' "#41 F4: die Meldung nennt die erwartete Ausgabe"
ret_41 dir; assert_exit 1 "$?" "#41 F4: Verzeichnis statt Bundle → rot"
ret_41 two; assert_exit 1 "$?" "#41 E32: zwei Einträge im Ausgabeverzeichnis → rot"
mutant_37 41-rueckweg 's#^  \[ "\$entries" = "\$FETCH_BUNDLE" \] && \[ -f "\$1/\$FETCH_BUNDLE" \] && \[ ! -L "\$1/\$FETCH_BUNDLE" \]#  true#'
ret_41 symlink "$MUT37"; assert_exit 0 "$?" "#41 AK4.2 (Mutation): ohne Prüfung des Rückwegs käme der Symlink durch – die Prüfung ist wirksam"
# Ausgabeverzeichnis existiert schon → rot, kein Container
fd_41 pre1 file; mkdir -p "$OUT_41"; iso_41
assert_true "$([ "$rc_41" -eq 1 ] && grep -qF 'existiert schon' <<< "$out_41" && ! grep -qx run "$FD_41/calls.log"; echo $?)" "#41 E32: Ausgabeverzeichnis existiert schon → rot, kein Container gestartet"
# Docker fehlt/scheitert, Build scheitert, Container scheitert → rot, kein stiller Rückfall
fail_41() { # <fail-datei> <meldung> [<skript>] – 0 = rot mit Meldung und ohne Bundle
  fd_41 "fail$((N_24 += 1))" file; : > "$FD_41/$1"; iso_41 "${3:-}"
  [ "$rc_41" -eq 1 ] && grep -qF -- "$2" <<< "$out_41" && [ ! -e "$OUT_41/update.bundle" ]
}
fail_41 fail-info 'braucht Docker'; assert_exit 0 "$?" "#41 F1: kein Docker → rot mit Hinweis, kein Rückfall auf Ausführung ohne Container"
assert_true "$([ "$(cat "$FD_41/calls.log")" = info ]; echo $?)" "#41 F1: ohne Docker weder Build noch Container"
mutant_37 41-info 's#\|\| die "fetch braucht Docker#|| true "fetch braucht Docker#'
fail_41 fail-info 'braucht Docker' "$MUT37"; assert_exit 1 "$?" "#41 F1 (Mutation): ohne dieses die läuft der Lauf weiter – die Prüfung ist wirksam"
fail_41 fail-build 'nicht baubar'; assert_exit 0 "$?" "#41 F2: Image nicht baubar (Basis/Digest/apt) → rot"
assert_true "$(! grep -qx run "$FD_41/calls.log"; echo $?)" "#41 F2: nach gescheitertem Build kein Container"
mutant_37 41-build 's#\|\| die "Image für fetch nicht baubar#|| true "Image für fetch nicht baubar#'
fail_41 fail-build 'nicht baubar' "$MUT37"; assert_exit 1 "$?" "#41 F2 (Mutation): ohne dieses die ist derselbe Fall nicht mehr rot"
fail_41 fail-run 'im Container gescheitert'; assert_exit 0 "$?" "#41 F3: Container endet ≠ 0 → rot"
mutant_37 41-run 's#\|\| die "Abholung von \$1 im Container gescheitert#|| true "Abholung von $1 im Container gescheitert#'
fail_41 fail-run 'im Container gescheitert' "$MUT37"; assert_exit 1 "$?" "#41 F3 (Mutation): ohne dieses die ist derselbe Fall nicht mehr rot"
# Übergabeargumente werden vor jedem docker-Aufruf geprüft
fd_41 arg1 file; VER_41='--privileged' iso_41
assert_true "$([ "$rc_41" -eq 1 ] && [ ! -s "$FD_41/calls.log" ]; echo $?)" "#41 E31: Version ohne Form vX.Y.Z → rot vor jedem docker-Aufruf"

# ── E29: Modus fetch verweigert in CI ────────────────────────────────────────────────────────────────────────────────
ci_fetch_41() { # [<skript>] – Modus fetch direkt mit GITHUB_ACTIONS=true; setzt out_24/rc_24
  world_24 "cf$((N_24 += 1))"; add_release_24 v1.1.0; releases_24 v1.0.0 v1.1.0; CL_37="$W24/clone37"; BUNDLE_37="$W24/u.bundle"
  git clone -q "$C1_23" "$CL_37"
  out_24="$(env_23 "$CL_37" env -u FACTORY_SYNC_TOKEN GITHUB_ACTIONS=true bash "${1:-$UPD_24}" fetch v1.1.0 "$(git -C "$ORIGIN_24" rev-parse main)" "$BUNDLE_37")"; rc_24=$?
}
ci_fetch_41
assert_true "$([ "$rc_24" -eq 1 ] && grep -qF 'fetch-isolated' <<< "$out_24" && [ ! -e "$BUNDLE_37" ]; echo $?)" "#41 E29: Modus fetch mit GITHUB_ACTIONS=true → rot mit Verweis auf fetch-isolated, kein Bundle"
mutant_37 41-ci-fetch 's#\[ "\$\{GITHUB_ACTIONS:-\}" != true \] \|\| die "fetch führt#true || die "fetch führt#'
ci_fetch_41 "$MUT37"
assert_true "$([ "$rc_24" -eq 0 ] && [ -s "$BUNDLE_37" ]; echo $?)" "#41 AK4.2 (Mutation): ohne die Sperre liefe Release-Code in CI direkt auf dem Runner – die Sperre ist wirksam"

# ── AK2.2/AK3.1: Ende zu Ende über die Container-Nachbildung ─────────────────────────────────────────────────────────
# e2e_41 <welt> <payload-funktion> [<skript>] – main trägt die Skripte (v1.1.0), Release v1.2.0 mit Nutzlast in factory-sync.sh;
# fetch-isolated im frischen Klon (Container nachgebildet), danach publish mit dem Bundle. Setzt CFG_BEFORE_41, rc_41, rc_24, out_24.
e2e_41() {
  hostile_world_41 "$1" "$2"
  ROOT_41_OVERRIDE="$CL_37" fd_41 "e2e-$1" emulate
  CFG_BEFORE_41="$(cat "$CL_37/.git/config"; ls -A "$CL_37/.git/hooks")"
  VER_41=v1.2.0 BASE_41="$BASE_37" iso_41 "${3:-}"
  BUNDLE_37="$OUT_41/update.bundle"; VER_37=v1.2.0
  pub_37
}
hostile_world_41() { # <welt> <payload-funktion> – wie hostile_37 in factory-lock-37a-tests.sh, ohne die Abholung selbst
  world_24 "$1"
  MARKLOG_41="$W24/marker.log"; MARKER_41="$W24/marker.sh"; : > "$MARKLOG_41"
  printf '#!/bin/sh\necho "RAN FST=${FACTORY_SYNC_TOKEN:-} ART=${ACTIONS_RUNTIME_TOKEN:-} GHE=${GITHUB_ENV:-} $*" >> "%s"\nexit 0\n' "$MARKLOG_41" > "$MARKER_41"; chmod +x "$MARKER_41"
  factory_scripts_24 "$U23" "$UPD_24"
  add_release_24 v1.1.0
  sync_23 "$C1_23" v1.1.0 >/dev/null
  git -C "$C1_23" add -A && git_23 -C "$C1_23" commit -q -m "adopt v1.1.0" && git -C "$C1_23" push -q origin main
  { echo; "$2"; } >> "$U23/scripts/factory-sync.sh"
  add_release_24 v1.2.0; releases_24 v1.0.0 v1.1.0 v1.2.0
  BASE_37="$(git -C "$ORIGIN_24" rev-parse main)"; CL_37="$W24/clone41"
  git clone -q "$C1_23" "$CL_37"
}
payload_41() { cat <<EOF
"$MARKER_41" sync
git -C "\$FACTORY_DIR" config core.fsmonitor "$MARKER_41"
mkdir -p "\$FACTORY_DIR/.git/hooks"
for h in pre-commit post-commit reference-transaction; do printf '#!/bin/sh\n"$MARKER_41" hook-%s\nexit 0\n' "\$h" > "\$FACTORY_DIR/.git/hooks/\$h"; chmod +x "\$FACTORY_DIR/.git/hooks/\$h"; done
true
EOF
}
no_secret_marker_41() { ! grep -qE 'FST=[^ ]|ART=[^ ]|GHE=[^ ]' "$MARKLOG_41"; }
e2e_41 e1 payload_41
assert_true "$([ "$rc_41" -eq 0 ] && [ "$rc_24" -eq 0 ] && [ "$(lock_on_branch_24)" = v1.2.0 ]; echo $?)" "#41 AK3.1: fetch-isolated → publish → Update-PR auf v1.2.0 wie bisher"
assert_true "$(grep -q 'RAN .* sync' "$MARKLOG_41"; echo $?)" "#41 AK2.2 (Voraussetzung): die Nutzlast des Release lief im (nachgebildeten) Container"
assert_true "$(no_secret_marker_41; echo $?)" "#41 AK1.3: kein Befehl des Release sah FACTORY_SYNC_TOKEN, ACTIONS_RUNTIME_TOKEN oder GITHUB_ENV – obwohl alle auf dem Host gesetzt waren"
assert_true "$([ "$CFG_BEFORE_41" = "$(cat "$CL_37/.git/config"; ls -A "$CL_37/.git/hooks")" ]; echo $?)" "#41 AK2.2: .git/config und Hooks des Checkouts unverändert (Release-Code arbeitet nur auf der Kopie)"
assert_true "$([ "$(ls -A "$OUT_41")" = update.bundle ]; echo $?)" "#41 AK2.1: im Ausgabeverzeichnis liegt danach nur das Bundle"
# Gleiches Ergebnis wie die Abholung ohne Container: derselbe Baum auf derselben Basis
iso_tree_41="$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^{tree}")"
CL2_41="$W24/clone41-direkt"; git clone -q "$C1_23" "$CL2_41"
env_23 "$CL2_41" env -u FACTORY_SYNC_TOKEN bash "$CL2_41/scripts/factory-update.sh" fetch v1.2.0 "$BASE_37" "$W24/direkt.bundle" >/dev/null
assert_true "$([ "$iso_tree_41" = "$(git -C "$CL2_41" rev-parse 'HEAD^{tree}')" ] && [ "$(git -C "$ORIGIN_24" rev-parse "refs/heads/$BR_24^")" = "$BASE_37" ]; echo $?)" \
  "#41 AK3.1: das Bundle aus dem Container trägt denselben Baum wie die Abholung ohne Container, ein Commit auf base_sha"
# Gegenprobe: reicht der Aufruf ein Token per -e durch, sieht die Nutzlast es – die Grenze ist es, die schützt
mutant_37 41-env-durch 's#-e HOME=/tmp#-e HOME=/tmp -e FACTORY_SYNC_TOKEN#'
e2e_41 e2 payload_41 "$MUT37"
assert_exit 1 "$(no_secret_marker_41; echo $?)" "#41 AK1.3 (Gegenprobe): mit durchgereichtem -e FACTORY_SYNC_TOKEN sieht die Nutzlast das Token – die Umgebungsgrenze ist wirksam"

# ── E34 f: Smoke-Modus nutzt denselben Aufruf ────────────────────────────────────────────────────────────────────────
fd_41 sm1 file; iso_41; cp "$FD_41/run.argv" "$T23/iso-41.argv"
fd_41 sm2 smoke
out_41="$(env_23 "$ROOT_41" env PATH="$FAKE_HOST_66:$FAKE_41:$PATH" FAKE_DOCKER_STATE="$FD_41" bash "$UPD_24" fetch-smoke "$RT_41/fetch-out")"; rc_41=$?
opts_41() { tr '\0' '\n' < "$1" | awk -v img="$IMAGE_41" '$0 == img { exit } { print }' | sed "s#^$2:/out\$#OUT#; s#^$3:/src:ro\$#SRC#"; }
assert_exit 0 "$rc_41" "#41 E34 f: fetch-smoke mit Fake → grün, auch ohne factory.lock (Factory-Repo selbst)"
assert_true "$([ "$(opts_41 "$T23/iso-41.argv" "$T23/fd-sm1/rt/fetch-out" "$T23/fd-sm1/root")" = "$(opts_41 "$FD_41/run.argv" "$OUT_41" "$ROOT_41")" ] && [ "$(docker_calls_41 "$FD_41/calls.log")" = 'info build run ' ]; echo $?)" \
  "#41 E34 f: fetch-smoke startet das Image mit genau denselben Optionen wie fetch-isolated (eine Stelle im Skript)"
fd_41 sm3 none
env_23 "$ROOT_41" env PATH="$FAKE_HOST_66:$FAKE_41:$PATH" FAKE_DOCKER_STATE="$FD_41" bash "$UPD_24" fetch-smoke "$RT_41/fetch-out" >/dev/null; assert_exit 1 "$?" "#41 E34 f: fetch-smoke ohne Nachweis aus dem Container (/out leer) → rot"

# ── AK4.1/AK2.1: Verdrahtung an der echten factory-update.yml ────────────────────────────────────────────────────────
# wf_fetch_ok_41 <workflow> – fetch hat genau: Checkout (main), yq, fetch-isolated, Upload des Bundles; sonst nichts
wf_fetch_ok_41() {
  local f="$1"
  [ "$(yq -o=json -I=0 '[.jobs.fetch.steps[] | (.uses // .run)]' "$f")" = \
    "$(jq -cn --arg r "$RUN_LINE_41" '["actions/checkout@v4", "sudo bash scripts/install-yq.sh", $r, "actions/upload-artifact@v4"]')" ] || return 1
  [ "$(yq -o=json -I=0 '.jobs.fetch.steps[2].env | keys' "$f")" = '["VERSION","BASE_SHA"]' ] || return 1
  [ "$(yq '.jobs.fetch.steps[2].env.VERSION' "$f")" = '${{ needs.preflight.outputs.version }}' ] || return 1
  [ "$(yq '.jobs.fetch.steps[2].env.BASE_SHA' "$f")" = '${{ needs.preflight.outputs.base_sha }}' ] || return 1
  [ "$(yq '.jobs.fetch | (has("env") or has("container") or has("services") or has("defaults"))' "$f")" = false ] || return 1
  [ "$(yq '.jobs.fetch.steps[3].with.path' "$f")" = '${{ runner.temp }}/fetch-out/update.bundle' ] || return 1
  [ "$(yq '.jobs.fetch.steps[3].with.if-no-files-found' "$f")" = error ] || return 1
  # kein run-Schritt irgendeines Jobs ruft den Modus fetch direkt auf
  ! grep_in "$(yq '.jobs[].steps[].run // ""' "$f")" -qE 'factory-update\.sh fetch( |$)'
}
wf_fetch_ok_41 "$WF_24"; assert_exit 0 "$?" "#41 AK1.1/AK2.1/AK4.1: Job fetch = Checkout, yq, fetch-isolated, Upload von fetch-out/update.bundle – kein weiterer Schritt"
mut_wf_41() { # <name> <yq-ausdruck>
  cp "$WF_24" "$T23/mut41-$1.yml"; yq -i "$2" "$T23/mut41-$1.yml"
  assert_true "$(cmp -s "$WF_24" "$T23/mut41-$1.yml"; [ $? -ne 0 ]; echo $?)" "#41 Mutation $1: der Mutant unterscheidet sich vom Workflow (Voraussetzung)"
  wf_fetch_ok_41 "$T23/mut41-$1.yml"; assert_exit 1 "$?" "#41 AK4.2 (Mutation): $1 → derselbe Prüfer ist rot"
}
mut_wf_41 release-code-ausserhalb '.jobs.fetch.steps[2].run = "bash scripts/factory-update.sh fetch \"$VERSION\" \"$BASE_SHA\" \"$RUNNER_TEMP/fetch-out/update.bundle\""'
mut_wf_41 schritt-nach-container '.jobs.fetch.steps += [{"run": "git -C \"$RUNNER_TEMP/fetch-out\" log"}]'
mut_wf_41 schritt-zwischen '.jobs.fetch.steps |= .[0:3] + [{"run": "bash \"$RUNNER_TEMP/fetch-out/x.sh\""}] + .[3:]'
mut_wf_41 upload-ganzes-verzeichnis '.jobs.fetch.steps[3].with.path = "${{ runner.temp }}/fetch-out"'
mut_wf_41 actions-variable-im-schritt '.jobs.fetch.steps[2].env.ACTIONS_RUNTIME_TOKEN = "x"'
mut_wf_41 job-container '.jobs.fetch.container = "debian:stable"'
mut_wf_41 fetch-direkt-in-publish '.jobs.publish.steps += [{"run": "bash scripts/factory-update.sh fetch v1 x y"}]'

# ── E34 f: Smoke-Job in factory-ci.yml ───────────────────────────────────────────────────────────────────────────────
ci_smoke_ok_41() { # <factory-ci.yml>
  [ "$(yq -o=json -I=0 '[.jobs.fetch-container-smoke.steps[] | (.uses // .run)]' "$1")" = \
    "$(jq -cn --arg r "$SMOKE_LINE_41" '["actions/checkout@v4", "sudo bash scripts/install-yq.sh", $r]')" ] || return 1
  [ "$(yq '.jobs.fetch-container-smoke.runs-on' "$1")" = ubuntu-latest ] && [ "$(yq '.jobs.fetch-container-smoke.steps[0].with.persist-credentials' "$1")" = false ]
}
ci_smoke_ok_41 "$CI_WF_41"; assert_exit 0 "$?" "#41 AK4.3: factory-ci.yml hat den Smoke-Job (Checkout, yq, fetch-smoke)"
cp "$CI_WF_41" "$T23/mut41-ci.yml"; yq -i 'del(.jobs.fetch-container-smoke)' "$T23/mut41-ci.yml"
ci_smoke_ok_41 "$T23/mut41-ci.yml"; assert_exit 1 "$?" "#41 AK4.3 (Mutation): ohne den Smoke-Job ist derselbe Prüfer rot"

# ── AK5: Doku-Guards ─────────────────────────────────────────────────────────────────────────────────────────────────
ops_ok_41() { # $1 = geglätteter Text von OPERATING.md
  local p
  for p in '`fetch-isolated`' 'unprivilegierten Container' 'braucht der Job `fetch` Docker' 'Restrisiko für Caches' 'Nachtrag 2026-11-20'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
}
adr_ok_41() { # $1 = geglätteter Text von ADR-063
  local p
  for p in 'Status: Accepted (2026-11-20, umgesetzt in #41)' '**Berichtigt:** Das gilt für `FACTORY_SYNC_TOKEN`' 'E28 · Isolationsgrenze' 'Restrisiko (ehrlich, Q5)'; do
    grep -qF -- "$p" <<< "$1" || return 1
  done
  ! grep -qF -- 'Status: Proposed (wird mit der Umsetzung in #41 Accepted)' <<< "$1"
}
adr_41="$(tr '\n' ' ' < "$FACTORY_ROOT/docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md" | tr -s ' ')"
ops_41="$(tr '\n' ' ' < "$FACTORY_ROOT/docs/factory/OPERATING.md" | tr -s ' ')"
ops_ok_41 "$ops_41"; assert_exit 0 "$?" "#41 AK5.2: OPERATING.md §0.6 nennt Container, Docker-Voraussetzung und Restrisiko für Caches"
ops_ok_41 "$(strip_literal_37 "$ops_41" 'Restrisiko für Caches')"; assert_exit 1 "$?" "#41 AK5.2 (Mutation): ohne „Restrisiko für Caches“ ist derselbe Guard rot"
adr_ok_41 "$adr_41"; assert_exit 0 "$?" "#41 AK5.1: ADR-063 Nachtrag 2026-11-20 Accepted, E17 berichtigt, Restrisiko benannt"
adr_ok_41 "$(strip_literal_37 "$adr_41" '**Berichtigt:**')"; assert_exit 1 "$?" "#41 AK5.1 (Mutation): ohne die Berichtigung in E17 ist derselbe Guard rot"

factory_lock_template_unchanged
test_group_finish; exit $?
