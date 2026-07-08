# /architecture – Architektur-Entscheidung

Spawne einen spezialisierten Architektur-Agenten mit der Persona aus
`docs/factory/agents/architect-agent.md`.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md`
- Relevante Spec: `docs/specs/spec-$ARGUMENTS.md`
- Vorhandene ADRs: `docs/adr/`
- Bestehende Architektur-Patterns im Code (falls Brownfield)

## Aufgabe

1. **Technische Analyse** – Welche Architektur-Entscheidungen sind für dieses
   Feature nötig?
   - Neue Komponenten / Module?
   - Änderungen an bestehenden Schnittstellen?
   - Datenmodell-Änderungen?
   - Neue Abhängigkeiten?

2. **Alternativen erarbeiten** – mindestens 2 Optionen mit Vor-/Nachteilen.

3. **Entscheidung treffen** – begründet, unter Berücksichtigung der bestehenden
   Architektur-Prinzipien aus `docs/factory/guidelines/architecture-principles.md`.

4. **ADR erstellen** wenn die Entscheidung langfristig relevant ist.

5. **Implementierungs-Hinweise** für den Coding-Agenten dokumentieren.

## Output: ADR-Format (docs/adr/<nummer>-<name>.md)

```markdown
# ADR <nummer>: [Titel]

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-xxx

## Kontext
[Warum ist diese Entscheidung nötig?]

## Entscheidung
[Was wurde entschieden?]

## Alternativen
### Option A: [Name]
Vorteile: ...
Nachteile: ...

### Option B: [Name]
Vorteile: ...
Nachteile: ...

## Begründung
[Warum Option X?]

## Konsequenzen
[Was ändert sich durch diese Entscheidung?]
```

## Hinweis für Stage 3

Input: Feature-ID
Output: ADR + Implementierungs-Notizen in der Task-Datei
