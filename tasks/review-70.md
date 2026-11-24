# Review: Task 70

Diff `origin/main...HEAD` (5 Dateien, +284/−4): `scripts/checks/pre-commit.sh`, Testblock #70 in
`scripts/checks/tests/run-tests.sh`, Kleinfund in `docs/factory/kleinfunde.md`, Spec, Task-Datei.

## Kritische Findings (müssen behoben werden)

_Keine._

## Wichtige Findings (sollten behoben werden)

- [ ] [CHANGELOG.md:6] Unter `## Unreleased` fehlt der Eintrag für den Fix. `pre-commit.sh` wird ausgeliefert (Seite
  `factory`), und Konsumenten merken die Änderung: Ein großer Staged-Diff mit Konfliktmarker, Debug-Statement oder
  Credential blockiert jetzt den Commit. Zuvor ging er durch (fail-open). Neu ist auch die Meldung „Staged-Diff nicht
  lesbar … – commit blockiert“. Die Spec kündigt den Patch-Release v0.8.1 an. Die übrigen Konsumenten-PRs (#41, #66,
  #62) haben ihren Eintrag jeweils im selben PR angelegt, und das Release setzt einen CHANGELOG-Abschnitt voraus
  (Factory-ADR-063 D6). Vorschlag: einen Abschnitt `### Behoben` mit einem Satz zum Fehlerbild und dem Hinweis „für
  Konsumenten nichts zu tun“.

## Nitpicks (optional)

- [ ] [docs/factory/kleinfunde.md:327] Im bestehenden #61-Eintrag steht noch „Der Guard `pipe_grep_q_lines` gilt nur
  für die Test-Suiten“. Seit #70 (AK8) läuft er auch über `scripts/checks/pre-commit.sh`. Den Halbsatz ergänzen, sonst
  driftet der Eintrag.
- [ ] [scripts/checks/tests/run-tests.sh:9690] Für das Spec-Fehlerszenario „Zeilen, die mit `-` beginnen“ gibt es
  keine eigene Assertion. Es ist nur mittelbar abgedeckt, über die Kopfzeile `--- /dev/null` in jedem Diff einer neuen
  Datei. Ein Kommentar dazu würde genügen, ein eigener Fall wäre nicht nötig.
- [ ] [scripts/checks/tests/run-tests.sh:9696] Der Binärdatei-Fall prüft nur Exit 0. Das genügt (ein Treffer ergäbe
  Exit 1), aber ein `assert_contains_286 … "Keine Merge-Konflikte"` wie im Fall „leerer Diff“ wäre symmetrisch.

## Positives

- **Der Fix ist minimal und trifft die Ursache:** Der Diff wird einmal gelesen, alle vier Checks lesen per
  Here-String. Die Meldungstexte sind wortgleich (AK9), der Diff ändert nur die `if`-Bedingungen.
- **Fail-closed ist explizit:** `if ! STAGED_DIFF="$(git diff --cached)"` mit eigener Meldung statt eines stummen
  `set -e`-Abbruchs. Der Nutzer sieht den Grund. AK7 belegt das mit einem git-Stub, der nur `diff --cached` scheitern
  lässt.
- **`debugger[;]`:** Die Regex bleibt semantisch gleich, und die Zeile trifft sich als Diff-Zeile nicht mehr selbst.
  Ein Kommentar begründet das. Das passt zur Spec-Regel „Trigger-Strings nie wörtlich“, ebenso wie die zur Laufzeit
  zusammengesetzten Fixtures im Test.
- **Die Tests messen das Gate, nicht `grep`:** Exit-Code und Meldung von `pre-commit.sh` in einem Wegwerf-Repo. Die
  Vorbedingung ≥ 1 MiB ist als eigene Assertion abgesichert. Der Mutationsbeleg AK4 ist mit Kommando und Ergebnis in
  der Task-Datei notiert (11 rote Assertions gegen `main`, genau die von #70).
- **Guard AK8 mit eigener Mutation:** Eine eingeschleuste Pipe in eine Kopie von `pre-commit.sh` macht den Guard rot.
  Der Guard ist also nicht vakuös grün.
- **Scope eingehalten:** Check 3 (`awk`) nutzt dieselbe Quelle, sein Verhalten ändert sich nicht. Die beiden
  ähnlichen Stellen sind schwellenkonform als Kleinfund vermerkt, die Fundstellen sind verifiziert. `ownership-check`
  ist grün (243 Dateien), es gibt keine projektspezifischen Begriffe, ein ADR ist zu Recht entbehrlich.

## Verifikation

- `bash scripts/checks/tests/run-tests.sh` → `Ergebnis: 2801 grün, 0 rot`. Alle #70-Assertions sind grün (AK1–AK3,
  AK5–AK8, leerer Diff, Binärdatei, Vorbedingung 1122137 Byte), ebenso die bestehenden pre-commit-Tests (AK9).

## Empfehlung

APPROVED (das wichtige Finding zum CHANGELOG-Eintrag vor dem Merge nachziehen; es ist kein Rework am Code)
