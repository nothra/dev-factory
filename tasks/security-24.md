# Security Review: Task 24

Geprüft: `git diff origin/main...HEAD` (Stand `7bed7f5`) – Schwerpunkt `scripts/factory-update.sh`,
`.github/workflows/factory-update.yml`, `scripts/checks/pr-closes-keyword-check.sh` + `factory-ci.yml` (Gate-Ausnahme
E14), ADR-063 E4/E12, dazu das Zusammenspiel mit `scripts/factory-sync.sh` (#23). Bedrohungsmodell: ein Konsumenten-Repo
führt den Workflow täglich mit einem Fine-grained PAT aus (Contents/Pull requests/Workflows read+write, Laufzeit ≤ 1 Jahr).
Eingaben von außen: die Release-Liste des Quell-Repos (Tags, Release-Bodies, Assets), der Inhalt des abgeholten Releases
und der Zustand von PRs und Branch im Konsumenten-Repo.

Zweiter Durchgang nach dem Fix `aa6ccbe`/`a90e82a` (Abholung per `env -u …`) und Review-Iteration 4 (Hooks aus).

## Kritische Findings (Blocker)

_keine_

## Wichtige Findings

- [ ] **[Secrets / Lieferkette] Der Fix aus dem ersten Durchgang ist keine Grenze – Code und ADR behaupten aber eine.**
  `scripts/factory-update.sh:148-149` („Code eines noch ungeprüften Tags darf das schreibberechtigte PAT nie sehen“),
  ADR-063 E4 (`063-…md:501-503`, „ohne Anmeldedaten in der Umgebung“) und E12 (`:608-610`) stellen `env -u` als
  Abschirmung gegen den Release-Code dar. Das stimmt nur für ein **versehentliches** Weiterreichen (Logging, `curl` mit
  Env). Code des Release läuft weiter im selben Job und unter demselben Benutzer wie der spätere Push und kann an das Token
  kommen:
  1. **`.git/config`:** Release-Code schreibt z. B. `core.fsmonitor`. Das folgende `git add -A` (`:151`, ohne Wrapper)
     und auch `git -c core.hooksPath=/dev/null commit/status` führen den Befehl mit `FACTORY_SYNC_TOKEN` in der Umgebung
     aus. **Selbst nachgestellt** (Wegwerf-Repro `scripts/sec24-fsmonitor.tmp.sh`): Ausgabe
     `FACTORY_SYNC_TOKEN=geheim-123` bzw. `…-456` nach dem `hooksPath`-Aufruf. `core.hooksPath` schaltet nur Hooks
     ab, keine anderen Befehle aus der Config (Filter, `fsmonitor`, `include.path` …).
  2. **Prozessumgebung/Runner:** unter Linux liest ein Kindprozess desselben Benutzers `/proc/<ppid>/environ` des
     Elternprozesses (Yama `ptrace_scope=1` beschränkt nur das Anhängen, nicht das Lesen); GitHub-Runner haben außerdem
     passwortloses `sudo`, `git`/`gh` lassen sich also austauschen. (Hier nicht nachgestellt, kein Linux/Docker verfügbar.)
  3. **Der Update-PR selbst:** er kommt aus demselben Repo. `pull_request`-Workflows laufen mit den Workflow-Dateien des
     PR-Stands und sehen alle Repository-Secrets – ein Release, das eine Datei unter `.github/workflows/` ändert, kann
     `secrets.FACTORY_SYNC_TOKEN` auslesen, bevor ein Mensch den PR geprüft hat. Diesen Weg hat schon der erste Durchgang
     übersehen.
  **Einordnung:** Voraussetzung ist ein kompromittiertes oder fehlerhaftes Release in `nothra/dev-factory`; die Wirkung
  ist ein Schreib-PAT auf das Konsumenten-Repo (Branches außer `main`, Workflow-Dateien, Tags). `main` bleibt durch
  das Ruleset geschützt. Eine echte Trennung braucht eine Änderung am Aufbau des Workflows → **Issue #37**
  (Environment-Secret mit Branch-Regel `main`, Abholung und Push auf zwei Jobs verteilen).
  **Im Scope (wenige Zeilen Prosa):** Kommentar `:148-149` sowie ADR-063 E4 und E12 ehrlich fassen – `env -u`
  verhindert, dass das Token versehentlich weitergegeben wird, ist aber keine Grenze gegen Code aus dem Release im
  selben Job. Das Vertrauen in die Tags des Quell-Repos ist die eigentliche Annahme; Restrisiko benennen und auf #37
  verweisen. Der `env -u`-Aufruf und sein Test bleiben, sie sind als Schutz vor versehentlicher Weitergabe richtig.

## Hinweise

- [ ] **[Integrität] Release-Notes landen ungefiltert im PR-Body** (`scripts/factory-update.sh:165`). Ein
  `Closes #12`/`@name` im Release-Text würde beim Merge ein **Konsumenten**-Issue schließen bzw. jemanden
  benachrichtigen; das Gate `pr-closes-issue` sieht den Body für diesen Branch bewusst nicht an (E14). `CHANGELOG.md`
  enthält aktuell keine Closing-Keywords → geringes Risiko. Vom Implementierer bewusst nicht umgesetzt; unverändert.
- [ ] **[Konfiguration] Credential-Helper prüft den Host nicht** (`:37`). Benutzt werden nur `fetch`/`push` gegen
  `origin` (`github.com` aus `actions/checkout`). Kein Handlungsbedarf, solange keine weiteren Remotes dazukommen.
- [ ] **[Gate-Ausnahme] E14 ist sauber umgesetzt.** Werte kommen über `env:` (keine `${{ }}`-Interpolation im `run:`),
  Trigger ist `pull_request` (nicht `pull_request_target`), Fork-PRs mit gleichem Branch-Namen bleiben geprüft.
- [ ] **[Hygiene] Wegwerf-Dateien dieses Durchgangs:** `scripts/sec24-fsmonitor.tmp.sh`, `scripts/sec24-issue.tmp.sh`
  (gitignoret, nicht im PR). `rm` war nicht freigegeben – zusammen mit den älteren `scripts/*.tmp.sh` und
  `tasks/telemetry-raw-24-*.tmp.txt` manuell löschen.

Geprüft und unauffällig: Token nie in argv/URL/`.git/config` (`persist-credentials: false`, Helper per `-c` als
Literal, `credential.helper=` vorher geleert, `GIT_TERMINAL_PROMPT=0`); `GITHUB_TOKEN` wird entfernt, Workflow-Rechte
nur `contents: read`; `GITHUB_REPOSITORY` gegen Slug-Regex, Tags gegen `^v\d+\.\d+\.\d+$` geprüft, bevor sie in Befehle
und Pfade fließen; Release-Liste fail-closed validiert (auch mehrseitig); PR-Auswahl nur ohne `isCrossRepository`;
Push nur auf `refs/heads/chore/factory-update` mit Lease; nie `merge`/`--auto`; Hooks bei Checkout/Fetch/Commit/Push
aus; Selbst-Ersatz per `main "$@"; exit $?` abgefangen; Fehlermeldungen geben gh-/API-Texte aus, aber nie das Token;
keine neuen Abhängigkeiten oder Fremd-Actions.

## Ergebnis
NEEDS_FIXES
