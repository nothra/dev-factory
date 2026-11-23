# Security Review: Task 61

> Geprüft am 2026-11-22 gegen `git diff origin/main...HEAD` (13 Dateien). Der Diff ändert nur Test-Helfer, die Test-Suiten,
> Doku und Task-Dateien. Produktiv-Skripte sind nicht betroffen.

## Kritische Findings (Blocker)

Keine.

## Wichtige Findings

- [ ] [Security-Gate fail-open, Out-of-Scope] `scripts/checks/pre-commit.sh:27,35,51` prüft Konfliktmarker,
  Debug-Statements und hartkodierte Credentials per `git diff --cached | grep -qE …` unter `set -euo pipefail`.
  Bei großem Staged-Diff und frühem Treffer stirbt `git diff` an SIGPIPE, die `if`-Bedingung wird falsch, und der Commit
  geht **trotz Treffer durch**. Betroffen ist auch die Secret-Prüfung (Check 4). Der Hook ist ohnehin umgehbar
  (`--no-verify`), aber ein stilles Durchlassen ist schlimmer als ein bewusstes Umgehen. Der Fehler stammt nicht aus
  diesem PR, er wurde hier nur gefunden.
  **Schwelle (Factory-ADR-043):** echtes Sicherheitsrisiko → Schritt A, Issue mit `bug` + `security`.
  **Status:** Die Sandbox hat `create_issue_idempotent` erneut abgelehnt (`'.' evaluates arguments as shell code`).
  Eine Suche nach einem bestehenden Issue (`gh issue list --search "pre-commit SIGPIPE"`) war leer.
  **Ein Mensch muss das Issue vor dem Merge anlegen**, z. B.:

  ```bash
  . scripts/lib/create-issue.sh
  create_issue_idempotent "Pre-Commit-Prüfungen gegen SIGPIPE-Race bei git diff | grep -q absichern" \
    "<Kontext aus diesem Finding>" bug "security"
  ```

  Empfohlene Lösung: den Diff einmal in eine Variable lesen und per Here-String prüfen (`grep -qE … <<< "$staged_diff"`)
  oder `grep -E … >/dev/null` (liest bis EOF). Test: großer Staged-Diff mit Treffer in Zeile 1 → Commit abgelehnt.
  Gleiches Muster, unkritischer: `scripts/factory-update.sh:77`, `scripts/start-work.sh:310`.

## Hinweise

- [x] [Injection] `grep_in` reicht die Argumente als `"$@"` an `grep` weiter, ohne `eval` oder Word-Splitting. Der Haystack
  geht als Daten über den Here-String, nie als Code. Alle `grep_in`-Aufrufe im Diff quoten den Haystack (Ausnahmen sind nur
  ein Literal `'#…'` und ein Kommentar). Kein `eval` neu, keine Aufrufe mit verklebtem Optionswort (`grep_in "$x"-qF`).
  `assert_contains_286`/`assert_absent` behalten das `--` vor der Phrase (bash-gotchas § 20). Ein Test (AK3) belegt das.
- [x] [Fehlerbehandlung] `assert_absent` konnte vorher bei der Race falsch grün melden. Der Diff schließt das. Auch der
  Guard `pipe_grep_q_lines` ist fail-closed: eine fehlende oder nicht lesbare Eingabe oder keine Eingabe ergibt rot.
- [x] [Daten] Bash legt große Here-Strings als temporäre Datei in `$TMPDIR` ab und löscht sie sofort wieder. Der Inhalt
  sind Test-Ausgaben ohne Secrets. Kein Handlungsbedarf.
- [x] [Temp-Dateien] `TMP_61` entsteht per `mktemp -d` und wird am Ende des Blocks entfernt. Die Fixture-Pfade sind fest,
  keine fremden Eingaben.
- [x] [Secrets/Dependencies] Keine Credentials, keine neuen Dependencies, keine neuen Fremd-Binaries.
- [x] [Kleinfund] Den Eintrag für die Produktiv-Stellen mit kurzen Werten (`printf | grep -q` auf Tag/SHA/Slug) in
  `docs/factory/kleinfunde.md` halte ich für richtig eingestuft: Das Race ist bei einem Schreibvorgang mit wenigen Bytes
  praktisch nicht auslösbar. Kein Sicherheitsrisiko.

## Ergebnis

PASSED – kein Blocker in diesem PR. Offen ist nur das Issue für `pre-commit.sh` (siehe oben), das ein Mensch vor dem Merge anlegen muss.
