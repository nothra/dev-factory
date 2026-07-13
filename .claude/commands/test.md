# /test – Test-Suite vervollständigen

Spawne einen spezialisierten Testing-Agenten mit der Persona aus
`docs/factory/agents/testing-agent.md`.

## Kontext laden

- `docs/factory/PROJECT-CONTEXT.md` – Test-Framework, Coverage-Schwelle
- `tasks/task-$ARGUMENTS.md`
- `docs/specs/spec-$ARGUMENTS.md` – alle Akzeptanzkriterien
- Vorhandene Tests für den geänderten Code

## Aufgabe

### 1. Coverage-Analyse
```bash
{{TEST_COVERAGE_COMMAND}}
```
Liegt Coverage unter `{{COVERAGE_THRESHOLD}}`%? → Lücken identifizieren.

### 2. Test-Vollständigkeit prüfen
Für jeden Akzeptanzkriterium aus der Spec:
- [ ] Happy Path getestet?
- [ ] Fehlerfälle / Edge Cases getestet?
- [ ] Boundary-Werte getestet?

### 3. Test-Qualität prüfen
- Testen Tests das Verhalten oder die Implementierung?
- Tests sind unabhängig voneinander?
- Tests sind deterministisch (kein Flakiness-Risiko)?
- Test-Namen beschreiben klar, was getestet wird?

### 4. Fehlende Tests schreiben
TDD-Prinzip einhalten:
- Unit Tests: isoliert, schnell, viele
- Integration Tests: Schnittstellen zwischen Komponenten
- Kein Mocking von internem Code (nur externe Systeme)

### 5. Finale Test-Ausführung
```bash
{{TEST_COMMAND}}
```
Alle Tests müssen grün sein. Coverage-Schwelle muss erreicht sein.

## Output

- Vervollständigte Test-Suite
- Coverage-Report (in `tasks/coverage-$ARGUMENTS.md` falls detailliert)
- Alle Tests grün, Coverage ≥ Schwelle

## Regeln

- Kein Produktionscode ändern in diesem Schritt – nur Tests
- Schlägt ein Test fehl, der vorher grün war: sofort eskalieren
- Keine Test-Helfer, die Produktions-Logik duplizieren
- Fertige Tests committen und pushen über `bash scripts/factory-commit.sh "<message>"`
  (nicht rohes `git commit`/`git push`; fail-closed gegen main/master & `--force`, ADR-019).
