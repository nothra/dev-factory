# Task 70: pre-commit-sigpipe-fail-closed

## Status
- [x] In Bearbeitung
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
- [x] AK1: großer Diff (≥ 1 MiB), Konfliktmarker in erster Zeile → `pre-commit.sh` Exit 1 + Meldung
- [x] AK2: großer Diff, Debug-Statement in erster Zeile → Exit 1 + Meldung
- [x] AK3: großer Diff, Credential in erster Zeile → Exit 1 + Meldung
- [x] AK4: Mutationsbeleg – AK1–AK3 gegen die alte Pipe-Fassung rot (Kommando + Ergebnis hier notiert)
- [x] AK5: großer Diff ohne Treffer → Exit 0, Checks 1/2/4 „✓"
- [x] AK6: großer Diff, Treffer nur in letzter Zeile (je Check) → Exit 1 + Meldung
- [x] AK7: `git diff --cached` schlägt fehl → Exit ≠ 0, kein „✓" für Checks 1/2/4
- [x] AK8: Guard `pipe_grep_q_lines scripts/checks/pre-commit.sh` ohne Fund; Mutation macht ihn rot
- [x] AK9: bestehende pre-commit-Tests unverändert grün, Meldungstexte wortgleich
- [x] Kleinfund `factory-update.sh:77` / `start-work.sh:310` in `kleinfunde.md` vermerkt

## Technische Notizen
Kein ADR nötig (`/architecture` entfällt): Anwendung der bestehenden Regel bash-gotchas §3 / Lesson #61.
Muster: `staged_diff="$(git diff --cached)"` einmal oben, dann `grep -qE … <<< "$staged_diff"`.

**Umsetzung (/implement, 2026-11-24):**
- `pre-commit.sh` liest `STAGED_DIFF="$(git diff --cached)"` einmal vor Check 1; Checks 1–4 (auch das `awk` von
  Check 3) lesen per Here-String. Lesefehler → eigene Meldung „Staged-Diff nicht lesbar … – commit blockiert" und
  `exit 1` vor jedem Check (expliziter `if !` statt stillem `set -e`-Abbruch, damit der Grund sichtbar ist).
  Variable statt Temp-Datei: kein Aufräum-Trap nötig, Diffgrößen eines Commits sind unkritisch.
- Tests: Block „Factory-Issue #70" in `scripts/checks/tests/run-tests.sh` (Wegwerf-Repo mit Kopie von `pre-commit.sh`
  + `gate-config.sh`, ohne Integritäts-Check, damit AK5 auch in Konsumenten Exit 0 sieht). Trigger werden zur
  Laufzeit zusammengesetzt. Zusätzlich die Fehlerszenarien leerer Diff und Binärdatei.
- Die bestehenden Meldungstexte sind wortgleich (AK9): der Diff ändert nur die `if`-Bedingungen.

**Mutationsbeleg AK4 (2026-11-24):** Tests vor dem Fix gegen die unveränderte Pipe-Fassung (`main`) laufen lassen –
`bash scripts/checks/tests/run-tests.sh` → `Ergebnis: 2790 grün, 11 rot`. Rot waren genau die #70-Assertions:
AK1/AK2/AK3 je „Exit 1 (erwartet exit=1, war 0)" + fehlende Meldung, AK7 (Exit 0 und alle drei „✓"), AK8 (Guard-Fund
`pre-commit.sh:27`). AK5/AK6 waren schon vorher grün (erwartet: kein früher Treffer, also kein SIGPIPE).
Nach dem Fix: `Ergebnis: 2801 grün, 0 rot`.

## Offene Fragen
Keine.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/70-pre-commit-sigpipe-fail-closed`
Erstellt: 2026-11-24 11:41
