# Security Review: Task 24

Geprüft: `git diff origin/main...HEAD` – Schwerpunkt `scripts/factory-update.sh`, `.github/workflows/factory-update.yml`,
`scripts/checks/pr-closes-keyword-check.sh` + `factory-ci.yml` (Gate-Ausnahme E14), dazu das Zusammenspiel mit dem
bestehenden `scripts/factory-sync.sh` (#23). Bedrohungsmodell: ein Konsumenten-Repo führt den Workflow täglich mit einem
Fine-grained PAT aus (Contents/Pull requests/Workflows read+write, Laufzeit ≤ 1 Jahr); Eingaben von außen sind die
Release-Liste des Quell-Repos (Tags, Release-Bodies, Assets), der Inhalt des abgeholten Releases und der Zustand von
PRs/Branch im Konsumenten-Repo.

## Kritische Findings (Blocker)

_keine_

## Wichtige Findings

- [ ] **[Secrets / Lieferkette] Neu abgeholter Factory-Code läuft mit `FACTORY_SYNC_TOKEN` in der Umgebung – vor jedem
  menschlichen Review.** `rebuild_branch` ruft `FACTORY_DIR="$ROOT" bash "$SYNC" "$TARGET_VERSION"`
  (`scripts/factory-update.sh:144`) mit unveränderter Umgebung auf; das Token ist dort exportiert (Workflow-`env:`).
  `factory-sync.sh` schreibt in Phase 2 die Release-Dateien – darunter sich selbst (`scripts/factory-sync.sh` steht auf
  Seite `factory`, `OWNERSHIP.md:76`) – und ruft danach `bash "$SELF" --compose --check` auf
  (`scripts/factory-sync.sh:322`, `$SELF` = derselbe Pfad, also schon die **neue** Fassung). Folge: ein kompromittierter
  oder fehlerhafter Tag im Quell-Repo bekommt sofort Codeausführung mit einem PAT, das Workflows und Inhalte im
  Konsumenten-Repo schreiben darf (andere Branches, Workflow-Dateien, Tags) – genau der Schritt, den Update-PR, Gates und
  menschliche Freigabe (AK2.4, F1) vor das Übernehmen neuer Factory-Fassungen stellen sollen. Das Verhalten von
  `factory-sync.sh` stammt aus #23, die Token-Exposition entsteht erst mit diesem PR. Auch der Kommentar in
  ADR-063 E4 („Phase 2 führt nur lokale Kopien aus“) trifft auf Zeile 322 nicht zu.
  **Empfohlene Lösung (im Scope, wenige Zeilen):** die Abholung ohne Anmeldedaten laufen lassen, z. B.
  `env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN FACTORY_DIR="$ROOT" bash "$SYNC" "$TARGET_VERSION"` –
  `factory-sync.sh` holt das Release per anonymem `git`/`curl` und braucht kein Token. Test: Stub-`factory-sync.sh`
  im Fixture protokolliert, ob `FACTORY_SYNC_TOKEN` gesetzt ist; Erwartung „leer“, Mutationsbeleg ohne `env -u` → rot.
  Den ADR-Satz in E4 präzisieren (die nachgezogene `--compose --check`-Prüfung führt die neue Fassung aus).

## Hinweise

- [ ] **[Integrität] Release-Notes landen ungefiltert im PR-Body.** `write_body` übernimmt `.body` jedes Releases
  (`scripts/factory-update.sh:159`). Enthält ein Release-Text `Closes #12`/`Fixes #12` oder `@name`, schließt der Merge
  des Update-PRs das **Konsumenten**-Issue #12 bzw. benachrichtigt die Person – das Gate `pr-closes-issue` sieht den
  Body für diesen Branch bewusst nicht mehr an (E14). Die Marke ist korrekt gegen zitierte Notes abgesichert (nur der
  Kopf zählt). Aktuell enthält `CHANGELOG.md` keine Closing-Keywords; Risiko daher gering. Abhilfe bei Bedarf: Notes in
  einen `<details>`-Block mit eingerücktem Code oder Keywords/`@` entschärfen – Entscheidung beim Implementierer.
- [ ] **[Konfiguration] Credential-Helper prüft den Host nicht.** Der Helper gibt das Token für jede Anfrage aus
  (`scripts/factory-update.sh:36`). Benutzt werden nur `fetch`/`push` gegen `origin` (von `actions/checkout` auf
  `github.com` gesetzt), Git reicht Anmeldedaten nicht an fremde Redirect-Hosts weiter → kein Handlungsbedarf, nur
  festgehalten, falls später weitere Remotes dazukommen.
- [ ] **[Gate-Ausnahme] E14 ist sauber umgesetzt.** Werte kommen als `env:` (keine `${{ }}`-Interpolation im `run:`),
  Trigger ist `pull_request` (nicht `pull_request_target`), Fork-PRs mit gleichem Branch-Namen bleiben geprüft. Dass
  jeder mit Push-Recht die Ausnahme nutzen kann, ist im Skriptkopf als „Hygiene-Gate, keine Sicherheitsgrenze“ benannt.

Geprüft und unauffällig: Token nie in argv/URL/`.git/config` (`persist-credentials: false`, Helper per `-c`,
`credential.helper=` zurückgesetzt, `GIT_TERMINAL_PROMPT=0`); `GITHUB_TOKEN` wird entfernt, Workflow-Rechte nur
`contents: read`; `GITHUB_REPOSITORY` gegen Slug-Regex, Tags gegen `^v\d+\.\d+\.\d+$` geprüft, bevor sie in
Befehle/Pfade fließen; Push nur auf `refs/heads/chore/factory-update` mit Lease; nie `merge`/`--auto`; Fehlermeldungen
geben gh-/API-Fehlertexte, aber nie das Token aus; Release-Liste fail-closed validiert; Fremd-Action vermieden.

## Ergebnis
NEEDS_FIXES
