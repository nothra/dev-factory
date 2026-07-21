# /codify – Learnings extrahieren (Self-Improvement Loop)

Dieser Skill schließt einen Feature-Zyklus ab und verbessert den Harness.
Er ist der Meta-Loop: Was hat die Factory dieses Mal falsch gemacht?

## Kontext laden

- `tasks/task-$ARGUMENTS.md` – Vollständige Task-Historie
- `tasks/review-$ARGUMENTS.md` – Review-Findings
- `tasks/security-$ARGUMENTS.md` – Security-Findings (falls vorhanden)
- `CLAUDE.md` – Aktuelle Regeln
- `docs/factory/guidelines/` – Aktuelle Guidelines
- `docs/factory/PROJECT-CONTEXT.md` – Index der Stolpersteine + Kern-Kurzregeln
- `docs/factory/lessons/` – Volltext der ausgelagerten Stolperstein-Learnings (ADR-037)

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
- Ist er projektspezifisch → als Lesson unter `docs/factory/lessons/<thema>.md`
  (Volltext) + eine Index-Zeile mit „Laden bei"-Trigger in `PROJECT-CONTEXT.md`?

### 3. Änderungen vornehmen

**Neue projektspezifische Regel (häufig):**
→ Schreibe den **Volltext** in die thematisch passende `docs/factory/lessons/<thema>.md`
(`frontend-react`, `next-auth`, `db-drizzle`, `testing`, `build-tooling`, `code-style`,
`factory-workflow`) **plus** eine **Index-Zeile** unter „Index der ausgelagerten Learnings“
in `docs/factory/PROJECT-CONTEXT.md` – **nicht** mehr in den @import-Volltext (ADR-037).
Die Index-Zeile bekommt einen **„Laden bei"-Trigger** (welcher Skill + welche Situation die
Lesson braucht), damit ein Skill sie bedarfsgesteuert lädt: bei homogener Domänen-Datei am
Gruppen-Header, bei gemischten Auslösern (`factory-workflow.md`) als `→ <Trigger>` je Zeile.
Nur eine wirklich taskübergreifende Data-Layer-/Validierungsregel darf zusätzlich als
Kern-Kurzregel inline stehen. Passt kein Thema, eine neue `lessons/<thema>.md` anlegen.

**Neue universelle Regel (seltener, nur wenn wirklich generisch):**
→ Ergänze die passende Guideline-Datei in `docs/factory/guidelines/`

**Fundamentale Factory-Regel:**
→ Ergänze `CLAUDE.md` unter "Nicht verhandelbare Prinzipien"

**Neuer Check (für hartnäckige, automatisierbare Fehler):**
→ Erstelle neuen Check in `scripts/checks/`

**Folge-Arbeit, die den aktuellen Scope sprengt → autonom als GitHub-Issue anlegen (ADR-018):**
Stößt du auf ein Learning, das eigenen Aufwand braucht (Refactoring, fehlende Tests,
Härtung), lege es über den zentralen Seam an – statt es nur im Report zu vermerken:

```bash
. scripts/lib/create-issue.sh
create_issue "<Titel im Imperativ>" "<Kontext: warum, woraus>" enhancement "tech-debt"
```

Konvention (kanonisch in `docs/factory/guidelines/git-workflow.md` → „GitHub-Labels"):
**genau ein Art-Label** (`bug`/`enhancement`/`documentation`) + passende **Aspekt-Labels**
(`security`/`tech-debt`/`test`). Die Issue-Nummer erscheint auf stdout; im Report verlinken.

> **Sicherheit:** Labels sind **feste Literale** – niemals aus Finding-/Diff-/Fremdinhalt
> ableiten (nur Titel/Body dürfen Inhalt zitieren). Der `factory::`-Präfix ist der Pipeline
> vorbehalten und wird vom Seam verworfen.

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
