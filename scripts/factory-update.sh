#!/usr/bin/env bash
# factory-update.sh – pflegt den Update-PR eines Konsumenten-Repos auf die neueste Factory-Version
#
# Verwendung (in CI über .github/workflows/factory-update.yml, lokal nur für Tests):
#   factory-update.sh guard                              Job „guard“ (ohne Environment): kein Lock → No-op; Repository-Secret → rot
#   factory-update.sh preflight                          Job „preflight“ (Token): Prüfungen, Ausgabe version/base_sha
#   factory-update.sh fetch-isolated <version> <base> <out_dir>
#                                                        Job „fetch“ (ohne Token): Image bauen, Release-Code im Container,
#                                                        Ergebnis = <out_dir>/update.bundle (Factory-ADR-063 E28–E33)
#   factory-update.sh fetch   <version> <base> <bundle>  Einstieg im Container (und der Kurzform); in CI direkt verweigert
#   factory-update.sh fetch-smoke <out_dir>              Smoke-Job in factory-ci.yml: dasselbe Image, harmloses Kommando + Netz-Probe
#   (fetch-isolated und fetch-smoke schotten das Netz des Containers per sudo -n iptables ab, E35–E39 – sonst Exit 1;
#    höchstens ein Lauf je Docker-Host, per flock, E41)
#   factory-update.sh publish <version> <base> <bundle>  Job „publish“ (Token): Bundle prüfen, pushen, PR pflegen
#   FACTORY_SYNC_TOKEN=<pat> GITHUB_REPOSITORY=<owner>/<repo> bash scripts/factory-update.sh
#                                                        Kurzform (nur Tests/lokal, in CI verweigert): alle Schritte hintereinander
#
# Ablauf (Factory-ADR-063, Nachtrag 2026-10-30 E11, ergänzt um Nachtrag 2026-10-31 E17–E22):
#   1. kein factory.lock (Factory-Repo selbst) → Hinweis, Exit 0, ohne Token und Netz; Lock ungültig → Exit 1
#   2. FACTORY_SYNC_TOKEN leer, abgelehnt oder ohne Schreibrecht → Exit 1, vor jedem weiteren Schritt
#   3. neueste veröffentlichte Version im Quell-Repo (kein Draft/Pre-Release, SemVer-Tag, Asset factory-release.json);
#      Release-Liste nicht lesbar → Exit 1; keine neuere als der Lock → Hinweis, Exit 0
#   4. offener Update-PR steht schon auf dieser Version, oder ein ohne Merge geschlossener PR trug sie → Hinweis, Exit 0
#   5. Abholung (`fetch`): factory-sync.sh <version> in einem Checkout von origin/main OHNE Token, ein Commit, Übergabe
#      ausschließlich als `git bundle`; Prüfung (`publish`): ein Commit auf origin/main, keine Symlinks/Submodule, nur erwartete
#      Pfade, factory.lock == frisch geholtes Manifest, Hashes der Manifest-Dateien; der Commit wird mit dem geprüften Baum
#      NEU erzeugt (commit-tree) und per SHA gepusht (Lease)
#   6. offenen PR bearbeiten bzw. neuen anlegen (Label enhancement, kein Draft) – nie mergen, nie Auto-Merge
#
# Token-Grenze (E17, E28): Code des noch ungeprüften Release läuft nur in `fetch` – ohne Token in Job, Umgebung und Runner, und
# dort nur in einem unprivilegierten Container (kein Weg zum Runtime-Token des Laufs, weder über Runner-Dateien noch über sudo);
# `preflight`/`publish` tragen das Token und führen nur Code aus `main` aus. In der Kurzform läuft `fetch` als eigener Prozess
# ohne Token-Variablen in einem frischen Klon. Anmeldung: alle gh-Aufrufe mit GH_TOKEN=$FACTORY_SYNC_TOKEN; der eingebaute
# Actions-Token wird nie gelesen (Pushes mit ihm lösten keine pull_request-Workflows aus, AK2.4). Der Push meldet sich über einen
# Credential-Helper an, der das Token zur Laufzeit aus der Umgebung ausgibt – es steht weder in argv noch in .git/config (E12).
# Git-Hooks laufen bei keinem ref-schreibenden git-Aufruf.
#
# Projektwurzel: FACTORY_DIR (Tests/Override), sonst eine Ebene über scripts/. Fail-closed: jedes Werkzeug oder jede
# Antwort, die scheitert, beendet den Lauf mit Exit 1, bevor etwas gepusht wird.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="${FACTORY_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
FACTORY_DIR="$ROOT"
SYNC="$SELF_DIR/factory-sync.sh"

UPDATE_BRANCH="chore/factory-update"
BASE_BRANCH="main"
LOCK_FILE="factory.lock"
VERSION_MARK_PREFIX="<!-- factory-update-version: "
COMMIT_IDENTITY=(-c user.name=factory-update -c user.email=factory-update@localhost)
# Gibt auf `get` Benutzer und Token aus der Umgebung aus; der Wert selbst steht nirgends.
CREDENTIAL_HELPER='!f() { [ "$1" = get ] || return 0; printf "username=x-access-token\npassword=%s\n" "$FACTORY_SYNC_TOKEN"; }; f'

# Pfade, die der Neuaufbau außer den Manifest-Dateien ändern darf: die von factory-sync.sh zusammengesetzten Ziele.
COMPOSED_TARGETS=(.claude/settings.json .gitignore)
BUNDLE_MODE_FORBIDDEN_RE='^(120000|160000)$'  # Symlink, Submodul

