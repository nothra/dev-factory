# Security Review: Task 24

Geprüft: `git diff origin/main...HEAD` (Stand `80cec1b`) – Schwerpunkt `scripts/factory-update.sh`,
`.github/workflows/factory-update.yml`, `scripts/checks/pr-closes-keyword-check.sh` + `factory-ci.yml` (Gate-Ausnahme
E14), ADR-063 E4/E12, dazu das Zusammenspiel mit `scripts/factory-sync.sh` (#23). Bedrohungsmodell: ein Konsumenten-Repo
führt den Workflow täglich mit einem Fine-grained PAT aus (Contents/Pull requests/Workflows read+write, Laufzeit ≤ 1 Jahr).
Eingaben von außen: die Release-Liste des Quell-Repos (Tags, Release-Bodies, Assets), der Inhalt des abgeholten Releases
und der Zustand von PRs und Branch im Konsumenten-Repo.

Dritter Durchgang nach dem Doku-Fix `01f00ba` (Finding „`env -u` ist keine Grenze" aus dem zweiten Durchgang). Delta
seit dem zweiten Durchgang (`7bed7f5..80cec1b`): Kommentar `scripts/factory-update.sh:148-150`, ADR-063 E4
(`063-…md:503-504`) und E12 (`:612-617`), dazu Report-/Task-Dateien und der Pagination-Test aus `/test`. Kein
ausführbarer Code geändert (`git diff 7bed7f5 HEAD -- scripts .github` zeigt nur den Kommentar).

## Kritische Findings (Blocker)

_keine_

## Wichtige Findings

_keine_

- [x] **[Secrets / Lieferkette] Behoben (zweiter Durchgang): `env -u` wurde als Grenze gegen Release-Code dargestellt.**
  Kommentar `factory-update.sh:148-150` sagt jetzt „soll … nicht versehentlich erben" und „keine Grenze gegen bösartigen
  Release-Code im selben Job". ADR-063 E12 nennt die drei Wege aus dem zweiten Durchgang (`.git/config`/`core.fsmonitor`
  beim `git add`, `/proc/<ppid>/environ`, Workflow-Datei im Update-PR), nimmt das Restrisiko bewusst an (Voraussetzung:
  kompromittierter Tag in der Factory; `main` durch Ruleset geschützt) und verweist auf **Issue #37** (offen, Labels
  `enhancement` + `security`). E4 verweist knapp auf dieselbe Grenze. Der `env -u`-Aufruf und sein Test bleiben
  unverändert – wie empfohlen.

## Hinweise

- [ ] **[Integrität] Release-Notes landen ungefiltert im PR-Body** (`scripts/factory-update.sh:166`). Ein
  `Closes #12`/`@name` im Release-Text würde beim Merge ein **Konsumenten**-Issue schließen bzw. jemanden
  benachrichtigen; das Gate `pr-closes-issue` sieht den Body für diesen Branch bewusst nicht an (E14). `CHANGELOG.md`
  enthält aktuell keine Closing-Keywords → geringes Risiko. Vom Implementierer bewusst nicht umgesetzt; unverändert.
- [ ] **[Konfiguration] Credential-Helper prüft den Host nicht.** Benutzt werden nur `fetch`/`push` gegen `origin`
  (`github.com` aus `actions/checkout`). Kein Handlungsbedarf, solange keine weiteren Remotes dazukommen.
- [ ] **[Restrisiko, akzeptiert] Trennung von Abholung und Token** bleibt strukturell offen – verfolgt in Issue #37,
  in ADR-063 E12 benannt. Kein Blocker für diesen PR.
- [ ] **[Hygiene] Wegwerf-Dateien:** die `scripts/*.tmp.sh` aus früheren Durchgängen sind entfernt; noch vorhanden
  (gitignoret, nicht im PR): `tasks/telemetry-raw-24-20261030T221510Z.tmp.txt`,
  `tasks/telemetry-raw-24-20261031T102944Z.tmp.txt` – manuell löschen.

Geprüft und unauffällig: Token nie in argv/URL/`.git/config` (`persist-credentials: false`, Helper per `-c` als
Literal, `credential.helper=` vorher geleert, `GIT_TERMINAL_PROMPT=0`); `GITHUB_TOKEN` wird entfernt, Workflow-Rechte
nur `contents: read`; `GITHUB_REPOSITORY` gegen Slug-Regex, Tags gegen `^v\d+\.\d+\.\d+$` geprüft, bevor sie in Befehle
und Pfade fließen; Release-Liste fail-closed validiert (auch mehrseitig); PR-Auswahl nur ohne `isCrossRepository`;
Push nur auf `refs/heads/chore/factory-update` mit Lease; nie `merge`/`--auto`; Hooks bei Checkout/Fetch/Commit/Push
aus; Abholung ohne Token in der Umgebung (Schutz vor versehentlicher Weitergabe); Selbst-Ersatz per `main "$@"; exit $?`
abgefangen; Fehlermeldungen geben gh-/API-Texte aus, aber nie das Token; Gate-Ausnahme E14 über `env:` statt
`${{ }}`-Interpolation, Trigger `pull_request`, Fork-PRs bleiben geprüft; keine neuen Abhängigkeiten oder Fremd-Actions.

## Ergebnis
PASSED
