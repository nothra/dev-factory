#!/usr/bin/env bash
# gate-config.sh – Bibliothek der Git-Gates und Pipeline-Skripte (gesourct, nicht ausgeführt).
#
# Stellt bereit:
#   factory_cfg <yq-pfad>            Wert aus der geschichteten Config (factory.defaults.yml *
#                                    factory.config.yml); leer, wenn nicht gesetzt.
#   factory_cfg_list <yq-pfad>       Liste aus derselben Config, ein String-Element je Zeile (andere Typen,
#                                    leere Elemente, Elemente mit Steuerzeichen und ein Wert, der keine
#                                    Liste ist, entfallen); leer, wenn nicht gesetzt.
#                                    Der Override ersetzt die Liste, er hängt nicht an.
#   factory_cfg_list_dropped <yq-pfad>
#                                    Zahl der Elemente, die factory_cfg_list verwirft (keine Liste = 1), damit
#                                    der Aufrufer sie melden kann statt sie still zu übergehen.
#   copy_entry_problem <eintrag>     Pfadregel für start_work.copy_files (Factory-ADR-063 E24): leere
#                                    Ausgabe = gültig, sonst der Ablehnungsgrund. Gate und start-work.sh
#                                    rufen dieselbe Funktion.
#   gate_command <schluessel> [required|optional]
#                                    Gate-Kommando: Env FACTORY_<SCHLUESSEL>_COMMAND gewinnt, sonst
#                                    commands.<schluessel> aus der Config. Fehlt ein "required"-Kommando
#                                    in beiden, nennt die Meldung den Schlüssel (kein stiller Default).
#   run_project_checks <verzeichnis> Projekt-Erweiterungspunkt: führt die ausführbaren Skripte des
#                                    Verzeichnisses lexikalisch aus (scripts/project/checks/*.d/).
#
# Erwartet vom Aufrufer FACTORY_DIR (Projektwurzel) und – für run_project_checks – die Farbvariablen
# RED/GREEN/YELLOW/NC. Fail-closed: kein pnpm-Fallback (ADR-063, nothra/tch-gastro-services#431).

# Effektive Config je Aufruf neu lesen (billig; die Gates laufen selten) – kein Cache, der veralten kann.
# _factory_cfg_eval <yq-ausdruck>: wertet den Ausdruck auf der gemergten Config aus.
_factory_cfg_eval() {
  local expr="$1" defaults="$FACTORY_DIR/factory.defaults.yml" override="$FACTORY_DIR/factory.config.yml"
  command -v yq >/dev/null 2>&1 || { echo "gate-config: yq nicht gefunden (Factory-Prerequisite)." >&2; return 1; }
  [ -f "$defaults" ] || return 0
  if [ -f "$override" ]; then
    yq eval-all '. as $i ireduce ({}; . * $i)' "$defaults" "$override" | yq eval "$expr" -
  else
    yq eval "$expr" "$defaults"
  fi
}

factory_cfg() { _factory_cfg_eval ".$1 // \"\""; }

# Nur nicht leere String-Elemente einer echten Liste, ohne Steuerzeichen: ein null/5 käme sonst als Text
# "null"/"5" an, ein Element mit Zeilenumbruch zerfiele in zwei scheinbar gültige Zeilen, ein leeres Element
# schnitte '$(…)' am Listenende lautlos ab, und '.[]' auf einer Map lieferte deren Werte als Einträge.
# Solche Elemente lehnt das Config-Gate ab (Regel 9); factory_cfg_list_dropped zählt sie für den Aufrufer.
_FACTORY_CFG_LIST_KEEP='select(tag == "!!str") | select(. != "") | select(test("[[:cntrl:]]") | not)'
factory_cfg_list() { _factory_cfg_eval "(.$1 // []) | select(tag == \"!!seq\") | .[] | $_FACTORY_CFG_LIST_KEEP"; }

# Zahl der Elemente, die factory_cfg_list verwirft; ein gesetzter Wert, der keine Liste ist, zählt als einer.
# (Ohne if/then/else: die gepinnte yq-Version kennt es nicht.)
factory_cfg_list_dropped() {
  _factory_cfg_eval "(.$1 // []) as \$l | ([\$l | select(tag != \"!!seq\")] | length)
    + ([\$l | select(tag == \"!!seq\") | .[]] | length)
    - ([\$l | select(tag == \"!!seq\") | .[] | $_FACTORY_CFG_LIST_KEEP] | length)"
}

# Ein Eintrag ist ein Pfad zu einer einzelnen Datei relativ zur Repo-Wurzel. Steuerzeichen schließen
# auch den Zeilenumbruch aus, der die zeilenweise Liste aus factory_cfg_list zerlegen würde.
# Gibt immer 0 zurück: Aufrufer unter 'set -e' werten nur die Ausgabe aus.
copy_entry_problem() {
  local entry="$1"
  case "$entry" in
    '')            echo "leerer Pfad" ;;
    /*)            echo "absoluter Pfad" ;;
    */)            echo "abschließendes '/' (nur einzelne Dateien)" ;;
    *[[:cntrl:]]*) echo "Steuerzeichen im Pfad" ;;
    *)
      case "/$entry/" in
        */../*) echo "'..'-Segment" ;;
      esac ;;
  esac
  return 0
}

gate_command() {
  local key="$1" mode="${2:-required}" env_name value
  env_name="FACTORY_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')_COMMAND"
  # Einfaches `-`: ein BEWUSST leer gesetztes FACTORY_FORMAT_COMMAND="" ist der Opt-out des
  # Format-Gates und fällt nicht auf die Config zurück (nothra/tch-gastro-services#149). Für Pflicht-Kommandos zählt ein
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
