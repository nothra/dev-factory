# Review: Task 51

> Stand: `b66c121` gegen `origin/main` (`7153bd6`), 2026-11-09. Alle drei Runden (Logik, Code-Qualität,
> Architektur) liefen direkt im Orchestrator-Kontext; bei einem Diff dieser Größe lohnte die Fork-Delegation nicht
> (vgl. Lessons nothra/tch-gastro-services#298/#267). Projekt-Suite lokal: 191 grün, 0 rot (davon 45 Assertions im Block `#51`).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [scripts/project/tests/run-tests.sh:773] **Der Wrapper ist im Hook-Kontext eines Worktrees nicht als Verhalten
  getestet.** Das ist der eigentliche Anwendungsfall der Task: `start-work.sh` legt jede Task per Default in einem Worktree an,
  und der erste Push nach `/requirements` ist dort der typische reine Spec-/Task-Push. Git exportiert im pre-push-Hook eines
  Worktrees `GIT_DIR` und weitere Variablen (`assert-helpers.sh:20`). Alle `#51`-Tests laufen aber ohne diese Variablen,
  denn `assert-helpers.sh:23` unsetzt sie global. AK6 belegt per Grep nur, dass beide Aufrufer das Kommando über
  `gate_command` auflösen. Im Hook-Kontext gelaufen ist der Wrapper bisher nur beim Push dieses Branchs, also im Pfad
  „voller Lauf“. Ein dortiges Scheitern von `merge-base`/`diff`/`ls-files` wäre unsichtbar geblieben, weil auch der Fehlerpfad
  voll läuft. Das Risiko ist fail-closed (schlimmstenfalls bewirkt das Feature nichts), aber die Kernaussage bleibt unbelegt.
  Das ist dieselbe Fehlerklasse wie Lesson nothra/tch-gastro-services#348 und das Rezidiv nothra/tch-gastro-services#431
  („je Konsument ein eigener Test“). **Fix (~15 Zeilen):** Wegwerf-Repo mit Bare-Remote und `git worktree add` aufsetzen,
  im gemeinsamen `.git/hooks/pre-push` den Wrapper mit `FACTORY_DIR="$PWD"` aufrufen und aus dem Worktree pushen. Dann
  (a) einen Commit nur unter `tasks/` pushen → Ausgabe enthält die Skip-Meldung und kein `SUITE_RAN_51`, und (b) eine
  untracked Datei außerhalb anlegen → voller Lauf mit Grund „außerhalb“. Den Hook im Fixture **nicht** über
  `install-hooks.sh` installieren, sondern als Einzeiler: Geprüft wird der Git-Hook-Kontext, nicht `pre-push.sh`. Eine
  Sonde dafür ließ sich in dieser Review-Session nicht ausführen, weil die Shell-Guardrails sie blockierten. Das Ergebnis
  ist also offen und nicht negativ.

## Nitpicks (optional)

- [ ] [scripts/project/tests/run-tests.sh:718] Der Test „F1/F3: kein Git-Repo“ prüft nur `SUITE_RAN_51`, nicht den Grund.
  Damit bleibt offen, welcher Fail-Pfad greift. Laut Kommentar soll es der Merge-Base-Pfad sein. Eine Zeile
  `assert_contains_286 "$out_51" "Merge-Base mit origin/main nicht bestimmbar" …` isoliert den Pfad (AK9, Lesson
  „Negativ-Test mit mehreren Fail-Pfaden isolieren“, nothra/tch-gastro-services#214).
- [ ] [scripts/project/checks/factory-suite-gate.sh:63] Der Wrapper prüft `HEAD` und den Working Tree, nicht die Refs, die
  gerade gepusht werden. `git push origin anderer-branch` von einem reinen Spec-/Task-Stand aus überspringt die Suite deshalb,
  obwohl ein Branch mit Code gepusht wird. Das passt zum bisherigen Verhalten aller pre-push-Checks, die ebenfalls den
  Working Tree prüfen, und CI bleibt fail-closed. Ein Satz im Kopfkommentar würde die Grenze trotzdem sichtbar machen.
- [ ] [scripts/project/checks/factory-suite-gate.sh:81] `main "$@"` reicht Argumente weiter, die `main` nicht auswertet.
  `main` genügt, oder `exec bash "$SUITE" "$@"`, falls Argumente zur Suite durchgereicht werden sollen.
- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:182] D9 nennt `commands.test` = `run-tests.sh`. Das
  stimmt nach diesem PR nicht mehr (`commands.lint` = ShellCheck war schon vorher überholt). Die Datei gehört der Seite
  `factory`, und AK7 schließt Änderungen dort in diesem PR aus. Auch `docs/factory/kleinfunde.md` ist Seite `factory`. Der
  Fund steht deshalb nach der Regel im Dateikopf von `kleinfunde.md` nur hier. Es geht um Doku-Drift in einer Beschreibung
  des Ist-Stands, unterhalb der Schwelle (Factory-ADR-043). Mitnehmen, wenn ADR-063 ohnehin angefasst wird.

## Positives

- **Fail-closed konsequent umgesetzt:** Override, fehlende Merge-Base, `mktemp`-Fehler, jeder einzelne Git-Schritt und
  eine leere Änderungsmenge führen zum vollen Lauf, jeweils mit eigener Meldung. Kein Pfad liest einen Fehler als Skip.
- **F3 bricht die Messung, nicht den Input:** Ein `git`-Stub im `PATH` lässt jeden der drei Schritte einzeln scheitern
  und prüft die schrittspezifische Meldung sowie die Abwesenheit der Skip-Meldung. Das setzt die Lesson
  nothra/tch-gastro-services#319 direkt um. Das Stub-Muster für den committeten Diff (`--no-renames [0-9a-f]*HEAD`) trifft
  den Working-Tree-Aufruf nachweislich nicht.
- **NUL-getrennt von Anfang bis Ende** (`-z` bei allen drei Quellen, `read -d ''`). F4 deckt Leerzeichen und Zeilenumbruch
  im Pfad ab. Die F5-Muster mit Schrägstrich sind gegen beide Präfix-Varianten getestet.
- **Exit-Code per `exec` durchgereicht** und mit Rot (Exit 3) und Grün belegt (AK2). Der Wrapper braucht keinen eigenen
  Exit-Pfad nach der Suite.
- **AK7 eingehalten:** `ownership-check.sh --list factory` listet keine der geänderten Dateien. `OWNERSHIP.md`,
  `PROJECT-CONTEXT.md`, `factory.config.yml` und `scripts/project/**` sind Seite `project`. Die neue Datei ist durch den
  bestehenden Glob `scripts/project/**` gedeckt (AK8), und die Beschreibung der Zeile wurde nachgezogen.
- **Mitzuziehende Stellen vollständig:** Pin-Test `#431 AK-H1`, der Config-Kommentar und der `PROJECT-CONTEXT.md`-Build-Block
  sind aktualisiert. `commands.coverage` bleibt bewusst die volle Suite. Die Aussage im Kopfkommentar „`factory-self-test`
  führt die Suite immer aus“ ist geprüft: `factory-ci.yml` triggert auf jedes `pull_request` ohne Pfadfilter, der Job hat
  kein `if:`, und ADR-029 führt ihn als Required Check.
- **Tests nutzen die vorhandenen Helfer** (`mk_feature_repo`, `assert_contains_286`, `assert_absent`, `skip_yq`) und bauen
  keinen Scaffold parallel auf. Fixture-Commits laufen mit expliziter Git-Identität (Lesson nothra/tch-gastro-services#265).
- **Architektur-Entscheidung tragfähig:** Option A (Projekt-Wrapper als `commands.test`) deckt beide Aufrufer mit einer
  Regel ab und lässt ausgelieferte Dateien unberührt. Die Begründung „kein ADR“ ist nachvollziehbar dokumentiert.

## Empfehlung
NEEDS_REWORK
