# Review: Task 24

Review-Iteration 5. Diff-Basis: `git diff origin/main...HEAD` (37d31c3). Spec:
`docs/specs/spec-24-factory-update-workflow-update-pr.md`, Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30
(E10–E16). Drei Runden (Logik, Code-Qualität, Architektur) liefen im Orchestrator-Kontext, ohne Fork-Delegation.

**Circuit Breaker:** Diese Runde prüft das Rework aus Iteration 4, also das Delta `a90e82a..HEAD` (Hook-Abschaltung
per `git_nohooks`). Dieser Code wird zum zweiten Mal reviewt, nicht zum dritten. Eine Eskalation ist nicht nötig.

Lokal: Die ausgelieferte Suite `scripts/checks/tests/run-tests.sh` läuft mit 2137 grün / 0 rot. Gegenüber Iteration 4
sind sechs Assertions hinzugekommen, nämlich die Hook-Tests und ihr Mutationsbeleg.

## Kritische Findings (müssen behoben werden)
_(keine)_

## Wichtige Findings (sollten behoben werden)
_(keine)_

Das Finding aus Iteration 4 (Hooks sehen das Token) ist behoben:
- `git_nohooks` (`scripts/factory-update.sh:53`) setzt `-c core.hooksPath=/dev/null` und schaltet damit alle Hook-Typen
  ab, nicht nur die, die `--no-verify` erfasst. Es umschließt alle git-Aufrufe, die Hooks auslösen können: Checkout
  (Z. 147), Rückkehr im `cleanup` (Z. 46), Commit (Z. 151) sowie Fetch und Push über `git_with_token` (Z. 54).
  Die übrigen git-Aufrufe (`status`, `add`, `rev-parse`, `show`, `symbolic-ref`) lösen keine Hooks aus.
- Der Test hängt protokollierende Hooks für fünf Typen per `core.hooksPath` an C1 und prüft drei Dinge: Der Update-PR
  entsteht, kein Hook sieht ein Token, kein Hook läuft. Der Mutationsbeleg nutzt dieselbe Guard-Funktion
  `hooks_saw_no_token_24` und ankert daran, dass genau die eine Abschaltung entfernt ist. Eine Positivkontrolle belegt,
  dass `pre-push` im Mutanten das Token tatsächlich sah (Lessons Factory-Task #23, nothra/tch-gastro-services#286).
- ADR-063 E12, der Skriptkopf (Z. 18-19) und der WHY-Kommentar (Z. 51-52) sind nachgezogen und stimmen mit dem Code
  überein. Spec und `OPERATING.md` enthalten keine Hook-Aussage, die mitgepflegt werden müsste.

## Nitpicks (optional)
- [ ] [Arbeitsbaum, nicht im Diff] Im Worktree liegen weiterhin gitignorete Wegwerf-Sonden: `scripts/lock24.tmp.sh`,
  `scripts/review24-self.tmp.sh`, `scripts/review24-seen.tmp.sh` sowie `tasks/telemetry-raw-24-*.tmp.txt`. Sie landen
  nicht im PR. Vor dem nächsten Suite-Lauf bzw. vor `/security-review` sollten sie manuell gelöscht werden (Lessons
  nothra/tch-gastro-services#372, #312).

## Positives
- Der Fix ist minimal: eine Wrapper-Funktion, auf die vier Aufrufstellen umgestellt sind, ohne parallele Varianten.
  `git_with_token` baut auf `git_nohooks` auf, statt die Option zu duplizieren.
- Der Kommentar nennt beide Gründe, nämlich dass ein Token in fremdem Code sichtbar wäre und dass ein rotes Gate den
  Push für F1 verhindern würde. Das ist die richtige WHY-Ebene.
- Der Test setzt den Hook per `core.hooksPath` in der Konfiguration von C1. Damit bildet er den härtesten Fall ab, eine
  bereits gesetzte Pfad-Option, und nicht nur `.git/hooks`. Er belegt zugleich, dass `-c` sie übersteuert.
- Der bestehende Mutationsbeleg zur Rückkehr auf `ORIG_REF` wurde auf die neue Aufrufzeile nachgezogen. Der Anker ist
  die volle Aufrufzeile und kein Fragment (Lesson nothra/tch-gastro-services#114/#310).

## Empfehlung
APPROVED
