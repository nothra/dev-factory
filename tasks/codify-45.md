## Codify-Report: Task 45

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`, Gruppe `testing`): Guard über mehrere Pfade braucht je Pfad einen Fixture-Test „Treffer mit Datei und Zeile“ und am echten Baum „hat getrackte Dateien“; Orakel-Liste unabhängig vom Guard; Fixture-Dateinamen unter `docs/factory/adr/` zur Laufzeit zusammensetzen – wegen: Review-Iteration 1 W1 (vier von fünf Pfaden ungetestet, erst der Mutationsbeleg zeigte es).
- `PROJECT-CONTEXT.md` (Gruppe `factory-workflow`, Zeile mit `→`-Trigger): Neuer Guard über Dateien, die nur per `.claude/**`-Patch änderbar sind, bleibt bis zum Apply rot und blockiert den Push – lokal committen, Push zurückhalten, Patch in Wegwerf-Kopie belegen – wegen: Blocker dieser Task (Review W3).
- `docs/factory/lessons/build-tooling.md`: Regel-Absatz zu `.gitignore` nachgeführt (`*.tmp.spec.tsx` entfällt seit Task 45) – wegen: Review-Nitpick (Lesson nannte das Muster noch als ignoriert); Lehre unverändert.

### Keine Änderungen nötig
- Kein neues CLAUDE.md-/Guideline-Prinzip: die Muster sind testspezifisch bzw. Lesson-Niveau.
- Kein neuer Check: Stack-Guard und C1-Guard wurden in dieser Task selbst angelegt.
- Out-of-Scope: Review-Nitpick 2 (`app/`, `db/`, `lib/` in `codify.md`) liegt in einer nur per Patch änderbaren Datei und verletzt keine Begriffsliste – unterhalb der Schwelle, kein Issue.

### Empfehlung für nächste Features
- Offen für den Menschen vor dem Merge: `git apply tasks/patch-45.diff` (ändert `.claude/commands/implement.md`, `review.md`, `codify.md`, `.gitignore`), danach Patch-Datei entfernen, `[~]` → `[x]` in der Task-Datei, committen, pushen.
- AK16: Übergabe-Kommentar an nothra/tch-gastro-services#428 liegt nur als Entwurf vor, Freigabe zum Posten steht aus; danach im PR-Body verlinken.
- Bei Tasks, die `.claude/**` berühren, den Push-Block durch den neuen Guard früh einplanen.