# Container des Jobs fetch (Factory-ADR-063 E28–E33). Basis per Digest gepinnt (Trust-on-First-Use wie YQ_SHA256 in
# install-yq.sh; ein Bump ändert diese Zeile, Digest per `docker buildx imagetools inspect debian:<stable>-slim`).
FETCH_BASE_IMAGE="debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2"
FETCH_IMAGE="factory-update-fetch:local"
FETCH_BUNDLE="update.bundle"
# Im Container: Arbeitskopie des nur lesend eingebundenen Checkouts, darin die Abholung. Version und Basis als Positionsargumente.
FETCH_CONTAINER_SCRIPT='cp -a /src/. /tmp/work && bash /tmp/work/scripts/factory-update.sh fetch "$1" "$2" /out/update.bundle'
# Harmloser Nachweis für den Smoke-Job (E34 f): Werkzeuge da, kein root, keine Runner-Umgebung, Checkout nur lesend, /out beschreibbar.
# Dazu die Netz-Probe (E40 c, $1 = Gateway, $2 = Port des Host-Lauschers): Gateway, IMDS und WireServer abgewiesen, DNS und HTTPS
# zu GitHub erreichbar, keine IPv6-Adresse außer lo. Abgewiesen heißt curl-Exit 7: REJECT antwortet mit ICMP port-unreachable;
# ein Timeout (28) belegt die Regel nicht. Grenze: curl meldet jeden gescheiterten connect() mit 7, auch eine fehlende Route –
# die Probe setzt einen Runner voraus, auf dem die Ziele ohne Regel antworten (GitHub-gehostet: ja, ADR-063 E40 c).
# Fehlt /proc/net/if_inet6 (kein IPv6), ist das erfüllt;
# grep kann dort nicht zwischen „Datei fehlt“ und „nicht lesbar“ unterscheiden – beides gilt als ohne IPv6.
FETCH_SMOKE_SCRIPT='blocked() { curl -s -o /dev/null --max-time 5 "$1"; rc=$?; [ "$rc" = 7 ] || { echo "✗ Netz-Sperre nicht belegt: $1 → curl-Exit $rc (erwartet 7 = abgewiesen)" >&2; return 1; }; }
git --version && jq --version && yq --version && curl --version && sha256sum --version \
  && [ "$(id -u)" != 0 ] && ! env | grep -qE "^(ACTIONS|GITHUB|RUNNER)_" && ! touch /src/.smoke 2>/dev/null \
  && blocked "http://$1:$2/" && blocked http://169.254.169.254/ && blocked http://168.63.129.16/ \
  && curl -sS -o /dev/null --retry 3 --retry-all-errors --max-time 20 https://github.com \
  && ! grep -vE "[[:space:]]lo\$" /proc/net/if_inet6 2>/dev/null \
  && echo ok > /out/smoke.txt'

# Netz des Containers (E35–E39): eigenes Docker-Netz mit fester Bridge; alle Regeln hängen an dieser Schnittstelle und lassen
# andere Container und Dienste des Runners unberührt.
FETCH_NETWORK="factory-fetch"
FETCH_BRIDGE="factory-fetch0"
# Regeln (E36) – einzige Stelle, je Eintrag Kette und Regel, in Zielreihenfolge: so stehen sie nach dem Einfügen am Kettenanfang.
# INPUT sperrt den Host ganz (Verkehr zum Host läuft nicht durch FORWARD/DOCKER-USER); DNS am WireServer vor dessen Sperre.
FETCH_NET_RULES=(
  "INPUT -i $FETCH_BRIDGE -j REJECT"
  "DOCKER-USER -i $FETCH_BRIDGE -d 168.63.129.16/32 -p udp --dport 53 -j RETURN"
  "DOCKER-USER -i $FETCH_BRIDGE -d 168.63.129.16/32 -p tcp --dport 53 -j RETURN"
  "DOCKER-USER -i $FETCH_BRIDGE -d 168.63.129.16/32 -j REJECT"
  "DOCKER-USER -i $FETCH_BRIDGE -d 169.254.0.0/16 -j REJECT"
)
FETCH_NET_HINT="fetch braucht passwortloses sudo und iptables auf dem Runner (GitHub-gehostet vorhanden) – kein Container ohne Netz-Sperre"
# Host-weiter Lock (E41): Netz, Bridge und Regeln tragen feste Namen – zwei Läufe an einem Docker-Daemon entfernten sich sonst
# gegenseitig die Sperre. Gehalten auf fd 9 bis zum Prozessende, also über Einrichten → Container → Abräumen (EXIT-Trap).
# FACTORY_FETCH_LOCK lenkt die Datei um (gedacht für Tests). Er wirkt überall, auch in CI: Instanzen mit verschiedenen Werten
# serialisieren nicht mehr gegeneinander – nie nur für einen Teil der Runner eines Hosts setzen.
FETCH_LOCK_FILE="${FACTORY_FETCH_LOCK:-/tmp/factory-fetch.lock}"
FETCH_LOCK_WAIT_SECONDS=900
# Smoke-Probe (E40 c): Port des Host-Lauschers auf dem Gateway; Gegenprobe vom Host bis zu N Versuche im Abstand von S Sekunden
FETCH_SMOKE_PORT=18066
SMOKE_LISTENER_TRIES=10
SMOKE_LISTENER_PAUSE=0.5

WORK=""
FETCH_NET_ACTIVE=""
SMOKE_LISTENER_PID=""
SMOKE_GATEWAY=""

die() { printf '✗ factory-update: %s\n' "$1" >&2; exit 1; }
note() { printf 'ℹ factory-update: %s\n' "$1"; }
warn() { printf '⚠ factory-update: %s\n' "$1" >&2; }

