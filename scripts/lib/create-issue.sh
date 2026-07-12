#!/usr/bin/env bash
# create-issue.sh – sourcebare Bibliothek: zentraler Seam für die Issue-Anlage (ADR-018).
#
# Diese Datei wird per `source`/`.` eingebunden und stellt EINE Funktion bereit:
#
#   create_issue <title> <body> <art-label> [aspekt-csv]
#     → legt ein GitHub-Issue an, setzt Art-Label + optionale Aspekt-Labels
#     → gibt die Issue-Nummer AUSSCHLIESSLICH auf stdout zurück (Exit 0)
#     → alle Warnungen/Diagnostik gehen auf stderr, damit `num=$(create_issue …)`
#       ausschließlich die reine Nummer erhält (stdout-Hygiene, ADR-018 §2)
#     → Exit ≠ 0 nur, wenn gar kein Issue entsteht (fail-closed auf die Anlage)
#
# Label-Degradation (fail-open aufs Label, ADR-018 §3) – das verpflichtende Art-Label
# wird nie durch ein fehlendes Aspekt-Label mitgerissen:
#
#   create mit  Art + allen Aspekt-Labels
#     └─ scheitert? → create nur mit Art-Label     (Warnung nennt die weggefallenen Aspekte)
#          └─ scheitert? → create ohne Label        (Warnung; die Anlage darf nicht scheitern)
#
# Robustheit gegen die Aufrufer-Shell-Optionen: Der Seam wird in Skripte mit
# `set -euo pipefail` gesourct. `set -u` (nounset) gilt auch innerhalb von `$(create_issue …)`,
# darum werden ALLE Array-Expansionen mit dem `+`-Guard abgesichert. `set -e` (errexit) wird
# innerhalb der Stufen bewusst über `if num=$(…)` neutralisiert, damit die Degradation auch
# bei einem bloßen (nicht via `$(…)` gefangenen) Aufruf durchläuft.
#
# Annahme (bewusst): `gh issue create` ist bzgl. der Anlage atomar – es löst Label-Namen VOR
# dem Anlegen zu IDs auf und scheitert bei fehlendem Label, BEVOR ein Issue entsteht. Nur
# unter dieser Annahme ist der Retry der nächsten Stufe kein Duplikat-Risiko.
#
# Repo-Bezug (ADR-018 §4): der Seam leitet den Slug NICHT selbst ab. Er nutzt
# `--repo "$FACTORY_REPO"` (sonst den vom Aufrufer gesetzten `$REPO`); ist beides leer,
# überlässt er `gh` die Auto-Erkennung aus dem Arbeitsverzeichnis.
#
# Die kanonische Label-Liste (genau ein Art-Label + null..n Aspekt-Labels) lebt allein in
# `docs/factory/guidelines/git-workflow.md` → „GitHub-Labels". Der Seam validiert bewusst
# nicht dagegen (keine Duplikation, kein Drift).

# _cri_is_reserved_label <label> – 0, wenn das Label dem Maschinen-Kontroll-Plane vorbehalten
# ist (`factory::`-Präfix, git-workflow.md → „factory::-Labels"). Eine Definition für Art- UND
# Aspekt-Guard, damit der reservierte Präfix sich nicht an zwei Stellen auseinanderentwickelt.
_cri_is_reserved_label() {
  case "$1" in
    factory::*) return 0 ;;
    *)          return 1 ;;
  esac
}

# _cri_try_create <gh-issue-create-args…> – versucht EINE Anlage. Druckt bei Erfolg die reine
# Issue-Nummer auf stdout und gibt 0 zurück; sonst 1 (keine Ausgabe). Bewusst robust gegen
# set -e/pipefail des Aufrufers (`|| …` statt Verlass auf errexit).
_cri_try_create() {
  local url num
  url=$(gh issue create "$@" 2>/dev/null) || url=""
  num=$(printf '%s' "$url" | grep -oE '[0-9]+$' | tail -n1) || num=""
  [ -n "$num" ] || return 1
  printf '%s\n' "$num"
}

