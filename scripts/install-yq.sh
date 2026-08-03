#!/usr/bin/env bash
# install-yq.sh – installiert eine fest gepinnte, SHA-256-verifizierte yq-Binary (#258)
#
# Verwendung:
#   bash scripts/install-yq.sh
#       lädt die gepinnte Version, verifiziert sie und installiert sie nach /usr/local/bin/yq
#       (Schreibrecht dort nötig – in CI: `sudo bash scripts/install-yq.sh`).
#       Nur Linux/amd64: der gepinnte Hash gilt für genau ein Artefakt.
#   bash scripts/install-yq.sh --verify <binary> <checksums> <checksums_hashes_order> <sha256>
#       prüft nur eine bereits vorliegende Datei – netzwerkfrei, für den Self-Test
#   bash scripts/install-yq.sh --help
#       gibt diese Verwendung aus
#
# Einzige Quelle der yq-Bereitstellung in CI (factory-ci.yml: `config-validation`,
# `factory-self-test`; factory-poll.yml: `factory-poll`) – kein dreifach kopierter
# wget+chmod-Block mehr. Die Regel dazu steht in geladener Doku (CLAUDE.md §Guardrails,
# OPERATING.md §5.4), nicht nur hier im Header.
#
# Warum zwei Anker statt einem:
#   1. YQ_SHA256 ist im Repo gepinnt und damit der eigentliche Supply-Chain-Anker. Wird das
#      Release-Asset unter demselben Tag ersetzt (kompromittierter Publisher, Re-Upload),
#      weicht es von diesem Wert ab und der Schritt bricht ab. Eine Prüfung NUR gegen die
#      mitgeladenen `checksums` würde das nicht sehen: wer das Binary ersetzen kann, ersetzt
#      die Hash-Datei daneben mit – beide kommen aus demselben Kanal.
#   2. Die mitgeladenen `checksums` + `checksums_hashes_order` liefern den veröffentlichten
#      Vergleichswert und werden gegen den Pin geprüft. Sie erkennen Korruption,
#      Teil-Download und Asset-/Format-Drift, ersetzen den Pin aber nicht.
# Grenze der Zusage: der Pin ist ein Trust-on-First-Use-Anker (übernommen aus dem
# verifizierten CI-Lauf 30805947583 zu v4.53.3), keine Prüfung der Publisher-Identität.
# Eine Signaturkette (cosign/GPG) ist bewusst nicht Teil dieser Stufe (spec-258 §Nicht
# inbegriffen). Ein Versions-Bump ändert genau zwei Zeilen: YQ_VERSION + YQ_SHA256.
#
# Fail-closed: jeder Fehlerfall (Pin-Abweichung, Mismatch, fehlender Eintrag, Format-Drift,
# fremde Plattform, unbekanntes Argument, abgebrochener Download) bricht mit Exit ≠ 0 ab,
# BEVOR das Ausführbar-Bit gesetzt wird.

set -euo pipefail

YQ_VERSION="v4.53.3"
YQ_SHA256="fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4"
YQ_BINARY="yq_linux_amd64"
YQ_INSTALL_PATH="/usr/local/bin/yq"
# Welche Hash-Spalte der `checksums`-Datei SHA-256 ist, sagt allein
# `checksums_hashes_order` – mikefarah/yq rotiert diese Reihenfolge pro Release.
YQ_HASH_ALGO="SHA-256"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

fail() {
  echo -e "${RED}✗${NC} install-yq: $1" >&2
  exit 1
}

usage() {
  echo "Verwendung:"
  echo "  install-yq.sh                    lädt, verifiziert und installiert yq $YQ_VERSION (Linux/amd64)"
  echo "  install-yq.sh --verify <binary> <checksums> <checksums_hashes_order> <sha256>"
  echo "                                   prüft eine vorliegende Datei, netzwerkfrei"
  echo "  install-yq.sh --help             diese Ausgabe"
}