# Läuft per trap auf EXIT, nach Erfolg und nach Fehler: erst der Lauscher, dann Netz-Sperre und Netz (E38), zuletzt WORK.
cleanup() {
  [ -z "$SMOKE_LISTENER_PID" ] || kill "$SMOKE_LISTENER_PID" 2>/dev/null
  [ -z "$FETCH_NET_ACTIVE" ] || teardown_fetch_network
  [ -z "$WORK" ] || rm -rf "$WORK"
}

# Ausgabe für nachfolgende Jobs (GitHub Actions); ohne $GITHUB_OUTPUT (Tests, lokal) nur auf stdout.
emit_output() {
  printf '%s=%s\n' "$1" "$2"
  [ -z "${GITHUB_OUTPUT:-}" ] || printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

gh_token() { GH_TOKEN="$FACTORY_SYNC_TOKEN" gh "$@"; }
# Ohne Hooks: die installierten Hooks rufen Skripte des Konsumenten auf (mit dem Token in der Umgebung), und ein rotes
# Gate im pre-push brächte genau den Push zu Fall, den F1 als Update-PR vorsieht.
git_nohooks() { git -c core.hooksPath=/dev/null "$@"; }
git_with_token() { git_nohooks -c credential.helper= -c "credential.helper=$CREDENTIAL_HELPER" "$@"; }

has_lock() { [ -e "$ROOT/$LOCK_FILE" ] || [ -L "$ROOT/$LOCK_FILE" ]; }

# ─── 1. Lock ─────────────────────────────────────────────────────────────────────────────────────────────────────────

read_lock_version() {
  fl_validate_manifest "$ROOT/$LOCK_FILE" >&2 || die "$LOCK_FILE ungültig – kein Update (fail-closed, kein Rückfall auf den No-op)"
  LOCK_VERSION="$(jq -r .version "$ROOT/$LOCK_FILE")" || die "$LOCK_FILE nicht lesbar"
}

# ─── 2. Token ────────────────────────────────────────────────────────────────────────────────────────────────────────

require_token() {
  local hint="Token anlegen bzw. erneuern: Secret im Environment factory-update (Lauf auf main), nicht als Repository-Secret – docs/factory/OPERATING.md §0.6"
  [ -n "${FACTORY_SYNC_TOKEN:-}" ] || die "FACTORY_SYNC_TOKEN fehlt oder ist leer. $hint"
  printf '%s' "${GITHUB_REPOSITORY:-}" | grep -qE "$FL_SLUG_RE" || die "GITHUB_REPOSITORY ist kein <owner>/<repo>-Slug: '${GITHUB_REPOSITORY:-}'"
  local can_push
  can_push="$(gh_token api "repos/$GITHUB_REPOSITORY" --jq .permissions.push 2>&1)" \
    || die "FACTORY_SYNC_TOKEN wird abgelehnt (abgelaufen oder ungültig): $can_push. $hint"
  [ "$can_push" = true ] || die "FACTORY_SYNC_TOKEN hat kein Schreibrecht auf $GITHUB_REPOSITORY. $hint"
}

# ─── 3. Neueste Version ──────────────────────────────────────────────────────────────────────────────────────────────

# jq: Kandidaten (veröffentlicht, SemVer-Tag, Manifest-Asset) mit numerischem Versionsschlüssel, aufsteigend sortiert.
CANDIDATES_JQ='
  add
  | map(select(.draft == false and .prerelease == false
               and ((.tag_name // "") | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
               and any(.assets[]?; .name == "factory-release.json")))
  | map(. + {key: (.tag_name | ltrimstr("v") | split(".") | map(tonumber))})
  | sort_by(.key)'

version_key() { printf '%s' "$1" | jq -R 'ltrimstr("v") | split(".") | map(tonumber)'; }

# Schreibt die Kandidaten über N nach $WORK/newer.json (aufsteigend) und setzt TARGET_VERSION (leer = keine neuere).
find_newer_releases() {
  local repo="$1"
  gh_token api --paginate "repos/$repo/releases" > "$WORK/releases.raw" 2> "$WORK/releases.err" \
    || die "Release-Liste von $repo nicht lesbar: $(cat "$WORK/releases.err") (fail-closed)"
  jq -e -s 'length > 0 and all(.[]; type == "array")' "$WORK/releases.raw" >/dev/null 2>&1 \
    || die "Release-Liste von $repo ist keine gültige Antwort (kein JSON-Array, fail-closed)"
  jq -s --argjson n "$(version_key "$LOCK_VERSION")" "$CANDIDATES_JQ | map(select(.key > \$n))" "$WORK/releases.raw" > "$WORK/newer.json" \
    || die "Release-Liste von $repo nicht auswertbar (fail-closed)"
  TARGET_VERSION="$(jq -r 'last | .tag_name // empty' "$WORK/newer.json")"
}

# ─── 4. Stand von Branch und PR ──────────────────────────────────────────────────────────────────────────────────────

# PRs des Update-Branches aus diesem Repo (Fork-PRs mit gleichem Branch-Namen zählen nie).
own_prs() { # $1 = open|closed
  gh_token pr list --head "$UPDATE_BRANCH" --state "$1" --limit 100 --json number,url,body,mergedAt,isCrossRepository \
    | jq -e '[.[] | select(.isCrossRepository == false)]'
}

fetch_origin() {
  git_with_token fetch --prune --quiet origin || die "Fetch von origin fehlgeschlagen"
  BRANCH_SHA="$(git rev-parse -q --verify "refs/remotes/origin/$UPDATE_BRANCH" || true)"
}

branch_version() {
  [ -n "$BRANCH_SHA" ] || return 0
  git show "$BRANCH_SHA:$LOCK_FILE" 2>/dev/null | jq -r '.version // empty' 2>/dev/null
}

# Setzt OPEN_PR (Nummer oder leer); Exit 0, wenn für TARGET_VERSION nichts zu tun ist.
check_existing_pr() {
  local open closed rejected
  open="$(own_prs open)" || die "offene PRs nicht lesbar (fail-closed)"
  OPEN_PR="$(jq -r '.[0].number // empty' <<< "$open")"
  if [ -n "$OPEN_PR" ]; then
    if [ "$(branch_version)" = "$TARGET_VERSION" ]; then
      note "Update-PR $(jq -r '.[0].url' <<< "$open") steht schon auf $TARGET_VERSION – nichts zu tun"
      exit 0
    fi
    return 0
  fi
  closed="$(own_prs closed)" || die "geschlossene PRs nicht lesbar (fail-closed)"
  # Nur der Kopf des Bodys (vor der ersten Release-Überschrift aus write_body) zählt – zitierte Notes sperren nichts
  rejected="$(jq -r --arg m "$VERSION_MARK_PREFIX$TARGET_VERSION -->" \
    '[.[] | select(.mergedAt == null) | select((.body // "") | split("\n## ")[0] | contains($m))] | .[0].url // empty' <<< "$closed")"
  if [ -n "$rejected" ]; then
    note "$TARGET_VERSION wurde ohne Merge abgelehnt ($rejected) – erst eine neuere Version wird wieder angeboten"
    exit 0
  fi
}

# ─── 5. Abholung (ohne Token) und Prüfung (mit Token, ohne Release-Code) ──────────────────────────────────────────────

require_clean_tree() { [ -z "$(git -C "$1" status --porcelain)" ] || die "Arbeitsbaum nicht sauber – kein Neuaufbau (fail-closed)"; }

# fetch <version> <base_sha> <bundle>: hier – und nur hier – läuft Release-Code (factory-sync.sh ersetzt sich beim Abholen
# selbst und startet in der neuen Fassung aus dem Release neu). Der Aufrufer sorgt dafür, dass kein Token in der Umgebung steht.
# Ergebnis ausschließlich als Bundle eines Commits auf <base_sha>.
fetch_release() {
  local version="$1" base="$2" bundle="$3"
  require_clean_tree "$ROOT"
  git_nohooks checkout --quiet --detach "$base" || die "Basis $base nicht auscheckbar (fail-closed)"
  FACTORY_DIR="$ROOT" bash "$SYNC" "$version" || die "Abholung von $version gescheitert (Meldung oben) – nichts gepusht"
  git add -A && git_nohooks "${COMMIT_IDENTITY[@]}" commit --quiet -m "chore: factory auf $version heben" \
    || die "Commit fehlgeschlagen – nichts gepusht"
  git_nohooks bundle create --quiet "$bundle" "$base..HEAD" || die "Übergabe-Bundle nicht erzeugbar – nichts gepusht"
}

# ─── 5a. Container für den Release-Code (E28–E33) ─────────────────────────────────────────────────────────────────────

require_docker() {
  docker info >/dev/null 2>&1 \
    || die "fetch braucht Docker auf dem Runner (GitHub-gehostet vorhanden) – kein Rückfall auf eine Ausführung ohne Container"
}

fetch_dockerfile() {
  printf 'FROM %s\n' "$FETCH_BASE_IMAGE"
  printf '%s\n' 'RUN apt-get update && apt-get install -y --no-install-recommends git jq curl ca-certificates && rm -rf /var/lib/apt/lists/*'
}

# Vor jedem Release-Code und nur aus Code von main: Dockerfile per stdin, kein Build-Kontext.
build_fetch_image() {
  fetch_dockerfile | docker build -t "$FETCH_IMAGE" - >&2 \
    || die "Image für fetch nicht baubar (Basis $FETCH_BASE_IMAGE nicht ladbar, Digest falsch oder apt gescheitert) – nichts abgeholt"
}

# Legt das Ausgabeverzeichnis neu an (existiert es schon → Exit 1); setzt OUT_DIR (absolut, für den Mount).
make_out_dir() {
  [ -n "${1:-}" ] || die "Ausgabeverzeichnis fehlt"
  mkdir -- "$1" 2>/dev/null || die "Ausgabeverzeichnis $1 existiert schon oder ist nicht anlegbar (fail-closed)"
  OUT_DIR="$(cd "$1" && pwd)" || die "Ausgabeverzeichnis $1 nicht erreichbar"
}

# Die Optionen von docker run (E31) – einzige Stelle, fetch-isolated und fetch-smoke starten beide hierüber. Keine Sonderrechte,
# keine Umgebung außer HOME, genau drei Mounts: Checkout und yq nur lesend, dazu das Ausgabeverzeichnis. Netz: nur das eigene
# (E35), ohne IPv6 (E37).
run_in_fetch_container() { # <out_dir> <kommando…>
  local out="$1" yq_bin; shift
  yq_bin="$(command -v yq)" || die "yq nicht gefunden (scripts/install-yq.sh, fail-closed)"
  docker run --rm --network "$FETCH_NETWORK" --sysctl net.ipv6.conf.all.disable_ipv6=1 --cap-drop ALL --security-opt no-new-privileges --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$ROOT:/src:ro" -v "$out:/out" -v "$yq_bin:/usr/local/bin/yq:ro" "$FETCH_IMAGE" "$@"
}

# ─── 5b. Netz-Sperre des Containers (E35–E39) ─────────────────────────────────────────────────────────────────────────

# -n: ohne passwortloses sudo scheitert der Aufruf, statt auf ein Passwort zu warten.
host_iptables() { sudo -n iptables "$@"; }
# fetch_rule <-I|-C|-D> <eintrag aus FETCH_NET_RULES>
fetch_rule() { local op="$1" args; read -ra args <<< "$2"; host_iptables "$op" "${args[@]}"; }

# E41: wartet begrenzt auf den host-weiten Lock. Ohne Lock (anderer Lauf, flock fehlt, Datei nicht öffenbar) → Exit 1, bevor
# Netz oder Regeln angefasst werden – die gehören dann womöglich dem anderen Lauf.
acquire_fetch_lock() {
  exec 9>>"$FETCH_LOCK_FILE" && flock -w "$FETCH_LOCK_WAIT_SECONDS" 9 \
    || die "host-weiter Lock $FETCH_LOCK_FILE nicht erhalten: ein anderer fetch-Lauf auf diesem Docker-Host hält ihn seit über $FETCH_LOCK_WAIT_SECONDS s, oder flock fehlt bzw. die Datei ist nicht öffenbar – Netz und Regeln bleiben unberührt (fail-closed)"
}

# Entfernt jede Regel aus FETCH_NET_RULES, solange -C sie findet (auch mehrfach vorhandene Reste); Exit 1, wenn eine bleibt.
remove_fetch_rules() {
  local rule rc=0
  for rule in "${FETCH_NET_RULES[@]}"; do
    while fetch_rule -C "$rule" 2>/dev/null; do
      fetch_rule -D "$rule" 2>/dev/null || { rc=1; break; }
    done
  done
  return "$rc"
}

remove_fetch_network() {
  docker network inspect "$FETCH_NETWORK" >/dev/null 2>&1 || return 0
  docker network rm "$FETCH_NETWORK" >/dev/null
}

# Vor Image und Container (E39, E41): Lock, Reste abräumen, Netz anlegen, Regeln in umgekehrter Folge an den Kettenanfang
# einfügen (danach stehen sie in der Folge von FETCH_NET_RULES), jede per -C prüfen. Jeder Fehler → Exit 1, kein Rückfall aufs
# Standard-Netz. FETCH_NET_ACTIVE (Abräumen im EXIT-Trap) erst mit dem Lock.
setup_fetch_network() {
  local i rule
  acquire_fetch_lock
  FETCH_NET_ACTIVE=1
  remove_fetch_rules; remove_fetch_network
  docker network create --driver bridge -o "com.docker.network.bridge.name=$FETCH_BRIDGE" "$FETCH_NETWORK" >/dev/null \
    || die "Docker-Netz $FETCH_NETWORK nicht anlegbar. $FETCH_NET_HINT"
  for ((i = ${#FETCH_NET_RULES[@]} - 1; i >= 0; i--)); do
    fetch_rule -I "${FETCH_NET_RULES[i]}" || die "Regel nicht setzbar: ${FETCH_NET_RULES[i]}. $FETCH_NET_HINT"
  done
  for rule in "${FETCH_NET_RULES[@]}"; do
    fetch_rule -C "$rule" 2>/dev/null || die "Regel nach dem Setzen nicht vorhanden: $rule. $FETCH_NET_HINT"
  done
}

# Nach dem Container (E38): Fehler sind nur eine Warnung – der Container ist dann schon beendet (--rm).
teardown_fetch_network() {
  remove_fetch_rules || warn "Netz-Sperre nicht abgeräumt (iptables -D gescheitert) – Regeln an $FETCH_BRIDGE bleiben stehen"
  remove_fetch_network || warn "Docker-Netz $FETCH_NETWORK nicht abgeräumt"
}

# Smoke-Probe (E40 c): Lauscher auf dem Gateway von FETCH_NETWORK; die Gegenprobe vom Host belegt, dass er läuft – sonst sagte
# „im Container abgewiesen" nichts. Setzt SMOKE_GATEWAY. Der Lauscher erbt den Lock (fd 9) nicht.
start_gateway_listener() {
  local tries="$SMOKE_LISTENER_TRIES"
  command -v python3 >/dev/null 2>&1 || die "python3 fehlt – Smoke-Probe der Netz-Sperre nicht möglich"
  SMOKE_GATEWAY="$(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "$FETCH_NETWORK" 2>/dev/null)"
  [[ "$SMOKE_GATEWAY" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "Gateway von $FETCH_NETWORK nicht ermittelbar – Smoke-Probe nicht möglich"
  mkdir "$WORK/listener" || die "Verzeichnis für den Lauscher nicht anlegbar"
  python3 -m http.server --bind "$SMOKE_GATEWAY" --directory "$WORK/listener" "$FETCH_SMOKE_PORT" >/dev/null 2>&1 9>&- &
  SMOKE_LISTENER_PID=$!
  while :; do
    curl -s -o /dev/null --max-time 2 "http://$SMOKE_GATEWAY:$FETCH_SMOKE_PORT/" && return 0
    tries=$((tries - 1)); [ "$tries" -gt 0 ] || break
    sleep "$SMOKE_LISTENER_PAUSE"
  done
  die "Gegenprobe gescheitert: der Host erreicht den Lauscher auf $SMOKE_GATEWAY:$FETCH_SMOKE_PORT nicht – Smoke-Probe ohne Aussage"
}

# Rückweg (E32): genau ein Eintrag, die reguläre Datei update.bundle – kein Symlink, kein Verzeichnis. Der Host liest sie nicht.
require_single_bundle() {
  local entries
  entries="$(ls -A -- "$1")"
  [ "$entries" = "$FETCH_BUNDLE" ] && [ -f "$1/$FETCH_BUNDLE" ] && [ ! -L "$1/$FETCH_BUNDLE" ] \
    || die "Ausgabe des Containers ist nicht genau die reguläre Datei $FETCH_BUNDLE – kein Artefakt (fail-closed)"
}

# Prüfliste des Übergabe-Commits (E18), alle fail-closed, in vier Schritten. Setzt QUARANTINE_SHA; $WORK/manifest.json ist das
# frisch geholte Manifest des Release.

# 1. Bundle laden: lesbar, genau ein Commit auf der erwarteten Basis (Quarantäne – nichts davon wird ausgeführt).
load_bundle() {
  local base="$1" bundle="$2"
  [ -f "$bundle" ] || die "Übergabe-Bundle fehlt: $bundle – nichts gepusht"
  git_nohooks bundle verify --quiet "$bundle" >/dev/null 2>&1 || die "Übergabe-Bundle unlesbar oder unvollständig – nichts gepusht"
  git_nohooks fetch --quiet --no-tags "$bundle" HEAD 2>/dev/null || die "Übergabe-Bundle nicht übernehmbar – nichts gepusht"
  QUARANTINE_SHA="$(git rev-parse -q --verify FETCH_HEAD^{commit})" || die "Übergabe-Bundle ohne Commit – nichts gepusht"
  [ "$(git rev-parse -q --verify "refs/remotes/origin/$BASE_BRANCH")" = "$base" ] \
    || die "origin/$BASE_BRANCH hat sich seit der Abholung bewegt – nichts gepusht, der nächste Lauf baut neu auf"
  [ "$(git rev-list --count "$base..$QUARANTINE_SHA")" = 1 ] && [ "$(git rev-parse "$QUARANTINE_SHA^")" = "$base" ] \
    || die "Übergabe ist nicht genau ein Commit auf origin/$BASE_BRANCH – nichts gepusht"
}

# 2. Manifest holen und prüfen: gültig, keine geschützten Stellen (wie factory-sync.sh).
verify_manifest() {
  local repo="$1" version="$2" findings rc
  fl_fetch_manifest "$repo" "$version" "$WORK/manifest.json" || die "Release-Manifest zu $version nicht abrufbar – nichts gepusht"
  fl_validate_manifest "$WORK/manifest.json" "$repo" "$version" || die "Release-Manifest zu $version ungültig – nichts gepusht"
  # Wie factory-sync.sh: ein Manifest, das Projektbesitz oder Anpassungsstellen liefert, ist abgelehnt – das Manifest gehört dem Release
  findings="$(fl_protected_findings "$WORK/manifest.json")"; rc=$?
  [ "$rc" -eq 0 ] || die "Anpassungsstellen nicht prüfbar (fail-closed) – nichts gepusht"
  if [ -n "$findings" ]; then
    printf '%s\n' "$findings" | sed 's/^/✗ /; s/\t/: liefert eine geschützte Stelle (/; s/$/)/' >&2
    die "Manifest von $version liefert geschützte Stellen (Projektbesitz) – nichts gepusht"
  fi
}

# 3. Geänderte Pfade: keine Symlinks/Submodule, nur Pfade aus altem Lock, neuem Manifest und zusammengesetzten Zielen.
verify_changed_paths() {
  local base="$1" meta path mode unexpected
  { jq -r '.files[].path' "$LOCK_FILE"; jq -r '.files[].path' "$WORK/manifest.json"; printf '%s\n' "$LOCK_FILE" "${COMPOSED_TARGETS[@]}"; } \
    | LC_ALL=C sort -u > "$WORK/allowed.txt"

  : > "$WORK/changed.txt"
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    mode="$(printf '%s' "$meta" | cut -d' ' -f2)"
    [[ ! "$mode" =~ $BUNDLE_MODE_FORBIDDEN_RE ]] || die "Übergabe enthält Symlink oder Submodul: $path – nichts gepusht"
    case "$path" in *$'\n'*) die "Übergabe enthält einen Pfad mit Zeilenumbruch – nichts gepusht" ;; esac
    printf '%s\n' "$path" >> "$WORK/changed.txt"
  done < <(git diff-tree -r --no-renames --raw -z "$base" "$QUARANTINE_SHA")
  unexpected="$(LC_ALL=C sort -u "$WORK/changed.txt" | LC_ALL=C comm -23 - "$WORK/allowed.txt")"
  if [ -n "$unexpected" ]; then
    printf '%s\n' "$unexpected" | sed 's/^/✗ unerwarteter Pfad: /' >&2
    die "Übergabe ändert Pfade außerhalb von Manifest, altem Lock und zusammengesetzten Dateien – nichts gepusht"
  fi
}

# 4. Inhalt: factory.lock == Manifest, jede Manifest-Datei hat den Manifest-Hash.
verify_hashes() {
  local version="$1" path
  git cat-file blob "$QUARANTINE_SHA:$LOCK_FILE" 2>/dev/null | cmp -s - "$WORK/manifest.json" \
    || die "$LOCK_FILE der Übergabe ist nicht das Manifest von $version – nichts gepusht"
  mkdir -p "$WORK/quarantine"
  jq -r '.files[].path' "$WORK/manifest.json" > "$WORK/manifest-paths.txt"
  while IFS= read -r path; do
    mkdir -p "$WORK/quarantine/$(dirname -- "$path")"
    git cat-file blob "$QUARANTINE_SHA:$path" > "$WORK/quarantine/$path" 2>/dev/null || die "Manifest-Datei fehlt in der Übergabe: $path – nichts gepusht"
  done < "$WORK/manifest-paths.txt"
  fl_hash_paths "$WORK/quarantine" < "$WORK/manifest-paths.txt" > "$WORK/quarantine.tsv" || die "Hashen der Übergabe fehlgeschlagen – nichts gepusht"
  fl_manifest_tsv "$WORK/manifest.json" > "$WORK/want.tsv"
  [ -z "$(fl_diff_hashes "$WORK/want.tsv" "$WORK/quarantine.tsv")" ] || die "Dateien der Übergabe stimmen nicht mit dem Manifest überein – nichts gepusht"
}

verify_bundle() {
  local repo="$1" version="$2" base="$3" bundle="$4"
  load_bundle "$base" "$bundle"
  verify_manifest "$repo" "$version"
  verify_changed_paths "$base"
  verify_hashes "$version"
}

# Neuer Commit mit dem geprüften Baum (Autor, Nachricht, Signatur und Header des Release-Codes gelangen nicht in den Branch), per SHA gepusht.
push_verified() {
  local version="$1" base="$2" sha
  sha="$(git_nohooks -c commit.gpgSign=false "${COMMIT_IDENTITY[@]}" commit-tree "$QUARANTINE_SHA^{tree}" -p "$base" \
    -m "chore: factory auf $version heben")" || die "Commit nicht erzeugbar – nichts gepusht"
  git_with_token push --quiet --force-with-lease="refs/heads/$UPDATE_BRANCH:$BRANCH_SHA" origin "$sha:refs/heads/$UPDATE_BRANCH" \
    || die "Push auf $UPDATE_BRANCH abgelehnt (Branch inzwischen geändert oder Token ohne Recht) – PR unverändert"
}

# ─── 6. PR ───────────────────────────────────────────────────────────────────────────────────────────────────────────

write_body() {
  {
    printf 'Hebt die Factory von %s auf %s (`factory-sync.sh %s`).\n\n' "$LOCK_VERSION" "$TARGET_VERSION" "$TARGET_VERSION"
    printf '%s%s -->\n\n' "$VERSION_MARK_PREFIX" "$TARGET_VERSION"
    printf '> Der Branch `%s` gehört dem Workflow `factory-update.yml`: bei jeder neuen Factory-Version wird er von `%s` aus neu aufgebaut – eigene Commits auf diesem Branch entfallen dann.\n\n' \
      "$UPDATE_BRANCH" "$BASE_BRANCH"
    jq -r 'reverse | .[] | "## \(.tag_name)\n\n\(.body // "")\n"' "$WORK/newer.json"
  } > "$WORK/body.md"
}

publish_pr() {
  local title="chore: factory auf $TARGET_VERSION heben" url
  write_body
  if [ -n "$OPEN_PR" ]; then
    gh_token pr edit "$OPEN_PR" --title "$title" --body-file "$WORK/body.md" >/dev/null || die "Update-PR #$OPEN_PR nicht aktualisierbar"
    echo "✓ factory-update: Update-PR #$OPEN_PR auf $TARGET_VERSION neu aufgebaut"
  else
    url="$(gh_token pr create --base "$BASE_BRANCH" --head "$UPDATE_BRANCH" --title "$title" --body-file "$WORK/body.md" --label enhancement)" \
      || die "Update-PR nicht anlegbar (Branch ist gepusht)"
    echo "✓ factory-update: Update-PR auf $TARGET_VERSION angelegt: $url"
  fi
}

# ─── Aufruf ──────────────────────────────────────────────────────────────────────────────────────────────────────────

# Gemeinsamer Anfang der Modi mit Token: Lock, Werkzeuge, Token, Quell-Repo, Arbeitsverzeichnis. Setzt REPO.
prepare_with_token() {
  read_lock_version
  command -v gh >/dev/null 2>&1 || die "gh nicht gefunden (fail-closed)"
  require_token
  REPO="$(fl_upstream_repo)" || die "Quell-Repo nicht ermittelbar (upstream.repo, fail-closed)"
}

make_work_dir() { WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"; }

# Keine neuere Version als der Lock (TARGET_VERSION leer) → Hinweis, Exit 0.
exit_if_current() {
  [ -z "$TARGET_VERSION" ] || return 0
  note "keine neuere Version als $LOCK_VERSION in $REPO veröffentlicht – nichts zu tun"
  exit 0
}

# Version und Basis stammen aus Job-Ausgaben: Form prüfen, bevor sie an git/curl gehen.
require_handover_args() { # $1 version, $2 base, $3 bundle
  printf '%s' "$1" | grep -qE "$FL_VERSION_RE" || die "Version muss die Form vX.Y.Z haben: '$1'"
  printf '%s' "$2" | grep -qE '^[0-9a-f]{40}$' || die "Basis ist keine Commit-SHA: '$2'"
  [ -n "$3" ] || die "Pfad des Übergabe-Bundles fehlt"
}

mode_guard() {
  if ! has_lock; then
    note "kein factory.lock – Repo bindet die Factory nicht per Lock ein (z. B. das Factory-Repo selbst), nichts zu tun"
    emit_output lock false
    exit 0
  fi
  read_lock_version
  [ -z "${FACTORY_SYNC_TOKEN_REPO_SECRET:-}" ] \
    || die "FACTORY_SYNC_TOKEN liegt als Repository-Secret – dort sieht es jeder pull_request-Workflow. Als Secret des Environments factory-update hinterlegen und das Repository-Secret löschen: docs/factory/OPERATING.md §0.6"
  emit_output lock true
}

mode_preflight() {
  prepare_with_token
  make_work_dir
  find_newer_releases "$REPO"
  exit_if_current
  fetch_origin
  check_existing_pr
  emit_output version "$TARGET_VERSION"
  emit_output base_sha "$(git rev-parse "refs/remotes/origin/$BASE_BRANCH")"
}

mode_fetch() {
  # Docker reicht GITHUB_ACTIONS nicht in den Container: dort läuft der Modus, direkt auf dem Runner nicht (E29).
  [ "${GITHUB_ACTIONS:-}" != true ] || die "fetch führt Release-Code aus und läuft in CI nur im Container – fetch-isolated verwenden (Factory-ADR-063 E29)"
  require_handover_args "${1:-}" "${2:-}" "${3:-}"
  # Kein Token in der Umgebung: im Container nur HOME, die Kurzform ruft diesen Modus über `env -u` auf.
  fetch_release "$1" "$2" "$3"
}

# Job fetch (E29): läuft auf dem Runner, führt nur Code aus main aus; der Release-Code läuft im Container.
mode_fetch_isolated() {
  require_handover_args "${1:-}" "${2:-}" "${3:-}"
  require_docker
  # Vor dem Lock: endet der Lauf am Lock, bleibt das Verzeichnis leer liegen – ein Retry braucht einen neuen Pfad (CI: je Lauf frisch).
  make_out_dir "$3"
  setup_fetch_network
  build_fetch_image
  run_in_fetch_container "$OUT_DIR" bash -c "$FETCH_CONTAINER_SCRIPT" _ "$1" "$2" \
    || die "Abholung von $1 im Container gescheitert (Meldung oben) – kein Artefakt"
  require_single_bundle "$OUT_DIR"
  note "Übergabe liegt in $OUT_DIR/$FETCH_BUNDLE – geprüft wird sie in publish"
}

# Smoke-Job in factory-ci.yml (E34 f, E40 c): dasselbe Image, derselbe Aufruf, dieselbe Netz-Sperre, ein harmloses Kommando samt
# Netz-Probe statt der Abholung.
mode_fetch_smoke() {
  require_docker
  make_out_dir "${1:-}"
  make_work_dir
  setup_fetch_network
  build_fetch_image
  start_gateway_listener
  run_in_fetch_container "$OUT_DIR" bash -c "$FETCH_SMOKE_SCRIPT" _ "$SMOKE_GATEWAY" "$FETCH_SMOKE_PORT" \
    || die "Smoke im Container gescheitert (Meldung oben)"
  [ "$(cat "$OUT_DIR/smoke.txt" 2>/dev/null)" = ok ] || die "Smoke ohne Nachweis aus dem Container (/out/smoke.txt fehlt)"
  echo "✓ factory-update: Image und Aufruf des fetch-Containers tragen"
}

mode_publish() {
  require_handover_args "${1:-}" "${2:-}" "${3:-}"
  prepare_with_token
  make_work_dir
  find_newer_releases "$REPO"
  [ "$TARGET_VERSION" = "$1" ] || die "neueste Version ist inzwischen ${TARGET_VERSION:-keine}, nicht $1 – nichts gepusht, der nächste Lauf baut neu auf"
  fetch_origin
  check_existing_pr
  verify_bundle "$REPO" "$1" "$2" "$3"
  push_verified "$1" "$2"
  publish_pr
}

# Kurzform für Tests und lokale Läufe: Abholung als eigener Prozess ohne Token-Variablen in einem frischen Klon, Übergabe per Bundle.
mode_all() {
  [ "${GITHUB_ACTIONS:-}" != true ] || die "die Kurzform ohne Modus läuft nicht in CI (Token neben Release-Code) – guard|preflight|fetch|publish verwenden"
  prepare_with_token
  make_work_dir
  find_newer_releases "$REPO"
  exit_if_current
  fetch_origin
  check_existing_pr
  require_clean_tree "$ROOT"
  local base; base="$(git rev-parse "refs/remotes/origin/$BASE_BRANCH")" || die "origin/$BASE_BRANCH nicht ermittelbar"
  git_nohooks clone --quiet "$ROOT" "$WORK/clone" || die "frischer Klon nicht möglich (fail-closed)"
  env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN FACTORY_DIR="$WORK/clone" bash "$SELF" fetch "$TARGET_VERSION" "$base" "$WORK/update.bundle" \
    || die "Abholung von $TARGET_VERSION gescheitert (Meldung oben) – nichts gepusht"
  verify_bundle "$REPO" "$TARGET_VERSION" "$base" "$WORK/update.bundle"
  push_verified "$TARGET_VERSION" "$base"
  publish_pr
}

main() {
  local mode="${1:-all}"
  [ $# -eq 0 ] || shift
  cd "$ROOT" 2>/dev/null || die "Projektwurzel nicht erreichbar: $ROOT"
  # guard meldet den No-op selbst; die fetch-Modi brauchen keinen Lock (Abholung im Container, Smoke im Factory-Repo)
  if ! [[ "$mode" =~ ^(guard|fetch|fetch-isolated|fetch-smoke)$ ]] && ! has_lock; then
    note "kein factory.lock – Repo bindet die Factory nicht per Lock ein (z. B. das Factory-Repo selbst), nichts zu tun"
    exit 0
  fi
  # shellcheck source=lib/factory-lock.sh
  source "$SELF_DIR/lib/factory-lock.sh" || die "scripts/lib/factory-lock.sh nicht ladbar (fail-closed)"
  unset GITHUB_TOKEN
  export GIT_TERMINAL_PROMPT=0
  trap cleanup EXIT
  case "$mode" in
    guard) mode_guard ;;
    preflight) mode_preflight ;;
    fetch) mode_fetch "$@" ;;
    fetch-isolated) mode_fetch_isolated "$@" ;;
    fetch-smoke) mode_fetch_smoke "$@" ;;
    publish) mode_publish "$@" ;;
    all) mode_all ;;
    *) die "unbekannter Modus: $mode (guard|preflight|fetch-isolated|fetch|fetch-smoke|publish)" ;;
  esac
}

# Auf einer Zeile: factory-sync.sh ersetzt diese Datei im Lauf (Modus fetch), und bash liest Skripte stückweise – ohne das exit
# hier läse es nach main am alten Byte-Offset in der neuen Fassung weiter.
main "$@"; exit $?