# create_issue <title> <body> <art-label> [aspekt-csv]
create_issue() {
  local title="$1" body="$2" art_label="${3:-}" aspect_csv="${4:-}"

  command -v gh >/dev/null 2>&1 || {
    echo "create_issue: 'gh' nicht gefunden – Issue-Anlage nicht möglich." >&2
    return 1
  }
  # Sicherheits-Guard (defense-in-depth, Security-Review #82 H-1): der 'factory::'-Präfix ist
  # der Maschinen-Kontroll-Plane vorbehalten (Auto-Pipeline-Trigger/Status, git-workflow.md →
  # „factory::-Labels") und wird ausschließlich von der Pipeline via 'gh issue edit' gesetzt –
  # NIE über den allgemeinen Anlage-Seam. Käme ein solches Label hier durch (etwa aus einem
  # Skill, das es fälschlich aus untrusted Inhalt ableitet), könnte 'factory::run' einen
  # ungewollten Pipeline-Lauf auslösen → hart abweisen. Das ist eine schmale Denylist EINES
  # reservierten Präfix, NICHT die vom ADR-018 §3 abgelehnte Taxonomie-Allowlist.
  if _cri_is_reserved_label "$art_label"; then
    echo "create_issue: reserviertes Art-Label '$art_label' (factory::-Präfix) verworfen – diese Labels setzt nur die Pipeline." >&2
    art_label=""
  fi

  [ -n "$art_label" ] || \
    echo "create_issue: kein Art-Label übergeben – Issue entsteht ohne Art-Label (Konvention: genau ein Art-Label)." >&2

  # Repo-Slug aus der Umgebung (nicht selbst ableiten, ADR-018 §4).
  local repo="${FACTORY_REPO:-${REPO:-}}"
  local -a repo_args=()
  [ -n "$repo" ] && repo_args=(--repo "$repo")

  # Aspekt-CSV portabel in einzelne Labels zerlegen (leere Felder überspringen) –
  # ohne IFS-Spielereien, damit der Aufrufer-Kontext unberührt bleibt.
  local -a aspects=()
  local remaining="$aspect_csv" token
  while [ -n "$remaining" ]; do
    token="${remaining%%,*}"
    if [ -n "$token" ]; then
      # Reservierter Maschinen-Präfix (siehe Guard oben) – auch als Aspekt verwerfen.
      if _cri_is_reserved_label "$token"; then
        echo "create_issue: reserviertes Aspekt-Label '$token' (factory::-Präfix) verworfen – diese Labels setzt nur die Pipeline." >&2
      else
        aspects+=("$token")
      fi
    fi
    [ "$token" = "$remaining" ] && break
    remaining="${remaining#*,}"
  done

  # Label-Arg-Sätze gestuft aufbauen: voll (Art + Aspekte) und nur-Art.
  local -a labels_full=() labels_art=()
  local label
  if [ -n "$art_label" ]; then
    labels_full+=(--label "$art_label")
    labels_art+=(--label "$art_label")
  fi
  for label in ${aspects[@]+"${aspects[@]}"}; do
    labels_full+=(--label "$label")
  done

  # Gemeinsame Argumente; repo_args set-u-sicher expandieren (leer im gh-Auto-Pfad).
  local -a common_args=(${repo_args[@]+"${repo_args[@]}"} --title "$title" --body "$body")

  local num

  # Stufe 1: Art + alle Aspekt-Labels (nur, wenn überhaupt Labels vorhanden sind).
  if [ "${#labels_full[@]}" -gt 0 ]; then
    if num=$(_cri_try_create "${common_args[@]}" "${labels_full[@]}"); then
      printf '%s\n' "$num"; return 0
    fi
  fi

  # Stufe 2: nur Art-Label (Aspekte fallen weg) – nur sinnvoll, wenn es Aspekte UND ein
  # Art-Label gab (sonst identisch zu Stufe 1 bzw. Stufe 3). `gh` verrät nicht, welches Label
  # es ablehnte, daher neutrale Formulierung.
  if [ "${#aspects[@]}" -gt 0 ] && [ "${#labels_art[@]}" -gt 0 ]; then
    echo "create_issue: mind. ein Label wurde abgelehnt (im Repo nicht vorhanden?) – versuche nur mit Art-Label '${art_label}' (Aspekte '${aspects[*]}' fallen weg)." >&2
    if num=$(_cri_try_create "${common_args[@]}" "${labels_art[@]}"); then
      printf '%s\n' "$num"; return 0
    fi
  fi

  # Stufe 3: ohne jedes Label – die Anlage darf nicht an Label-Kosmetik scheitern.
  if [ "${#labels_full[@]}" -gt 0 ]; then
    echo "create_issue: Label(s) abgelehnt – lege Issue ohne Label an; bitte manuell klassifizieren." >&2
  fi
  if num=$(_cri_try_create "${common_args[@]}"); then
    printf '%s\n' "$num"; return 0
  fi

  echo "create_issue: Issue-Anlage fehlgeschlagen (keine Issue-Nummer erhalten)." >&2
  return 1
}
