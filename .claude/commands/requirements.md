# /requirements – Requirements Engineering

Spawne einen spezialisierten Requirements-Agenten mit der Persona aus
`docs/factory/agents/requirements-agent.md`.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md` – Projekt-Kontext
- `tasks/task-$ARGUMENTS.md` (falls eine Task-ID übergeben wurde)
- Vorhandene Specs in `docs/specs/` (falls vorhanden)

## Aufgabe

Erarbeite gemeinsam mit dem Entwickler eine präzise Spezifikation:

1. **Verständnis sicherstellen** – Stelle gezielte Fragen:
   - Was ist das gewünschte Verhalten aus Nutzersicht?
   - Was sind die Grenzen (was gehört NICHT dazu)?
   - Welche Fehlerszenarien müssen behandelt werden?
   - Gibt es Performance- oder Skalierungsanforderungen?

2. **Akzeptanzkriterien definieren** – im Format:
   ```
   GIVEN [Ausgangszustand]
   WHEN [Aktion/Ereignis]
   THEN [Erwartetes Ergebnis]
   ```

3. **Spec-Datei erstellen**: `docs/specs/spec-<id>-<name>.md`

4. **Task-Datei aktualisieren** (falls vorhanden): Checkboxen für jeden
   Akzeptanzkriterium eintragen.

## Output-Format (docs/specs/spec-<id>-<name>.md)

```markdown
# Spec: [Feature-Name]

## Kontext
[Warum wird das gebraucht?]

## Scope
**Inbegriffen:** ...
**Nicht inbegriffen:** ...

## Akzeptanzkriterien
- [ ] GIVEN ... WHEN ... THEN ...
- [ ] GIVEN ... WHEN ... THEN ...

## Fehlerszenarien
- [ ] ...

## Offene Fragen
- [ ] ...
```

## Hinweis für Stage 3

Input: Task-ID als Argument (`/requirements 42`)
Output: `docs/specs/spec-42-*.md` – wird von `/architecture` und `/implement` gelesen.
