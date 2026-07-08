# /pipeline – Vollständige Pipeline (Stage 3)

Dieser Skill ist der Entry Point für die automatisierte Pipeline.
Er wird primär von `scripts/run-pipeline.sh` aufgerufen, kann aber auch
manuell gestartet werden.

**Argument:** Task-ID (z.B. `/pipeline 42`)

## Voraussetzungen prüfen

Bevor die Pipeline startet:
- [ ] Task-Datei vorhanden: `tasks/task-$ARGUMENTS.md`?
- [ ] Spec vorhanden: `docs/specs/spec-$ARGUMENTS.md`?
- [ ] PROJECT-CONTEXT.md vollständig befüllt (keine `{{PLATZHALTER}}` mehr)?

Falls Voraussetzungen nicht erfüllt: Stoppen und Entwickler informieren.

## Pipeline-Ausführung

```
Phase 1: /implement $ARGUMENTS
  → Quality Gate: Lint + Tests grün?
  → Nein: Fehler-Report, stoppen
  → Ja: weiter

Phase 2: /review $ARGUMENTS
  → Ergebnis: APPROVED oder NEEDS_REWORK
  → NEEDS_REWORK (Versuch 1): zurück zu Phase 1
  → NEEDS_REWORK (Versuch 2): zurück zu Phase 1
  → NEEDS_REWORK (Versuch 3): CIRCUIT BREAKER – eskalieren an Mensch
  → APPROVED: weiter

Phase 3: /test $ARGUMENTS
  → Quality Gate: Coverage ≥ Schwelle?
  → Nein: Lücken schließen, nochmal
  → Ja: weiter

Phase 4: /security-review $ARGUMENTS
  → Ergebnis: PASSED oder NEEDS_FIXES
  → NEEDS_FIXES: zurück zu Phase 1
  → PASSED: weiter

Phase 5: /refactor $ARGUMENTS
  → Quality Gate: Tests noch grün?
  → Ja: weiter
  → Nein: Refactoring rückgängig, eskalieren

Phase 6: /codify $ARGUMENTS
  → Immer ausführen
  → Pipeline abgeschlossen
```

## Circuit Breaker

Bei Nicht-Konvergenz (3x dieselbe Phase gescheitert):
1. Aktuellen Stand commiten mit Prefix `WIP:`
2. Report schreiben in `tasks/pipeline-stuck-$ARGUMENTS.md`
3. An Mensch eskalieren

## Output

- Feature implementiert, reviewed, getestet, refactored
- `tasks/task-$ARGUMENTS.md` vollständig abgehakt
- `tasks/review-$ARGUMENTS.md` archiviert
- `CLAUDE.md` / Guidelines durch Codify aktualisiert
