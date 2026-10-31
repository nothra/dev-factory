# Review: Task 24

Review-Iteration 4. Diff-Basis: `git diff origin/main...HEAD` (a90e82a). Spec:
`docs/specs/spec-24-factory-update-workflow-update-pr.md`, Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30
(E10–E16). Drei Runden (Logik, Code-Qualität, Architektur) liefen im Orchestrator-Kontext, ohne Fork-Delegation.

**Circuit Breaker:** Iteration 3 hat den Stand 3ad8017 freigegeben (APPROVED). Diese Runde prüft neuen Code, nämlich den
Security-Fix aa6ccbe/a90e82a und die `/test`-Ergänzungen 481f85d. Den Schwerpunkt bildet das Delta `27d9033..HEAD`.
Derselbe Code wird also nicht ein drittes Mal iteriert, eine Eskalation ist nicht nötig.

Lokal: Die ausgelieferte Suite `scripts/checks/tests/run-tests.sh` läuft mit 2131 grün / 0 rot. Gegenprobe zum Security-Test:
Eine Wegwerf-Sonde hat den Wrapper-Stub zusätzlich die Argumente protokollieren lassen. Das Protokoll zeigt genau zwei
Aufrufe, `v1.1.0` und `--compose --check`, und beide sind tokenfrei. Die Testbezeichnung „auch der Neustart“ ist damit belegt.

## Kritische Findings (müssen behoben werden)
_(keine)_

## Wichtige Findings (sollten behoben werden)
- [ ] [scripts/factory-update.sh:147-149] Commit und Push in `rebuild_branch` führen Git-Hooks aus dem **neu abgeholten**
  Release aus, und zwar mit `FACTORY_SYNC_TOKEN` in der Umgebung. Damit hält die neue Zusage im Kommentar (Z. 144-145,
  „Code eines noch ungeprüften Tags darf das schreibberechtigte PAT **nie** sehen“) und in ADR-063 E12 („Abholung ohne
  Token … Push und `gh` laufen erst danach mit dem Token“) nicht durchgängig.
  - **Ursache:** `install-hooks.sh:81-82` installiert `pre-commit` = `bash scripts/checks/pre-commit.sh` und `pre-push` =
    `bash scripts/checks/pre-push.sh`, jeweils relativ zum Arbeitsbaum. Nach `factory-sync.sh` sind das schon die Dateien
    des Release. `git commit` (Z. 147) läuft ohne `env -u`. `git_with_token push` (Z. 149) braucht das Token ohnehin in
    der Umgebung, weil der Credential-Helper es von dort liest, und der `pre-push`-Hook erbt diese Umgebung.
  - **Wo es greift:** Auf GitHub-gehosteten Runnern sind im frischen Checkout keine Hooks installiert, dort besteht keine
    Exposition. Sie besteht überall, wo im `.git` des Checkouts Hooks liegen: bei lokalen Läufen, bei Self-hosted-Runnern
    mit wiederverwendetem Workspace (`factory-ci.yml:110` ruft `install-hooks.sh` in CI auf) und bei gesetztem `core.hooksPath`.
  - **Funktionale Folge:** Lokal startet der `pre-push`-Hook die komplette Gate-Kette der neuen Fassung. Ein rotes Gate
    darin bricht den Push ab, obwohl F1 genau dafür den Update-PR vorsieht.
  - **Vorschlag (wenige Zeilen, im Scope des Security-Fixes):** Commit und Push ohne Hooks ausführen, etwa
    `git -c core.hooksPath=/dev/null …` im Commit und in `git_with_token`. Alternative: `--no-verify` an beiden Aufrufen.
    Das lässt aber andere Hook-Typen offen. Dazu ein Test: In der Welt wird vor dem Lauf ein `pre-commit`/`pre-push`-Hook
    nach `.git/hooks` von C1 gelegt, der protokolliert, ob `FACTORY_SYNC_TOKEN` gesetzt ist. Erwartung: nicht aufgerufen
    bzw. tokenfrei. Mutationsbeleg mit derselben Guard-Funktion ohne die `core.hooksPath`-Option. Lesson
    `code-style.md` („X erzwingt Y“ vor dem Schreiben am Enforcer prüfen) und Lesson aus Factory-Task #23
    (dieselbe Funktion auf Original und Mutante) beachten.

## Nitpicks (optional)
- [ ] [Arbeitsbaum, nicht im Diff] Aus diesem Review-Lauf liegen zwei gitignorete Wegwerf-Sonden im Worktree:
  `scripts/review24-self.tmp.sh` und `scripts/review24-seen.tmp.sh`. Die Freigabe für `rm` fehlte. Sie landen nicht im PR,
  gehören aber vor dem nächsten Suite-Lauf gelöscht (Lessons nothra/tch-gastro-services#372, #312). Die Altlasten aus
  Iteration 3 sind weg.

## Positives
- Der Security-Fix ist schmal und trifft die richtige Stelle. `env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN`
  wirkt nur auf die Abholung. Push und `gh` behalten das Token, und der WHY-Kommentar nennt den Grund (Selbst-Ersatz und
  Neustart in der Release-Fassung).
- Der Test misst das echte Verhalten: Ein Wrapper-Stub protokolliert die Umgebung je Aufruf, die Prüfung läuft
  zeilenweise und verlangt mindestens zwei Aufrufe, also auch den Neustart. Der Mutationsbeleg nutzt dieselbe
  Guard-Funktion `sync_saw_no_token_24` auf Original und Mutante (Lesson aus Factory-Task #23). Eine Positivkontrolle
  belegt, dass der Stub im Mutanten das Token tatsächlich sah, und ein Anker prüft, dass genau ein `env -u` entfernt ist.
- Die `/test`-Ergänzungen decken die bisher ungetesteten Fail-closed-Zweige ab: `gh` fehlt, Slug ungültig (vier
  Varianten), Fetch, PR-Listen offen/geschlossen, unsauberer Arbeitsbaum, `pr create`/`pr edit` scheitern. Jeder Zweig
  prüft Rot, die zweigspezifische Meldung und dass weder Push noch schreibender `gh`-Aufruf stattfand (Lesson Task #23).
  Für die Rückkehr auf den Ausgangs-Branch gibt es einen Mutationsbeleg, für das Scheitern von `pr create` einen
  Selbstheilungs-Folgelauf.
- Der Helfer `fail_closed_24` bündelt die wiederkehrende Assertion, statt sie inline zu kopieren (Lessons
  nothra/tch-gastro-services#267/#310).
- ADR-063 E4 ist ehrlich präzisiert: `--compose --check` läuft schon in der neuen Fassung. E12 trägt die tokenfreie
  Abholung als eigene Begründung. Auf die Hook-Lücke oben muss E12 nach dem Fix noch gezogen werden.

## Empfehlung
NEEDS_REWORK
