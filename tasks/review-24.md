# Review: Task 24

Review-Iteration 6. Diff-Basis: `git diff origin/main...HEAD` (ccd0a2c). Spec:
`docs/specs/spec-24-factory-update-workflow-update-pr.md`, Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30
(E10–E16). Drei Runden (Logik, Code-Qualität, Architektur) liefen im Orchestrator-Kontext, ohne Fork-Delegation.

**Circuit Breaker:** Iteration 5 war APPROVED. Diese Runde prüft nur das Delta `67e41df..HEAD`: den Pagination-Test aus
`/test` (`6a38669`) und den Doku-Fix aus dem zweiten Security-Durchgang (`01f00ba`, Kommentar `factory-update.sh:148-150`,
ADR-063 E4/E12). Dieser Code wird zum ersten Mal reviewt. Eine Eskalation ist nicht nötig.

Lokal laufen beide Suiten grün: die ausgelieferte Suite `scripts/checks/tests/run-tests.sh` mit 2142 / 0 und die
Projekt-Suite `scripts/project/tests/run-tests.sh` mit 145 / 0.

## Kritische Findings (müssen behoben werden)
_(keine)_

## Wichtige Findings (sollten behoben werden)
_(keine)_

Geprüft:
- **Pagination-Test** (`factory-lock-tests.sh:668-686`): Der Stub liefert zwei getrennte Arrays hintereinander. Das ist
  die Form, die `gh api --paginate` ohne `--slurp` ausgibt. Das Skript liest sie per `jq -s` und führt sie mit `add` in
  `CANDIDATES_JQ` (`factory-update.sh:81`) zusammen. Die Voraussetzung ist eigens belegt (`jq -s 'length' = 2`). Der
  Mutant `.[0]` liest nur Seite 1 und ist damit die passende Gegenhypothese. Der Anker ist die volle Zeile `^  add$`,
  und es wird geprüft, dass sie genau einmal vorkommt. Original und Mutant laufen gegen dieselbe Guard-Funktion
  `paged_ok_24` (Lesson Factory-Task #23).
- **Doku-Fix:** Kommentar, E4 und E12 beanspruchen keine Grenze mehr. Die drei genannten Wege stimmen mit dem Code
  überein. Erstens läuft `git add -A` (`factory-update.sh:152`) ohne `git_nohooks` mit dem Token in der Umgebung, und
  `core.fsmonitor` ist kein Hook, also wirkt `core.hooksPath=/dev/null` nicht darauf. Zweitens hatte der Elternprozess das
  Token schon beim `exec`. Drittens laufen Workflows auf einem PR aus demselben Repo mit Repo-Secrets. Issue #37
  existiert, ist offen und trägt `enhancement` und `security` (Lesson Factory-Task #22: Issue vor dem Verweis).
- Drift-Grep (`nie sehen`, `ohne Token`, `tokenfrei`) über `docs/`, das Skript und `.github/` hat keine verbliebene absolute
  Aussage über Release-Code gefunden. Der Skriptkopf (Z. 16-19) behauptet nur, was für Hooks und argv gilt.

## Nitpicks (optional)
- [ ] [scripts/checks/tests/factory-lock-tests.sh:684] Der Mutantenlauf verwirft Ausgabe und Exit-Code. Rot wird nur der
  Guard. Würde der Mutant aus einem anderen Grund scheitern, etwa an einem kaputten Scaffold, wäre der Guard aus dem
  falschen Grund ebenfalls rot. Abhilfe: zusätzlich Exit 0 und den Hinweis „keine neuere Version“ des Mutanten prüfen
  (Lesson Factory-Task #23, zweigspezifisches Signal). Das Risiko ist gering, weil `sed` genau eine Zeile durch gültiges
  jq ersetzt.
- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:504] Die neue Zeile in E4 ist deutlich länger als
  die umgebenden Zeilen, der Umbruch passt nicht zum Rest des Absatzes. Das ist rein kosmetisch.
- [ ] [Arbeitsbaum, nicht im Diff] Noch vorhanden sind die gitignoreten Dateien `tasks/telemetry-raw-24-*.tmp.txt`. Die
  Sonden `scripts/*.tmp.sh` sind inzwischen gelöscht.

## Positives
- Der Pagination-Test schließt eine echte Lücke. `add` war bisher nur mit einem einzigen Array belegt und damit von
  `.[0]` nicht zu unterscheiden. Der Test zeigt außerdem, dass die Validierung (`all(.[]; type == "array")`) mehrseitige
  Antworten akzeptiert.
- Der Security-Fix ändert nur die Prosa und lässt den Code unverändert. Er sagt ehrlich, wogegen `env -u` schützt und
  wogegen nicht. Die strukturelle Härtung ist als Issue verankert und nicht als offenes Versprechen formuliert.
- Ein Kommentar und zwei ADR-Stellen sind im selben Commit konsistent nachgezogen (Lesson nothra/tch-gastro-services#264).

## Empfehlung
APPROVED
