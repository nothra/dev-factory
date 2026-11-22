# Task 61: sigpipe-flake-printf-grep

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
SIGPIPE-Race `printf … | grep -q` unter `pipefail` in den Self-Test-Suiten beseitigen: Helfer `assert_contains_286` /
`assert_absent` robust machen, alle Fundstellen in `scripts/checks/tests/**` und `scripts/project/tests/**` umstellen,
Guard gegen Wiedereinführung. Schließt #15 ein (gleiche Ursache über `assert_contains_286`).
Spec: [`docs/specs/spec-61-sigpipe-flake-printf-grep.md`](../docs/specs/spec-61-sigpipe-flake-printf-grep.md)
PR-Body: `Closes #61`, `Closes #15`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [x] AK1 – `assert_contains_286` robust: ≥1-MB-Haystack, Phrase in Zeile 1, 200× unter `pipefail` → immer grün, kein `Broken pipe`
- [x] AK2 – `assert_absent` ohne Falsch-Grün: Phrase vorhanden → 200× rot; Phrase fehlt → grün
- [x] AK3 – Helfer-Semantik unverändert: `-`-Phrase und Regex-Zeichen als fester Text; leerer Haystack → `assert_contains_286` rot
- [x] AK4 – Guard: Pipe aus `printf`/`echo` in `grep -q…` unter `scripts/checks/tests/`, `scripts/project/tests/` → rot mit Datei:Zeile
- [x] AK5 – Guard-Mutationsbeleg: Muster rot; Here-String / `grep … <datei>` grün; Kommentarzeilen lösen nicht aus
- [x] AK6 – Bestand sauber: Guard findet nichts; Haupt- und Projekt-Suite grün; Assertion-Zahl vor/nach im PR genannt
- [ ] AK7 – CI-Beleg #61: `factory-self-test` 10× grün, kein `Broken pipe`, Lauf-Links im PR-Body
- [ ] AK8 – #15 abgedeckt: Test „#334 (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig …“ in allen Läufen grün
- [x] AK9 – Lesson `lessons/testing.md` verweist auf den Guard, kein Widerspruch zum neuen Helfer-Verhalten
- [ ] Produktiv-Fundstellen (nicht im Scope) als `kleinfunde.md`-Eintrag bzw. Issue nach Schwelle Factory-ADR-043
  (Kleinfund-Eintrag erledigt; Issue für `pre-commit.sh` steht aus, siehe Technische Notizen)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
- ADR-Trigger-Check (/implement, 2026-11-22): keine der vier Kategorien – Test-Helfer und Guard, keine Architektur-Entscheidung.
- **Helfer:** neuer `grep_in <haystack> <grep-args…>` in `lib/assert-helpers.sh` (Here-String statt Pipe);
  `assert_contains_286`/`assert_absent` nutzen ihn. Umstellung mechanisch als Präfix-Ersetzung
  `printf '%s' "$X" | grep ARGS` → `grep_in "$X" ARGS` (Grep-Argumente unverändert), andere Produzenten als
  `grep_in "$(produzent)" ARGS`. Umgestellt wurden `grep -q…`-Zeilen; Pipes in `grep -c/-n/-v` bleiben (lesen bis EOF).
  Ausnahme: die Seam-Zeile `n_labels=$(grep_in "$(tail -n1 "$LOG")" -oE …)` (ein `grep -o`) wurde mit umgestellt.
  Das ist harmlos und semantisch gleich, deshalb bleibt sie so.
- **Guard-Breite (Spec-Fehlerszenario „zu eng“):** `pipe_grep_q_lines` erfasst **jeden** Produzenten vor `grep -q`,
  nicht nur `printf`/`echo` – SIGPIPE trifft jeden, und jede Fundstelle lässt sich ohne Verlust auf `grep_in` umstellen,
  das Fehlalarmrisiko ist also gering. Ausgenommen: Kommentarzeilen, `||`, `grep` ohne `-q`/`--quiet`/`--silent`.