sha256_of() {
  local file="$1"
  # GNU-Coreutils (Linux/CI) vs. BSD/macOS – dieselbe Prüfsumme, anderes Werkzeug. Beide
  # Kandidaten werden geprüft, damit auch das Fehlen eines Hash-Werkzeugs eine eigene
  # Meldung trägt statt eines nackten "shasum: command not found".
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum -- "$file" | awk '{print $1}'
  elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 -- "$file" | awk '{print $1}'
  else
    fail "Kein SHA-256-Werkzeug gefunden (weder 'sha256sum' noch 'shasum') – keine Verifikation möglich (Abbruch)."
  fi
}

# published_sha256 <checksums> <checksums_hashes_order> <dateiname> <algorithmus>
# Gibt den im Release veröffentlichten SHA-256-Wert für <dateiname> auf stdout aus.
published_sha256() {
  local checksums_file="$1" order_file="$2" target="$3" algo="$4"
  local algo_line entry hash

  algo_line="$(awk -v algo="$algo" '$1 == algo { print NR; exit }' "$order_file")"
  [ -n "$algo_line" ] ||
    fail "'$order_file' enthält keine '$algo'-Zeile – ohne Spaltenzuordnung keine Verifikation möglich (Abbruch)."

  # Exakter Feldvergleich, nicht Präfix-Match: die Datei enthält auch Zeilen wie
  # '${target}.tar.gz', deren Hash für eine andere Datei gilt.
  entry="$(awk -v t="$target" '$1 == t { print; exit }' "$checksums_file")"
  [ -n "$entry" ] ||
    fail "'$checksums_file' enthält keinen Eintrag für '$target' – Abbruch statt Verifikation gegen einen leeren Erwartungswert."

  # Feld 1 ist der Dateiname, danach folgen die Hashes in der Reihenfolge des
  # order_file → dessen Zeile N liegt in Feld N+1.
  hash="$(printf '%s\n' "$entry" | awk -v col="$((algo_line + 1))" '{print $col}')"
  printf '%s' "$hash" | grep -qE '^[0-9a-f]{64}$' ||
    fail "Feld $((algo_line + 1)) der Zeile '$target' ist kein $algo-Wert ('${hash}') – Format-Drift, Abbruch."

  printf '%s' "$hash"
}

# verify_sha256 <binary> <checksums> <checksums_hashes_order> <gepinnter-sha256>
# Netzwerkfreier Kern: genau diese Funktion fährt der Self-Test gegen Fixtures. Der Pin ist
# ein Parameter, damit Produktionspfad und Test dieselbe Bahn nehmen – der Fixture-Pin des
# Tests durchläuft denselben Vergleich wie der Repo-Pin. Der Algorithmusname bleibt dagegen
# absichtlich global: er ist konstant, rotiert wird nur seine Position, und die kommt aus der
# übergebenen Order-Datei (also aus der Fixture) – Variieren im Test bringt hier nichts.
verify_sha256() {
  local binary="$1" checksums_file="$2" order_file="$3" pinned="$4"
  local file target published actual

  for file in "$binary" "$checksums_file" "$order_file"; do
    [ -r "$file" ] || fail "Datei nicht lesbar: '$file' – keine Verifikation möglich (Abbruch)."
  done

  target="$(basename -- "$binary")"

  # Erst der veröffentlichte Wert gegen den Repo-Pin: weichen sie ab, hat sich das
  # Release-Asset unter demselben Tag geändert (oder der Pin ist nach einem Bump veraltet).
  # Eigener Fehlerpfad, weil das eine andere Ursache ist als ein korrupter Download.
  published="$(published_sha256 "$checksums_file" "$order_file" "$target" "$YQ_HASH_ALGO")"
  [ "$published" = "$pinned" ] ||
    fail "Pin-Abweichung für '$target': veröffentlicht ist $published, im Repo gepinnt $pinned – Release-Asset geändert oder Pin veraltet (Abbruch ohne chmod)."

  actual="$(sha256_of "$binary")"
  [ "$actual" = "$pinned" ] ||
    fail "Checksum-Mismatch für '$binary': erwartet $pinned, berechnet $actual – Abbruch ohne chmod."

  echo -e "${GREEN}✓${NC} install-yq: SHA-256 von '$target' verifiziert ($pinned)"
}

