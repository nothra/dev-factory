## Codify-Report: Task 51

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` + Index-Zeile in `PROJECT-CONTEXT.md` – Git-nutzendes Gate im Hook braucht einen
  echten Push-Test aus einem Worktree (wegen Review-Finding W1: Wegwerf-Repos mit `update-ref` deckten `.git`-als-Datei
  und exportierte `GIT_*`-Variablen nicht ab).
- `docs/factory/kleinfunde.md` – ADR-063 D9 nennt `commands.test` noch ohne Wrapper (unterhalb der Schwelle, Seite `factory`).

### Keine Änderungen nötig
Security-Review: keine Findings. Mutationsbelege, Fail-closed-Messbruch per `git`-Stub und Helfer-Wiederverwendung
folgten bereits bestehenden Lessons – kein Rezidiv.

### Empfehlung für nächste Features
ADR-063 D9 mitnehmen, sobald die ADR ohnehin angefasst wird.
