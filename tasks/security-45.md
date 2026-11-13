# Security Review: Task 45

Geprüfter Stand: `git diff origin/main...HEAD` (HEAD `20fad44`) plus der noch nicht angewendete
`tasks/patch-45.diff` (`.claude/commands/implement.md`, `review.md`, `codify.md`, `.gitignore`).

Angriffsfläche: Der PR ändert fast nur Anweisungstexte (Skills, Personas, Guidelines, Lessons) und
Kommentare. Ausführbarer Code kommt nur in der Projekt-Suite `scripts/project/tests/run-tests.sh`
dazu. Diese Suite läuft lokal im pre-push-Hook und in CI (`project-self-test`), wird aber nicht an
Konsumenten ausgeliefert.

## Kritische Findings (Blocker)

Keine.

## Wichtige Findings

Keine.

## Hinweise

- [ ] [Security Misconfiguration / Daten-Hygiene] `*.tmp.spec.tsx` fällt aus
  `docs/factory/gitignore.factory` (und per Patch aus `.gitignore`). Ein Konsument, der solche
  Wegwerf-Specs anlegt, hat sie nach dem Update ungetrackt und nicht ignoriert, und ein
  `git add -A` (z. B. `factory-commit.sh`) committet sie dann mit. Das ist kein echtes
  Sicherheitsrisiko: Wegwerf-Specs enthalten normalerweise keine Secrets, und Secret-Dateien
  (`.env*`) deckt weiter ein eigenes Muster ab. Die Lösung ist schon vorgesehen: Der
  Übergabe-Kommentar (AK16, Spec Z. 156) nennt `.gitignore.project` als Ziel für das Muster. Kein
  eigener Eintrag nötig, solange AK16 vor dem Merge gepostet wird.
- [ ] [Doku-Drift, keine Sicherheitsrelevanz] `docs/factory/lessons/build-tooling.md:32` behauptet
  weiter, `.gitignore` decke `*.tmp.spec.tsx` ab. Ist schon als Review-Nitpick (Iteration 2) bekannt
  und für `/codify` vorgemerkt, darum hier kein Kleinfund-Eintrag.

## Geprüft ohne Befund

- **Command Injection:** Die neuen Funktionen `c1_hits_in` und `stack_hits_45` übergeben
  Begriffe als feste Literale (`grep -F -e … --` bzw. `grep -E -- <konstante>`). Dateinamen
  kommen NUL-getrennt aus `git ls-files -z`, stehen immer in Anführungszeichen und laufen nie
  über `eval`. Seit `/refactor` gibt `awk -v file=` den Dateinamen aus, statt dass er in einem
  `sed`-Ausdruck steht. `awk -v` liest Backslashes darin als Escape-Sequenzen, das betrifft aber
  nur die Anzeige, nicht die Ausführung.
- **Fail-closed:** `stack_hits_45` gibt Exit 2 zurück, wenn keine Datei gefunden wird, die Wurzel
  falsch ist oder eine Datei nicht lesbar ist. Die fail-closed-Zählung im C1-Scan (`> 50` Dateien)
  bleibt erhalten. Es gibt also keinen Weg, auf dem der Guard still grün wird.
- **Temp-Dateien:** Sie werden per `mktemp`/`mktemp -d` angelegt und am Ende entfernt. Das
  `rm -rf` trifft nur diese beiden `mktemp`-Verzeichnisse und keine Pfade, die sich aus Variablen
  aus dem Repo-Inhalt ergeben.
- **`scripts/checks/pre-push.sh`:** Geändert sind nur Kommentarzeilen, es gibt keine geänderte
  Code-Zeile (per Diff-Filter geprüft). Das Gate-Verhalten ist unverändert.
- **Secrets/Credentials:** Im Diff und im Patch gibt es keine Treffer (Scan nach Key-, Token- und
  Passwort-Mustern).
- **Dependencies:** Keine neuen.
- **Anweisungstexte (Prompt-Fläche):** Die neuen generischen Formulierungen verweisen auf
  `CLAUDE.md`/`PROJECT-CONTEXT.md` des Projekts, also auf schon etablierte, vom Projekt selbst
  gepflegte Anpassungsstellen. Es kommt kein neuer Kanal dazu, über den Fremdinhalt als Anweisung
  in den Agentenkontext gelangt.
- **Review-Persona (Atomarität):** Die Prüffrage nach einer projektweiten Atomaritäts-Klammer
  bleibt als generische Frage erhalten. Die Prüftiefe für Datenintegrität sinkt nicht.

## Ergebnis
PASSED
