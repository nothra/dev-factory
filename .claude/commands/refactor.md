# /refactor – Clean-Code-Pass

Spawne einen spezialisierten Refactoring-Agenten mit der Persona aus
`docs/factory/agents/refactor-agent.md`.

## Kontext laden

- `docs/factory/guidelines/clean-code.md`
- `tasks/task-$ARGUMENTS.md`
- `tasks/review-$ARGUMENTS.md` (Review-Findings, falls vorhanden)
- Geänderter Code: `git fetch origin` (best-effort), dann `git diff origin/main...HEAD`

## Wichtigste Regel

> **Kein neues Verhalten einführen.** Nur die interne Struktur verbessern.
> Tests müssen vor und nach dem Refactoring identisch grün sein.

## Refactoring-Checkliste

### Naming
- [ ] Variablen-/Funktionsnamen beschreiben klar, was sie sind/tun?
- [ ] Keine Abkürzungen (außer allgemein bekannte wie `id`, `url`)
- [ ] Keine irreführenden Namen?

### Funktionen & Methoden
- [ ] Funktionen machen genau eine Sache (SRP)?
- [ ] Funktions-Länge: max. ~20 Zeilen als Orientierung?
- [ ] Parameter-Anzahl: max. 3-4?
- [ ] Keine Flag-Parameter (boolean-Argumente die Verhalten steuern)?

### Struktur
- [ ] Code-Duplikation eliminiert?
- [ ] Magic Numbers/Strings durch benannte Konstanten ersetzt?
- [ ] Verschachtelungstiefe reduziert (Early Returns statt tiefer if-else)?
- [ ] Kommentare: erklärt das WHY, nicht das WHAT?

### Nach jedem Refactoring-Schritt
```bash
{{TEST_COMMAND}}
```
Wenn Tests rot werden: Refactoring rückgängig machen, kleiner aufteilen.

## Output

- Refactored Code (kein neues Verhalten)
- Alle Tests weiterhin grün
- Kurze Zusammenfassung der Änderungen in der Task-Datei
- Committen/pushen über `bash scripts/factory-commit.sh "<message>"`
  (nicht rohes `git commit`/`git push`; fail-closed gegen main/master & `--force`, ADR-019).
