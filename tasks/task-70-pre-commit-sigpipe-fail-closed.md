# Task 70: pre-commit-sigpipe-fail-closed

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
`scripts/checks/pre-commit.sh` prüft Konfliktmarker, Debug-Statements und Credentials per
`git diff --cached | grep -qE …` unter `set -euo pipefail`. Bei großem Staged-Diff und frühem Treffer stirbt
`git diff` an SIGPIPE, die `if`-Bedingung wird falsch und der Commit geht durch (fail-open). Umstellung auf einmal
gelesenen Diff + Here-String/Datei, fail-closed beim Lesefehler, Regressionstests mit Mutationsbeleg, Guard.

Spec: [`docs/specs/spec-70-pre-commit-sigpipe-fail-closed.md`](../docs/specs/spec-70-pre-commit-sigpipe-fail-closed.md)

## Akzeptanzkriterien
- [ ] AK1: großer Diff (≥ 1 MiB), Konfliktmarker in erster Zeile → `pre-commit.sh` Exit 1 + Meldung
- [ ] AK2: großer Diff, Debug-Statement in erster Zeile → Exit 1 + Meldung
- [ ] AK3: großer Diff, Credential in erster Zeile → Exit 1 + Meldung
- [ ] AK4: Mutationsbeleg – AK1–AK3 gegen die alte Pipe-Fassung rot (Kommando + Ergebnis hier notiert)
- [ ] AK5: großer Diff ohne Treffer → Exit 0, Checks 1/2/4 „✓"
- [ ] AK6: großer Diff, Treffer nur in letzter Zeile (je Check) → Exit 1 + Meldung
- [ ] AK7: `git diff --cached` schlägt fehl → Exit ≠ 0, kein „✓" für Checks 1/2/4
- [ ] AK8: Guard `pipe_grep_q_lines scripts/checks/pre-commit.sh` ohne Fund; Mutation macht ihn rot
- [ ] AK9: bestehende pre-commit-Tests unverändert grün, Meldungstexte wortgleich
- [ ] Kleinfund `factory-update.sh:77` / `start-work.sh:310` in `kleinfunde.md` vermerkt

## Technische Notizen
Kein ADR nötig (`/architecture` entfällt): Anwendung der bestehenden Regel bash-gotchas §3 / Lesson #61.
Muster: `staged_diff="$(git diff --cached)"` einmal oben, dann `grep -qE … <<< "$staged_diff"`.

## Offene Fragen
Keine.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/70-pre-commit-sigpipe-fail-closed`
Erstellt: 2026-11-24 11:41
