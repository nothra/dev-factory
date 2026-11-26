## Codify-Report: Task 67

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + Index-Zeile in `docs/factory/lessons/INDEX.md` (Trigger `/implement`, `/review`, `/refactor`) –
  Abgeleiteten Pfad (`$TASK_FILE`) einmal beim Start auflösen und weiterreichen, statt ihn in einer zweiten Funktion aus ID/Muster neu zu bauen;
  bei Umbenennung einer Namenskonvention alle Pfad-Bauer per `grep` suchen; fail-open-Meldungen („nicht gefunden") testen –
  wegen: `pipeline_summary()` meldete seit der Slug-Umstellung in jedem Lauf „Task-Datei nicht gefunden", unbemerkt, weil fail-open.
- `docs/factory/kleinfunde.md` (Schritt B, unter der Schwelle) – `run-pipeline.sh` prüft die Task-ID nicht auf Ziffern (Fund aus `/security-review`, keine Sicherheitsgrenze).

### Keine Änderungen nötig
CLAUDE.md und Guidelines bleiben unverändert: das Learning ist ein eng benennbarer Fall, also Lesson statt Dauerkontext (Factory-ADR-047).
Review ohne Findings (nur zwei Nitpicks), Security-Review PASSED.

### Empfehlung für nächste Features
Die Task-ID-Ziffernprüfung (Kleinfund) bei Gelegenheit mit einem Test nachziehen.
