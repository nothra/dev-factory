# Security Review: Task 67

Geprüft: `git diff origin/main...HEAD`. Der Fix ist eine Zeile in `pipeline_summary()` (`scripts/run-pipeline.sh:606`):
`local task_file="$TASK_FILE"` statt eines neu gebauten `tasks/task-<id>.md`-Pfads. Dazu kommen ein Test in
`scripts/checks/tests/run-tests.sh` sowie Spec, Task- und Review-Datei.

## Kritische Findings (Blocker)
_Keine._

## Wichtige Findings
_Keine._

## Hinweise
- [x] [Input-Validierung / Command Injection] Der Diff baut keinen neuen Pfad aus Eingaben. `$TASK_FILE` wird einmal beim
  Pipeline-Start über `find … -name "task-${TASK_ID}-*.md"` aufgelöst und ist schon die Datei, die in die Skill-Prompts
  geht (`:456`). Das Summary liest jetzt dieselbe Datei, die Angriffsfläche bleibt also gleich. Im Summary wird der Pfad
  nur gequotet gelesen (`[ -f "$task_file" ]`, `grep -m1 … "$task_file"`), nichts davon wird ausgeführt oder per `eval` ausgewertet.
- [x] [Output / Terminal-Escape] Der Titel wird mit `echo` ohne `-e` ausgegeben, Backslash-Sequenzen werden also nicht
  interpretiert. Die Task-Datei liegt versioniert im Repo, das ist keine neue Vertrauensgrenze (Verhalten wie vorher).
- [x] [Test-Hygiene] Der Test arbeitet in einem eigenen `mktemp -d`-Verzeichnis und räumt es mit `rm -rf "$TMP_67"` auf
  (Variable gequotet, immer gesetzt). Die Git-Identität ist ein Wegwerf-Literal (`t@t.com`), es gibt keine Secrets und keine Netzwerkzugriffe.
- [x] [Dependencies] Keine neuen Abhängigkeiten.
- [x] [Out of Scope, schon vorher vorhanden] `TASK_ID` wird nicht auf Ziffern geprüft und geht als Glob in `find -name`.
  Das ist keine ausnutzbare Sicherheitsgrenze, nur eine Robustheitslücke: Es kann die falsche Task gewählt werden.
  Klassifiziert als Schritt B (Factory-ADR-043) und in `docs/factory/kleinfunde.md` eingetragen, ohne Issue.

## Ergebnis
PASSED
