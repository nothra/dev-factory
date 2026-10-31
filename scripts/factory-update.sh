#!/usr/bin/env bash
# factory-update.sh – pflegt den Update-PR eines Konsumenten-Repos auf die neueste Factory-Version
#
# Verwendung (in CI über .github/workflows/factory-update.yml, lokal nur für Tests):
#   FACTORY_SYNC_TOKEN=<pat> GITHUB_REPOSITORY=<owner>/<repo> bash scripts/factory-update.sh
#
# Ablauf (Factory-ADR-063, Nachtrag 2026-10-30 E11 – die Reihenfolge ist Teil der Entscheidung):
#   1. kein factory.lock (Factory-Repo selbst) → Hinweis, Exit 0, ohne Token und Netz; Lock ungültig → Exit 1
#   2. FACTORY_SYNC_TOKEN leer, abgelehnt oder ohne Schreibrecht → Exit 1, vor jedem weiteren Schritt
#   3. neueste veröffentlichte Version im Quell-Repo (kein Draft/Pre-Release, SemVer-Tag, Asset factory-release.json);
#      Release-Liste nicht lesbar → Exit 1; keine neuere als der Lock → Hinweis, Exit 0
#   4. offener Update-PR steht schon auf dieser Version, oder ein ohne Merge geschlossener PR trug sie → Hinweis, Exit 0
#   5. Branch chore/factory-update von origin/main neu aufbauen, factory-sync.sh <version>, ein Commit, Push mit Lease
#   6. offenen PR bearbeiten bzw. neuen anlegen (Label enhancement, kein Draft) – nie mergen, nie Auto-Merge
#
# Anmeldung: alle gh-Aufrufe laufen mit GH_TOKEN=$FACTORY_SYNC_TOKEN; der eingebaute Actions-Token wird nie gelesen
# (Pushes mit ihm lösten keine pull_request-Workflows aus, AK2.4). Der Push meldet sich über einen Credential-Helper an,
# der das Token zur Laufzeit aus der Umgebung ausgibt – es steht weder in argv noch in .git/config (E12). Git-Hooks
# laufen bei keinem ref-schreibenden git-Aufruf (Checkout, Fetch, Commit, Push).
#
# Projektwurzel: FACTORY_DIR (Tests/Override), sonst eine Ebene über scripts/. Fail-closed: jedes Werkzeug oder jede
# Antwort, die scheitert, beendet den Lauf mit Exit 1, bevor etwas gepusht wird.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

WORK=""
ORIG_REF=""  # Checkout vor dem Neuaufbau; wird am Ende wiederhergestellt, damit ein Folgelauf den Lock von dort liest

die() { printf '✗ factory-update: %s\n' "$1" >&2; exit 1; }
note() { printf 'ℹ factory-update: %s\n' "$1"; }

cleanup() {
  [ -z "$ORIG_REF" ] || git_nohooks checkout --quiet "$ORIG_REF" || echo "⚠ factory-update: Rückkehr auf $ORIG_REF fehlgeschlagen" >&2
  [ -z "$WORK" ] || rm -rf "$WORK"
}

gh_token() { GH_TOKEN="$FACTORY_SYNC_TOKEN" gh "$@"; }
# Ohne Hooks: nach der Abholung rufen die installierten Hooks Skripte des ungeprüften Release auf, mit dem Token in der
# Umgebung – und ein rotes Gate im pre-push brächte genau den Push zu Fall, den F1 als Update-PR vorsieht.
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
  local hint="Token anlegen bzw. erneuern: docs/factory/OPERATING.md §0.6"
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

# ─── 5. Neuaufbau ────────────────────────────────────────────────────────────────────────────────────────────────────

rebuild_branch() {
  [ -z "$(git status --porcelain)" ] || die "Arbeitsbaum nicht sauber – kein Neuaufbau (fail-closed)"
  ORIG_REF="$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)" || die "aktueller Checkout nicht ermittelbar"
  git_nohooks checkout --quiet -B "$UPDATE_BRANCH" "origin/$BASE_BRANCH" || die "Branch $UPDATE_BRANCH nicht von origin/$BASE_BRANCH aufbaubar"
  # Ohne Token: factory-sync.sh ersetzt sich beim Abholen selbst und startet in der neuen Fassung aus dem Release neu –
  # Code eines noch ungeprüften Tags darf das schreibberechtigte PAT nie sehen (E12; Push und gh laufen erst danach).
  env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN FACTORY_DIR="$ROOT" bash "$SYNC" "$TARGET_VERSION" || die "Abholung von $TARGET_VERSION gescheitert (Meldung oben) – nichts gepusht"
  git add -A && git_nohooks "${COMMIT_IDENTITY[@]}" commit --quiet -m "chore: factory auf $TARGET_VERSION heben" \
    || die "Commit fehlgeschlagen – nichts gepusht"
  git_with_token push --quiet --force-with-lease="refs/heads/$UPDATE_BRANCH:$BRANCH_SHA" origin "HEAD:refs/heads/$UPDATE_BRANCH" \
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

main() {
  cd "$ROOT" 2>/dev/null || die "Projektwurzel nicht erreichbar: $ROOT"
  if ! has_lock; then
    note "kein factory.lock – Repo bindet die Factory nicht per Lock ein (z. B. das Factory-Repo selbst), nichts zu tun"
    exit 0
  fi
  # shellcheck source=lib/factory-lock.sh
  source "$SELF_DIR/lib/factory-lock.sh" || die "scripts/lib/factory-lock.sh nicht ladbar (fail-closed)"
  read_lock_version
  unset GITHUB_TOKEN
  export GIT_TERMINAL_PROMPT=0
  command -v gh >/dev/null 2>&1 || die "gh nicht gefunden (fail-closed)"
  require_token
  local repo
  repo="$(fl_upstream_repo)" || die "Quell-Repo nicht ermittelbar (upstream.repo, fail-closed)"
  WORK="$(mktemp -d)" || die "mktemp fehlgeschlagen"
  trap cleanup EXIT
  find_newer_releases "$repo"
  if [ -z "$TARGET_VERSION" ]; then
    note "keine neuere Version als $LOCK_VERSION in $repo veröffentlicht – nichts zu tun"
    exit 0
  fi
  fetch_origin
  check_existing_pr
  rebuild_branch
  publish_pr
}

# Auf einer Zeile: factory-sync.sh ersetzt diese Datei im Lauf, und bash liest Skripte stückweise – ohne das exit
# hier läse es nach main am alten Byte-Offset in der neuen Fassung weiter.
main "$@"; exit $?
