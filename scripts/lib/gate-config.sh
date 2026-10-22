#!/usr/bin/env bash
# gate-config.sh – Bibliothek der Git-Gates und Pipeline-Skripte (gesourct, nicht ausgeführt).
#
# Stellt bereit:
#   factory_cfg <yq-pfad>            Wert aus der geschichteten Config (factory.defaults.yml *
#                                    factory.config.yml); leer, wenn nicht gesetzt.
#   gate_command <schluessel> [required|optional]
#                                    Gate-Kommando: Env FACTORY_<SCHLUESSEL>_COMMAND gewinnt, sonst
#                                    commands.<schluessel> aus der Config. Fehlt ein "required"-Kommando
#                                    in beiden, nennt die Meldung den Schlüssel (kein stiller Default).
#   run_project_checks <verzeichnis> Projekt-Erweiterungspunkt: führt die ausführbaren Skripte des
#                                    Verzeichnisses lexikalisch aus (scripts/project/checks/*.d/).
#
# Erwartet vom Aufrufer FACTORY_DIR (Projektwurzel) und – für run_project_checks – die Farbvariablen
# RED/GREEN/YELLOW/NC. Fail-closed: kein pnpm-Fallback (ADR-063, #431).

# Effektive Config je Aufruf neu lesen (billig; die Gates laufen selten) – kein Cache, der veralten kann.
factory_cfg() {
  local path="$1" defaults="$FACTORY_DIR/factory.defaults.yml" override="$FACTORY_DIR/factory.config.yml"
  command -v yq >/dev/null 2>&1 || { echo "gate-config: yq nicht gefunden (Factory-Prerequisite)." >&2; return 1; }
  [ -f "$defaults" ] || return 0
  if [ -f "$override" ]; then
    yq eval-all '. as $i ireduce ({}; . * $i)' "$defaults" "$override" | yq eval ".$path // \"\"" -
  else
    yq eval ".$path // \"\"" "$defaults"
  fi
}

gate_command() {
  local key="$1" mode="${2:-required}" env_name value
  env_name="FACTORY_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')_COMMAND"
  # Einfaches `-`: ein BEWUSST leer gesetztes FACTORY_FORMAT_COMMAND="" ist der Opt-out des
  # Format-Gates und fällt nicht auf die Config zurück (#149). Für Pflicht-Kommandos zählt ein
  # leerer Wert wie ein fehlender und fällt auf die Config zurück.
  if [ "${!env_name+set}" = set ] && { [ -n "${!env_name}" ] || [ "$mode" = optional ]; }; then
    printf '%s' "${!env_name}"
    return 0
  fi
  value="$(factory_cfg "commands.$key")" || return 1
  if [ -z "$value" ] && [ "$mode" = required ]; then
    echo "commands.$key fehlt in factory.config.yml und $env_name ist nicht gesetzt – Gate-Kommando konfigurieren." >&2
    return 1
  fi
  printf '%s' "$value"
}

run_project_checks() {
  local dir="$1" f name rc=0 out
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in .*) continue ;; esac
    if [ ! -x "$f" ]; then
      echo -e "  ${RED}✗${NC} Projekt-Check $name ist nicht ausführbar – Ausführbar-Bit fehlt (chmod +x $f)"
      rc=1
      continue
    fi
    echo -e "  ${YELLOW}→${NC} Projekt-Check: $name"
    if out="$(FACTORY_DIR="$FACTORY_DIR" "$f" 2>&1)"; then
      echo -e "  ${GREEN}✓${NC} Projekt-Check $name bestanden"
    else
      echo -e "  ${RED}✗${NC} Projekt-Check $name fehlgeschlagen"
      printf '%s\n' "$out" | sed 's/^/     /'
      rc=1
    fi
  done
  return "$rc"
}
