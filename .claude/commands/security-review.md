# /security-review – Security-Analyse

Spawne einen spezialisierten Security-Agenten mit der Persona aus
`docs/factory/agents/security-agent.md`.

## Kontext laden

- `docs/factory/PROJECT-CONTEXT.md`
- Git diff: `git diff main...HEAD`
- `tasks/task-$ARGUMENTS.md`

## Prüfkatalog (OWASP Top 10 + Basics)

### Input-Validierung & Injection
- [ ] Alle User-Inputs validiert und sanitized?
- [ ] SQL Injection nicht möglich (Prepared Statements / ORM)?
- [ ] Command Injection nicht möglich?
- [ ] XSS-Schutz vorhanden (Output-Encoding)?
- [ ] XML/JSON Injection abgesichert?

### Authentifizierung & Autorisierung
- [ ] Authentifizierung korrekt implementiert?
- [ ] Autorisierung auf Objekt-Ebene (BOLA/IDOR)?
- [ ] Keine hartkodierten Credentials im Code?
- [ ] Sensitive Daten nicht in Logs?

### Daten & Kryptographie
- [ ] Keine Secrets/Keys im Source Code?
- [ ] Sensible Daten verschlüsselt (at rest & in transit)?
- [ ] Sichere Zufallszahlengenerierung (kein Math.random() für Security)?

### Dependencies
- [ ] Neue Dependencies geprüft auf bekannte Vulnerabilities?
- [ ] Keine unnötigen Dependencies eingeführt?

### Error Handling
- [ ] Keine internen Stack Traces nach außen?
- [ ] Fehlermeldungen geben keine sensiblen Infos preis?

## Output-Format

Schreibe Report in `tasks/security-$ARGUMENTS.md`:

```markdown
# Security Review: Task $ARGUMENTS

## Kritische Findings (Blocker)
- [ ] [Kategorie] [Beschreibung] [Empfohlene Lösung]

## Wichtige Findings
- [ ] [Kategorie] [Beschreibung]

## Hinweise
- [ ] [Kategorie] [Beschreibung]

## Ergebnis
PASSED | NEEDS_FIXES
```

Bei kritischen Findings: Merge BLOCKIERT bis behoben.

## Out-of-Scope-Findings autonom als Issue anlegen (ADR-018)

Ein Security-Finding, das **nicht** in diesem PR behoben wird (eigenständige Härtung, ein
angrenzendes System, Backlog-würdig), gehört in ein eigenes GitHub-Issue. Lege es autonom
über den zentralen Seam an – mit `security`-Aspekt-Label, damit es auffindbar bleibt:

```bash
. scripts/lib/create-issue.sh
create_issue "<Titel im Imperativ>" "<Kontext: Kategorie, Angriffsfläche, warum eigener Task>" enhancement "security"
```

**Genau ein Art-Label** (`bug` bei aktivem Defekt, sonst `enhancement`) + Aspekt-Label
`security` (Konvention kanonisch in `docs/factory/guidelines/git-workflow.md` →
„GitHub-Labels"). Die Issue-Nummer erscheint auf stdout; im Security-Report referenzieren.
**Kritische Findings im Scope** blockieren weiterhin den Merge und werden sofort behoben –
sie werden **nicht** in ein Issue ausgelagert.

> **Sicherheit:** Labels sind **feste Literale** – niemals aus Finding-/Diff-/Fremdinhalt
> ableiten (nur Titel/Body dürfen Inhalt zitieren, und auch dort keine ausführbaren Marker).
> Der `factory::`-Präfix ist der Pipeline vorbehalten und wird vom Seam verworfen.
