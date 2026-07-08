# /codify – Learnings extrahieren (Self-Improvement Loop)

Dieser Skill schließt einen Feature-Zyklus ab und verbessert den Harness.
Er ist der Meta-Loop: Was hat die Factory dieses Mal falsch gemacht?

## Kontext laden

- `tasks/task-$ARGUMENTS.md` – Vollständige Task-Historie
- `tasks/review-$ARGUMENTS.md` – Review-Findings
- `tasks/security-$ARGUMENTS.md` – Security-Findings (falls vorhanden)
- `CLAUDE.md` – Aktuelle Regeln
- `docs/factory/guidelines/` – Aktuelle Guidelines
- `docs/factory/PROJECT-CONTEXT.md` – Bekannte Stolpersteine

## Aufgabe

### 1. Muster erkennen
Analysiere alle Findings aus Review und Security-Review:
- Welche Fehler wurden gemacht?
- Gibt es Muster? (z.B. "Immer wieder vergessene Fehlerbehandlung")
- Was hat überraschend gut funktioniert?

### 2. Regeln ableiten
Für jeden Fehler-Typ:
- Ist er durch eine neue Regel in CLAUDE.md verhinderbar?
- Ist er durch eine Ergänzung der Guidelines verhinderbar?
- Ist er projektspezifisch → in PROJECT-CONTEXT.md "Bekannte Stolpersteine"?

### 3. Änderungen vornehmen

**Neue projektspezifische Regel (häufig):**
→ Ergänze `docs/factory/PROJECT-CONTEXT.md` unter "Bekannte Stolpersteine"

**Neue universelle Regel (seltener, nur wenn wirklich generisch):**
→ Ergänze die passende Guideline-Datei in `docs/factory/guidelines/`

**Fundamentale Factory-Regel:**
→ Ergänze `CLAUDE.md` unter "Nicht verhandelbare Prinzipien"

**Neuer Check (für hartnäckige, automatisierbare Fehler):**
→ Erstelle neuen Check in `scripts/checks/`

### 4. Zusammenfassung ausgeben

Schreibe den Report in `tasks/codify-$ARGUMENTS.md`:

```markdown
## Codify-Report: Task $ARGUMENTS

### Neue Regeln hinzugefügt
- [Datei] [Regel] – wegen: [Fehler-Muster]

### Keine Änderungen nötig
[Begründung falls keine Learnings]

### Empfehlung für nächste Features
[Optional: Hinweise für die nächste Iteration]
```

Gib den Report zusätzlich auf der Konsole aus.

## Hinweis

Codify ist kein optionaler Schritt. Nach jedem Feature ausführen.
Der Harness wird besser, je öfter er genutzt wird.