# require_linux_amd64 – der gepinnte Hash gilt für genau EIN Artefakt ($YQ_BINARY).
# Ohne diesen Guard würde ein Aufruf auf macOS erfolgreich verifizieren (der Hash passt ja)
# und ein funktionierendes yq durch ein Linux-Binary ersetzen; auffallen würde das erst beim
# --version-Aufruf – also nach dem Überschreiben und ohne Rollback.
require_linux_amd64() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  [ "$os" = "Linux" ] ||
    fail "$YQ_BINARY ist ein Linux-Binary, dieses System meldet '$os' – Abbruch ohne Installation ('$YQ_INSTALL_PATH' bleibt unberührt). Lokal yq über den Paketmanager installieren."
  case "$arch" in
    x86_64 | amd64) ;;
    *)
      fail "$YQ_BINARY ist ein amd64-Binary, dieses System meldet Architektur '$arch' – Abbruch ohne Installation ('$YQ_INSTALL_PATH' bleibt unberührt)."
      ;;
  esac
}

# fetch <url> <zieldatei> – lädt eine Datei oder bricht mit der konkreten URL ab.
# `wget -q` allein verschweigt, WELCHE der drei URLs gescheitert ist (Job rot ohne
# Diagnose); --timeout/--tries begrenzen einen hängenden Download auf Sekunden statt
# aufs Job-Timeout.
fetch() {
  wget -q --timeout=30 --tries=3 -O "$2" -- "$1" ||
    fail "Download fehlgeschlagen: $1 – Abbruch ohne Installation."
}

# Fail-closed dispatchen: ein unbekanntes Argument darf NICHT in den privilegierten
# Installationspfad fallen (ein Tippfehler wie '--verfiy' täte sonst etwas völlig anderes
# als beabsichtigt, '--help' würde installieren) – analog zum Flag-Guard aus #262.
case "${1:-}" in
  --verify)
    # Eigene Meldung statt nur Usage: jeder Fehlerpfad benennt, WAS fehlt (sonst rät der
    # Aufrufer, welches der vier Argumente er vergessen hat).
    [ "$#" -eq 5 ] || {
      echo "install-yq: --verify braucht vier Argumente <binary> <checksums> <checksums_hashes_order> <sha256> (erhalten: $(($# - 1)))." >&2
      usage >&2
      exit 2
    }
    verify_sha256 "$2" "$3" "$4" "$5"
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  "")
    # Kein Argument = Installationspfad; läuft unterhalb des case weiter.
    ;;
  *)
    echo "install-yq: Unbekanntes Argument '$1'." >&2
    usage >&2
    exit 2
    ;;
esac

require_linux_amd64

DOWNLOAD_DIR="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

BASE_URL="https://github.com/mikefarah/yq/releases/download/$YQ_VERSION"
echo "install-yq: lade yq $YQ_VERSION ($YQ_BINARY) …"
fetch "$BASE_URL/$YQ_BINARY" "$DOWNLOAD_DIR/$YQ_BINARY"
fetch "$BASE_URL/checksums" "$DOWNLOAD_DIR/checksums"
fetch "$BASE_URL/checksums_hashes_order" "$DOWNLOAD_DIR/checksums_hashes_order"

verify_sha256 "$DOWNLOAD_DIR/$YQ_BINARY" "$DOWNLOAD_DIR/checksums" "$DOWNLOAD_DIR/checksums_hashes_order" "$YQ_SHA256"

# Ausführbar-Bit erst NACH erfolgreicher Verifikation: bricht die Prüfung oben ab, wurde
# nie eine ausführbare Datei erzeugt und nichts installiert (fail-closed).
chmod 0755 "$DOWNLOAD_DIR/$YQ_BINARY"
mv -- "$DOWNLOAD_DIR/$YQ_BINARY" "$YQ_INSTALL_PATH"
"$YQ_INSTALL_PATH" --version
