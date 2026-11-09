# Review: Task 51

> Stand: `f1e1bbb` gegen `origin/main`, 2026-11-09 – **Iteration 2** (nach Rework 1). Alle drei Runden (Logik,
> Code-Qualität, Architektur) liefen direkt im Orchestrator-Kontext; bei einem Rework-Diff von ~30 Zeilen lohnte die
> Fork-Delegation nicht (vgl. Lessons nothra/tch-gastro-services#298/#267). Projekt-Suite lokal: 197 grün, 0 rot.
> `git status --ignored`: nur die gitignorete Telemetrie-Rohdatei `tasks/telemetry-raw-51-*.tmp.txt`, kein
> Scratch-Artefakt im Baum.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_

Das wichtige Finding aus Iteration 1 (Wrapper im pre-push-Hook eines Worktrees nicht als Verhalten getestet) ist behoben.
`scripts/project/tests/run-tests.sh:774-796` setzt ein Bare-Remote und `git worktree add` auf und installiert einen
Einzeiler-Hook über `core.hooksPath`. Danach pusht der Test echt aus dem Worktree:
(a) ein reiner Task-Commit führt zum Skip, die Suite startet nicht, Exit 0;
(b) eine untracked Datei außerhalb führt zum vollen Lauf mit dem Grund `neu-wt.txt`. Damit ist der eigentliche
Anwendungsfall (erster Push nach `/requirements` aus dem Task-Worktree) in beiden Richtungen belegt. Laut Task-Datei
macht ein Mutant `[ -d "$ROOT/.git" ]` nur die neuen Assertions rot. Das bestätigt, dass der Test die
Worktree-Eigenheit (`.git` ist eine Datei) wirklich erreicht.

## Nitpicks (optional)

- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:182] Unverändert aus Iteration 1, bewusst offen.
  D9 nennt `commands.test` = `run-tests.sh`, der Stand ist nach diesem PR überholt. Die Datei gehört der Seite `factory`
  und liegt damit außerhalb von AK7. Auch `docs/factory/kleinfunde.md` ist Seite `factory`. Doku-Drift unterhalb der
  Schwelle (Factory-ADR-043): mitnehmen, wenn ADR-063 ohnehin angefasst wird.
- [ ] [scripts/project/tests/run-tests.sh:793] Der zweite Worktree-Push prüft weder den Exit-Code noch, ob der Push
  gelingt. Da der Suite-Stub Exit 0 liefert, ist das Ergebnis vorhersehbar. Ein `assert_exit 0` würde die Symmetrie zu
  Fall (a) herstellen. Kein Verhaltensrisiko.

Erledigt aus Iteration 1: F1/F3-Grund assertiert (`run-tests.sh:723`), Grenze „HEAD statt gepushte Refs“ im
Kopfkommentar (`factory-suite-gate.sh:21-22`), `main "$@"` → `main` (`factory-suite-gate.sh:84`).

## Positives

- **Rework zielgenau:** Der neue Test folgt dem Vorschlag aus Iteration 1. Der Einzeiler-Hook prüft den
  Git-Hook-Kontext, nicht `pre-push.sh`, und das Bare-Remote liefert ein echtes `origin/main` statt `update-ref`.
  Zusätzlich ist der Mutationsbeleg in der Task-Datei dokumentiert, einschließlich des überlebenden Mutanten
  `--git-dir="$ROOT/.git"` und der Begründung, warum er kein Bruch ist.
- **Test-Hygiene:** `push_51` wird nach Gebrauch per `unset -f` entfernt, das Wegwerf-Verzeichnis gelöscht. Der
  Override wird per `env -u` aus dem Push-Kontext genommen, damit eine exportierte Variable der aufrufenden Shell den
  Test nicht verfälscht (vgl. Lesson nothra/tch-gastro-services#262). Fixture-Commits laufen mit expliziter Identität.
- **Bestehende Helfer wiederverwendet** (`mk_gate_repo_51`, `commit_51`, `SKIP_MSG_51`, `assert_*`), kein paralleler
  Scaffold.
- Alle Stärken aus Iteration 1 bleiben bestehen: fail-closed auf jedem Pfad mit eigener Meldung, NUL-Trennung von
  Anfang bis Ende, F3 bricht die Messung per `git`-Stub, Exit-Code per `exec`, AK7 eingehalten (nur Seite `project`
  geändert), Mitzieh-Stellen vollständig.

## Empfehlung
APPROVED
