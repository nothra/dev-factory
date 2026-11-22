## Codify-Report: Task 66

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + `INDEX.md` – **Schutz nie vor dem Geschützten abbauen:** Die Netz-Sperre wurde im Abbau
  vor dem Container entfernt, ein verwaister Container lief ungesperrt weiter. Drei Review-Runden prüften nur den Aufbaupfad;
  der Abbaupfad fiel erst im `/security-review` auf (W1). Regel: Schutz erst entfernen, wenn das Geschützte weg ist, sonst stehen
  lassen und warnen; Abbaupfad gehört in Spec, Test (Fake „lebt noch“ + Mutant) und Review.
- `docs/factory/lessons/testing.md` + `INDEX.md` – **Fake-Werkzeuge nur mit Builtins** (302 s statt 86 s je Gruppe); `${var}` vor
  typografischen Zeichen in Testnamen.

### Keine Änderungen nötig
- Keine Folge-Arbeit oberhalb der Schwelle: W1 wurde im PR behoben, daher kein Issue. Der Kleinfund „sudo ist root-äquivalent“ steht
  bereits in `docs/factory/kleinfunde.md`.

### Empfehlung für nächste Features
- Bei Sicherheitsgrenzen die Lebenszyklus-Frage „Was passiert beim Abbruch, und in welcher Reihenfolge fällt der Schutz?“ schon in
  `/architecture` stellen.
- `/codify` brach in der Pipeline dreimal am Turn-Limit (8) ab, obwohl die Lessons groß waren: bei Tasks mit mehreren Review-Runden
  das Budget für `/codify` erhöhen oder den Schritt manuell fahren (vgl. bestehende Turn-Limit-Lesson, Factory-ADR-065).
