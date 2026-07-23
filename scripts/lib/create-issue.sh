#!/usr/bin/env bash
# create-issue.sh – sourcebare Bibliothek: zentraler Seam für die Issue-Anlage (ADR-018).
#
# Diese Datei wird per `source`/`.` eingebunden und stellt ZWEI öffentliche Funktionen bereit:
#
#   create_issue <title> <body> <art-label> [aspekt-csv]
#     → legt ein GitHub-Issue an, setzt Art-Label + optionale Aspekt-Labels
#     → gibt die Issue-Nummer AUSSCHLIESSLICH auf stdout zurück (Exit 0)
#     → alle Warnungen/Diagnostik gehen auf stderr, damit `num=$(create_issue …)`
#       ausschließlich die reine Nummer erhält (stdout-Hygiene, ADR-018 §2)
#     → Exit ≠ 0 nur, wenn gar kein Issue entsteht (fail-closed auf die Anlage)
#
#   create_issue_idempotent <title> <body> <art-label> [aspekt-csv]   (ADR-040, #207)
#     → opt-in-Idempotenz-Variante NUR für die autonomen Pipeline-Aufrufer (`/codify`,
#       `/review`, `/security-review`): findet ein OFFENES Issue mit exakt gleichem Titel →
#       dessen Nummer auf stdout (keine Anlage), sonst DELEGATION an das unveränderte
#       `create_issue`. Gleiche Signatur + gleicher stdout/stderr-Kontrakt. Verhindert
#       Duplikat-Issues, wenn ein gedächtnisloser Retry denselben Fund erneut anlegen würde.
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

# _cri_find_open_issue_by_title <title> – sucht ein OFFENES Issue mit EXAKT gleichem Titel.
# Kontrakt über den Exit-Code (der Aufrufer unterscheidet Treffer / kein Treffer / fail-open):
#   0 → Treffer: die (bei mehreren exakten Treffern niedrigste/älteste) Nummer auf stdout
#   1 → kein Treffer (Lookup lief, nichts passte exakt)
#   2 → Lookup nicht durchführbar (kein gh / gh-Fehler) → Aufrufer geht fail-open
#
# Die `--search "in:title …"`-Abfrage ist eine Volltext-/Teilstring-Suche und verengt nur die
# Kandidatenmenge (ADR-040 §3); der EXAKTE Abgleich erfolgt clientseitig in der Shell. Genutzt
# wird die in `gh` eingebettete JSON-Projektion (`-q '.[] | .number, .title'`, je Kandidat
# Nummer- und Titel-Zeile) – keine externe `jq`-Abhängigkeit.
_cri_find_open_issue_by_title() {
  local title="$1"
  command -v gh >/dev/null 2>&1 || return 2

  local repo="${FACTORY_REPO:-${REPO:-}}"
  local -a repo_args=()
  [ -n "$repo" ] && repo_args=(--repo "$repo")

  # --limit 100: die `in:title`-Suche verengt bereits stark; sollten >100 offene Issues denselben
  # Titel-Teilstring tragen, ist ein übersehener älterer Treffer unkritisch (fail-open-Richtung:
  # höchstens ein Duplikat, nie ein verlorener Fund) – der frisch angelegte Retry-Kandidat ist
  # ohnehin der neueste und damit stets in der Menge.
  local raw
  raw=$(gh issue list ${repo_args[@]+"${repo_args[@]}"} \
          --state open --search "in:title $title" --limit 100 \
          --json number,title -q '.[] | .number, .title' 2>/dev/null) || return 2

  # Kandidaten paarweise lesen (Nummer-Zeile, dann Titel-Zeile) und clientseitig EXAKT
  # vergleichen. Issue-Titel sind einzeilig, daher ist das Zeilenpaar eindeutig.
  local best="" num="" cand_title expect_num=1 line
  while IFS= read -r line; do
    if [ -n "$expect_num" ]; then
      num="$line"; expect_num=""
      continue
    fi
    cand_title="$line"; expect_num=1
    [ "$cand_title" = "$title" ] || continue
    case "$num" in
      ''|*[!0-9]*) : ;;                          # keine reine Nummer → überspringen
      *) if [ -z "$best" ] || [ "$num" -lt "$best" ]; then best="$num"; fi ;;
    esac
  done <<<"$raw"

  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# create_issue_idempotent <title> <body> <art-label> [aspekt-csv]
# Idempotente Variante des Seams (ADR-040) – nur für die autonomen Pipeline-Aufrufer
# (`/codify`, `/review`, `/security-review`), damit ein Retry ohne Gedächtnis denselben
# Out-of-Scope-Fund nicht doppelt als Issue anlegt. Findet ein OFFENES Issue mit exakt gleichem
# Titel → dessen Nummer auf stdout (Exit 0, keine Anlage); sonst DELEGIERT sie unverändert an
# `create_issue`. Der stdout/stderr-Kontrakt (nur die Nummer auf stdout) bleibt unverändert.
create_issue_idempotent() {
  local title="$1" body="$2" art_label="${3:-}" aspect_csv="${4:-}"

  local existing rc=0
  existing=$(_cri_find_open_issue_by_title "$title") || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "create_issue_idempotent: offenes Issue #$existing mit exakt gleichem Titel gefunden – lege kein Duplikat an." >&2
    printf '%s\n' "$existing"
    return 0
  fi
  if [ "$rc" -eq 2 ]; then
    # fail-open (ADR-040 §4, konsistent mit der Label-Degradation): ein seltenes Duplikat
    # ist akzeptabler als ein verlorener Fund. Die Anlage selbst bleibt fail-closed.
    echo "create_issue_idempotent: Duplikat-Prüfung nicht durchführbar (gh-Lookup fehlgeschlagen) – lege regulär an (fail-open)." >&2
  fi

  create_issue "$title" "$body" "$art_label" "$aspect_csv"
}