- **Guard nach Review-Iteration 1:** erkennt zusätzlich `|&`, Env-Präfixe (`LC_ALL=C grep`), `command grep` und
  beliebige Wörter vor dem `-q` (`-m1`, `-e x -q`); das Pipe-Ziel endet an `|`, `;`, `&`, `)`. Er ist jetzt fail-closed:
  eine nicht lesbare oder fehlende Eingabe ergibt rot mit Meldung. Die Rest-Fundstelle `run-tests.sh` (#319 S3,
  `LC_ALL=C grep -q`) ist auf `LC_ALL=C grep_in` umgestellt. Bewusst nicht erkannt (im Helfer-Kommentar benannt):
  Zeilenfortsetzung und grep-Aufrufe über Variablen oder Funktionen.
  Assertions jetzt: Haupt-Suite 2775 grün (+9 Guard-Mutationsfälle, RED vorher: 8 rot), Projekt-Suite 250 grün.
- **Guard-Ort:** die ausgelieferte Suite prüft `scripts/checks/tests/` (plus Mutationsbelege), die Projekt-Suite
  `scripts/project/tests/` – so bleibt die ausgelieferte Suite konsumenten-neutral (Factory-ADR-064 D6).
- **Assertions vor/nach (AK6):** Haupt-Suite 2739 → 2766 grün (+27 neue #61-Assertions, keine entfernt), Projekt-Suite
  249 → 250 grün (+1 Guard). Lokal macOS, 2026-11-22; #15-Test („#334 (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig …“) grün.
- **RED-Nachweis:** Ein isolierter Lauf nur der AK1/AK2-Tests gegen den alten Pipe-Helfer war in der Session nicht
  möglich. Die Tests sind so gebaut, dass sie die Race erzwingen (1 MB, Nadel in Zeile 1, 200×). `/review` kann die
  Mutante (Helfer kurz auf `printf '%s' "$1" | grep -qF -- "$2"` zurück) als Beleg nachziehen.
- **Werkzeug-Falle beim Umstellen:** Massen-Ersetzungen, deren Ersatztext auf ein Leerzeichen endet, verloren das
  Leerzeichen (`grep_in "$x"-qF`). Das blieb meist grün, weil grep dann ohne `-q` druckte und trotzdem den richtigen
  Exit-Code lieferte. Rot wurden nur 12 Stellen. Behoben; eine Suche nach verklebten `grep_in`-Aufrufen ist leer.
- **Fund außerhalb der Spec-Liste (Issue-Kandidat, Schwelle „Funktionaler Defekt“):** `scripts/checks/pre-commit.sh:27,35,51`
  (`git diff --cached | grep -qE …` unter `set -euo pipefail`) – bei großem Staged-Diff und frühem Treffer stirbt
  `git diff` an SIGPIPE, die `if`-Bedingung wird falsch, und die Konfliktmarker-/Debug-/Secret-Prüfung lässt den Commit
  **durch** (fail-open). Ähnlich, aber unkritischer: `scripts/factory-update.sh:77` (`env | grep -qE`),
  `scripts/start-work.sh:310` (`git worktree list | grep -qxF`). Nicht in diesem PR (Produktiv-Skripte außerhalb des
  Scopes); Issue-Anlage steht aus.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
- Keine fachlichen. Kein ADR-Trigger erwartet (`/architecture` entfällt).
- Entscheidungen Mensch 2026-11-22: #15 im Scope; Guard ja; CI-Beleg per 10 Job-Läufen; Produktiv-Skripte nicht im Scope.

## Review-Findings
<!-- Wird durch /review befüllt -->
- Iteration 1 (2026-11-22): **NEEDS_REWORK**, Details in [`review-61.md`](review-61.md). 1 kritisch (Rest-Fundstelle
  `run-tests.sh:7403` mit `LC_ALL=C grep -q`, Guard übersieht Env-Präfix), 3 wichtig (Guard fail-open bei fehlender Datei,
  Guard-Lücken `-m1`/`-e x -q`/`|&`, Issue für `pre-commit.sh` noch nicht angelegt), 3 Nitpicks.
- Rework zu Iteration 1 (2026-11-22, /implement): kritisch + 2 wichtige behoben, 3 Nitpicks erledigt (Notiz zu
  `n_labels` angepasst, Grenzen im Guard-Kommentar, Lesson-Satz geteilt). **Offen:** Das Issue für `pre-commit.sh`
  (Labels `bug` + `security`) muss ein Mensch anlegen oder freigeben.

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/61-sigpipe-flake-printf-grep`
Erstellt: 2026-11-22 13:51
