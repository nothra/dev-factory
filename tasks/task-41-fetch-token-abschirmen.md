# Task 41: fetch-token-abschirmen

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Im Job `fetch` von `factory-update.yml` läuft Release-Code auf einem Runner, auf dem das Runtime-Token des Laufs liegt
(Cache-Schreibrecht im Scope `main`). Er erreicht es über `$GITHUB_ENV`/`$GITHUB_PATH` und den Folgeschritt sowie über
`sudo` direkt aus dem Speicher von `Runner.Worker`. Lösung: Release-Code in einem unprivilegierten Container ausführen,
zurück kommt nur das Bundle. Dazu ADR-063-Nachtrag und OPERATING §0.6. Spec: `docs/specs/spec-41-fetch-token-abschirmen.md`.
ADR-Trigger: ja (Jobstruktur/Isolationsgrenze) → `/architecture 41` vor `/implement`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt; Volltext in der Spec -->
- [x] AK1.1 Release-Code (Abholung, Commit, Bundle) läuft im `fetch`-Job nur im Container
- [x] AK1.2 Container ohne Sonderrechte (kein privileged/pid/network/ipc host, kein cap-add, kein Docker-Socket; cap-drop ALL, no-new-privileges)
- [x] AK1.3 Keine ACTIONS_*-/Token-Variablen, kein env-file, keine Runner-Dateien; nur Arbeits- und Ausgabeverzeichnis eingebunden
- [ ] AK1.4 Image per Digest gepinnt, nicht aus Arbeitsbaum/Release gebaut (Build ohne Kontext erledigt; Digest `sha256:a72b…` eingetragen, Ladbarkeit belegt erst der erste Lauf des Smoke-Jobs, siehe Blocker)
- [x] AK2.1 Nach dem Container nur der Upload der Bundle-Datei; kein git/keine Ausführung im Container-Verzeichnis
- [x] AK2.2 Manipulation von `.git/config`/Hooks wird auf dem Host nie ausgeführt
- [x] AK3.1 Bundle und Update-PR unverändert
- [x] AK3.2 Tests zu #23/#24/#37 grün, geänderte Anker mindestens gleich streng
- [x] AK4.1 Wiring-Tests an der echten `factory-update.yml`, ohne Docker lauffähig
- [x] AK4.2 Mutationsbeleg je tragender Eigenschaft
- [ ] AK4.3 Smoke-Job in `factory-ci.yml`: Image echt bauen und mit echten Optionen starten (Job angelegt und verdrahtet; erster echter Lauf in CI steht aus)
- [x] AK5.1 ADR-063-Nachtrag (#41) inkl. Korrektur der `sudo`-Aussage in E17
- [x] AK5.2 OPERATING §0.6: Container, Docker-Voraussetzung, Restrisiko für Caches
- [x] F1 Kein Docker → `fetch` rot, kein stiller Rückfall
- [x] F2 Image nicht ladbar/Digest falsch → rot
- [x] F3 Kein Bundle → rot, `publish` läuft nicht
- [x] F4 Symlink/Verzeichnis statt Bundle → nichts von außerhalb des Ausgabeverzeichnisses hochgeladen

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Factory-ADR-063, Nachtrag 2026-11-20 (E28–E34), Status Proposed → mit der Umsetzung Accepted setzen.

- **Neuer Modus** `factory-update.sh fetch-isolated <version> <base_sha> <out_dir>` (Host, nur main-Code):
  `docker info` → `docker build -t <tag> -` (Heredoc, `FROM debian:<stable>-slim@sha256:<digest>`, `apt-get install
  --no-install-recommends git jq curl ca-certificates`; Digest als Konstante, per `docker buildx imagetools inspect`
  ermitteln) → `docker run` → Ausgabe prüfen.
- **`docker run`-Argumente in genau einem Array:** `--rm --cap-drop ALL --security-opt no-new-privileges
  --user $(id -u):$(id -g) -e HOME=/tmp -v "$ROOT:/src:ro" -v "$out:/out" -v "$(command -v yq):/usr/local/bin/yq:ro"`;
  Kommando `bash -c 'cp -a /src/. /tmp/work && bash /tmp/work/scripts/factory-update.sh fetch "$1" "$2" /out/update.bundle' _ "$version" "$base"`.
- **Rückweg:** `<out_dir>` neu anlegen (existiert → Exit 1). Danach genau ein Eintrag `update.bundle`, reguläre Datei,
  kein Symlink → sonst Exit 1. Kein `git` auf Container-Daten.
- **`fetch` in CI sperren:** `GITHUB_ACTIONS=true` → die mit Verweis auf `fetch-isolated` (Docker reicht die Variable nicht durch).
- **Workflow `fetch`:** checkout → install-yq → `bash scripts/factory-update.sh fetch-isolated "$VERSION" "$BASE_SHA" "$RUNNER_TEMP/fetch-out"`
  → upload-artifact mit `path: ${{ runner.temp }}/fetch-out/update.bundle`. Anker `wf_ok_37` anpassen.
- **Tests:** Fake-`docker` im `PATH` (protokolliert argv, simuliert `/out`-Inhalte und Fehler). Wiring, Argumente,
  Rückweg, CI-Sperre, Mutationsbelege. Neue Gruppe `factory-lock-41-tests.sh` → `OWNERSHIP.md`-Zeile + Eintrag in `run-tests.sh`.
- **Smoke-Job** in `factory-ci.yml` (E34 f); dieselben Optionen wie das Array, daher den Aufruf im Skript wiederverwenden
  (z. B. Modus/Funktion mit austauschbarem Kommando) statt die Optionen im YAML zu kopieren.
- **Doku:** OPERATING §0.6 „Aufbau des Workflows"; E17-Berichtigung ist schon drin; Release-Notes: selbst gehostete
  Runner ohne Docker werden in `fetch` rot.

**Umsetzung (/implement, 2026-11-20):**
- Die `docker run`-Optionen stehen in **einem** Aufruf in `run_in_fetch_container` (statt eines Arrays). Das ist die eine
  Stelle aus E29; `fetch-isolated` und `fetch-smoke` starten beide darüber.
- Neue Testgruppe `factory-lock-41-tests.sh`. Sie läuft automatisch mit, weil der Gruppen-Glob in `run-tests.sh` sie
  findet, und `OWNERSHIP.md` deckt sie über `scripts/checks/tests/**` ab. Deshalb gibt es keine Einzelzeile.
- Fake-`docker` mit Modus `emulate`: Er bildet den Container nach (Arbeitskopie, Pfade umgelenkt, Umgebung nur aus `-e`).
  Damit laufen offline Ende-zu-Ende-Tests für AK2.2/AK3.1 und eine Gegenprobe mit durchgereichtem Token.
- Der Smoke-Job prüft zusätzlich harmlos: kein root, keine `ACTIONS_`/`GITHUB_`/`RUNNER_`-Variablen, `/src` nicht beschreibbar.
- Anker `wf_ok_37` auf `fetch-isolated` umgestellt. Die volle Schrittfolge prüft jetzt `wf_fetch_ok_41` (strenger).
- Guard `#431 AK-F1` und `OWNERSHIP.md` kennen den 7. Job `fetch-container-smoke`. Im CHANGELOG steht unter Unreleased
  der Breaking-Hinweis für selbst gehostete Runner.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Q1–Q5 in `/architecture` geklärt (ADR-063 E28–E34).

Blocker 2026-11-20: In `scripts/factory-update.sh` steht für `FETCH_BASE_IMAGE` ein Digest aus lauter Nullen. Den echten
Digest konnte die Session nicht holen, weil sie keinen Netz- oder Docker-Zugriff hatte. Der Test „#41 AK1.4: echter
Digest“ ist deshalb bewusst rot und hält das pre-push-Gate an. Ermitteln:
`docker buildx imagetools inspect debian:trixie-slim --format '{{json .Manifest.Digest}}'`, dann die eine Zeile ersetzen.

Update 2026-11-20 (/implement, Folgesession): In Commit 03359c5 steht für `FETCH_BASE_IMAGE` der Digest
`sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2`. Der Test „#41 AK1.4: echter Digest" ist
grün, die ausgelieferte Suite steht bei 2633/0, die Projekt-Suite bei 249/0, `pre-push.sh` ist grün. Gegen die Registry
geprüft ist der Digest noch nicht, weil die Session keine Docker-Freigabe hatte. Der Test schließt nur den
Nullen-Platzhalter aus. Ob das Image ladbar ist, zeigt erst der Job `fetch-container-smoke` in CI (F2: falscher Digest →
rot). Mit dessen erstem grünen Lauf werden AK1.4 und AK4.3 abgehakt.

## Review-Findings
<!-- Wird durch /review befüllt -->
Runde 1 (2026-11-20): **APPROVED**, 0 kritische, 2 wichtige, 4 Nitpicks. Details in `tasks/review-41.md`.
- Wichtig: Der Smoke-Befehl lässt die fetch-eigenen Schritte im Container nicht laufen (`cp -a`, git in der Kopie,
  Commit als UID ohne passwd-Eintrag). Ergänzen, bevor `fetch-container-smoke` zum ersten Mal läuft.
- Wichtig: AK1.4 und AK4.3 erst nach grünem `fetch-container-smoke` auf dem PR abhaken. Vor dem Merge darauf warten.

## Test-Notizen (/test, 2026-11-20)
- Jedes AK und F1–F4 hat Happy- und Fehlerfall plus Mutationsbeleg. Es gab keine AK-Lücke. Die Gruppe `factory-lock-41-tests.sh`
  steht bei 82 grün (vorher 78), die ausgelieferte Suite bei 2637/0, die Projekt-Suite bei 249/0. Coverage gibt es im
  Bash-Repo nicht, die Mutationsbelege stehen an ihrer Stelle.
- Zwei Review-Nitpicks sind jetzt im Test abgedeckt. Der Verbots-Prüfer erkennt `--cgroupns=host` und ein getrennt
  übergebenes `--security-opt <wert>` ≠ `no-new-privileges`, jeweils mit Mutationsbeleg. Zudem prüft ein Test, dass
  `FETCH_BUNDLE` und der feste Ausgabepfad in `FETCH_CONTAINER_SCRIPT` übereinstimmen.
- Nicht in diesem Schritt: Die Erweiterung des Smoke-Befehls (Produktionscode, Review-Finding „wichtig") und die
  Registry-Prüfung des Digests. Beides gehört in `/implement` bzw. in den ersten Lauf von `fetch-container-smoke`.

## Refactoring-Notizen (/refactor, 2026-11-20)
- Kein Code geändert. Geprüft: Naming, Funktionslänge (alle neuen Funktionen ≤ 10 Zeilen), Parameter (≤ 3), Duplikation, Magic Strings.
- Bewusst belassen: `FETCH_CONTAINER_SCRIPT` schreibt `/out/update.bundle` fest. Ein Ableiten aus `FETCH_BUNDLE` änderte den
  exakt gepinnten Aufruf (E31) und den Test-Anker `SCRIPT_41`; die Übereinstimmung sichert schon `bundle_const_ok_41`
  mit Mutationsbeleg. Der Gewinn rechtfertigt die gelockerte Pinnung nicht.
- Nicht Refactoring (neues Verhalten, bleibt für /implement): Smoke-Befehl erweitern, `docker build --no-cache`.
- Tests unverändert (kein Code geändert; Stand /test: 2637/0).

## Security-Notizen (/security-review, 2026-11-20)
**PASSED**, 0 kritische, 1 wichtiges Finding, 8 Hinweise. Details in `tasks/security-41.md`. Geprüft wurde nur statisch,
weil Docker und die Testgruppe ohne Freigabe nicht liefen.
- Die Isolationsgrenze hält: kein Weg zum Runtime-Token, keine Ausführung von Container-Daten auf dem Host.
- Wichtig, im Scope (für `/implement`): W1. Der Runner wertet stdout und stderr des Containers als Workflow-Kommandos
  aus. Den Kanal um `docker run` mit `::stop-commands::<zufälliges Token>` sperren und das per Test belegen.
- Kleinere Punkte im Scope: Die Meldung in `mode_all` (`:437`) nennt noch `fetch` statt `fetch-isolated`. `make_out_dir`
  könnte `:` und `,` im Pfad ablehnen.
- Out-of-Scope, Netz (Host-Gateway, Metadata-Dienst, WireServer erreichbar): Nach der Zweifelsregel gehört das in ein
  Issue mit `enhancement` + `security`. **Die Anlage steht noch aus**, weil der Seam eine Freigabe brauchte.
- Out-of-Scope, DoS durch ein riesiges Bundle: als Eintrag in `docs/factory/kleinfunde.md`.

## Codify-Notizen
Zwei neue Lessons in `docs/factory/lessons/factory-workflow.md` und `lessons/INDEX.md`: Log-Kanal als Rückkanal bei
Fremdcode-Isolation (W1) und Pin-Wert ohne Netz nicht erfinden (Null-Digest). Details: `tasks/codify-41.md`.
Offen: Issue „Fetch-Container vom Host-Gateway und Link-Local-Diensten abschotten" (`enhancement` + `security`) ist noch
anzulegen, die Anlage lehnte der Permission-Layer ab. DoS durch riesiges Bundle steht in `docs/factory/kleinfunde.md`.

---
Branch: `fix/41-fetch-token-abschirmen`
Erstellt: 2026-11-20 21:41
