#!/usr/bin/env bash
# factory-update.sh – pflegt den Update-PR eines Konsumenten-Repos auf die neueste Factory-Version
#
# Verwendung (in CI über .github/workflows/factory-update.yml, lokal nur für Tests):
#   factory-update.sh guard                              Job „guard“ (ohne Environment): kein Lock → No-op; Repository-Secret → rot
#   factory-update.sh preflight                          Job „preflight“ (Token): Prüfungen, Ausgabe version/base_sha
#   factory-update.sh fetch   <version> <base> <bundle>  Job „fetch“ (ohne Token): Release-Code läuft, Ergebnis = Bundle
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
# Token-Grenze (E17): Code des noch ungeprüften Release läuft nur in `fetch` – ohne Token in Job, Umgebung und Runner;
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

WORK=""

die() { printf '✗ factory-update: %s\n' "$1" >&2; exit 1; }
note() { printf 'ℹ factory-update: %s\n' "$1"; }

cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; }

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

# Prüfliste des Übergabe-Commits (E18), alle fail-closed. Setzt QUARANTINE_SHA; $WORK/manifest.json ist das frisch geholte Manifest.
verify_bundle() {
  local repo="$1" version="$2" base="$3" bundle="$4" meta path mode unexpected findings rc
  [ -f "$bundle" ] || die "Übergabe-Bundle fehlt: $bundle – nichts gepusht"
  git_nohooks bundle verify --quiet "$bundle" >/dev/null 2>&1 || die "Übergabe-Bundle unlesbar oder unvollständig – nichts gepusht"
  git_nohooks fetch --quiet --no-tags "$bundle" HEAD 2>/dev/null || die "Übergabe-Bundle nicht übernehmbar – nichts gepusht"
  QUARANTINE_SHA="$(git rev-parse -q --verify FETCH_HEAD^{commit})" || die "Übergabe-Bundle ohne Commit – nichts gepusht"
  [ "$(git rev-parse -q --verify "refs/remotes/origin/$BASE_BRANCH")" = "$base" ] \
    || die "origin/$BASE_BRANCH hat sich seit der Abholung bewegt – nichts gepusht, der nächste Lauf baut neu auf"
  [ "$(git rev-list --count "$base..$QUARANTINE_SHA")" = 1 ] && [ "$(git rev-parse "$QUARANTINE_SHA^")" = "$base" ] \
    || die "Übergabe ist nicht genau ein Commit auf origin/$BASE_BRANCH – nichts gepusht"

  fl_fetch_manifest "$repo" "$version" "$WORK/manifest.json" || die "Release-Manifest zu $version nicht abrufbar – nichts gepusht"
  fl_validate_manifest "$WORK/manifest.json" "$repo" "$version" || die "Release-Manifest zu $version ungültig – nichts gepusht"
  # Wie factory-sync.sh: ein Manifest, das Projektbesitz oder Anpassungsstellen liefert, ist abgelehnt – das Manifest gehört dem Release
  findings="$(fl_protected_findings "$WORK/manifest.json")"; rc=$?
  [ "$rc" -eq 0 ] || die "Anpassungsstellen nicht prüfbar (fail-closed) – nichts gepusht"
  if [ -n "$findings" ]; then
    printf '%s\n' "$findings" | sed 's/^/✗ /; s/\t/: liefert eine geschützte Stelle (/; s/$/)/' >&2
    die "Manifest von $version liefert geschützte Stellen (Projektbesitz) – nichts gepusht"
  fi
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
  WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"
  find_newer_releases "$REPO"
  if [ -z "$TARGET_VERSION" ]; then
    note "keine neuere Version als $LOCK_VERSION in $REPO veröffentlicht – nichts zu tun"
    exit 0
  fi
  fetch_origin
  check_existing_pr
  emit_output version "$TARGET_VERSION"
  emit_output base_sha "$(git rev-parse "refs/remotes/origin/$BASE_BRANCH")"
}

mode_fetch() {
  require_handover_args "${1:-}" "${2:-}" "${3:-}"
  # Hier steht kein Token (eigener Job); die Kurzform ruft diesen Modus über `env -u` auf.
  fetch_release "$1" "$2" "$3"
}

mode_publish() {
  require_handover_args "${1:-}" "${2:-}" "${3:-}"
  prepare_with_token
  WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"
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
  WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"
  find_newer_releases "$REPO"
  if [ -z "$TARGET_VERSION" ]; then
    note "keine neuere Version als $LOCK_VERSION in $REPO veröffentlicht – nichts zu tun"
    exit 0
  fi
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
  if [ "$mode" != guard ] && [ "$mode" != fetch ] && ! has_lock; then
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
    publish) mode_publish "$@" ;;
    all) mode_all ;;
    *) die "unbekannter Modus: $mode (guard|preflight|fetch|publish)" ;;
  esac
}

# Auf einer Zeile: factory-sync.sh ersetzt diese Datei im Lauf (Modus fetch), und bash liest Skripte stückweise – ohne das exit
# hier läse es nach main am alten Byte-Offset in der neuen Fassung weiter.
main "$@"; exit $?
