# /review – Multi-Persona Code-Review

Spawne drei spezialisierte Review-Sub-Agenten sequenziell.
Jeder bekommt nur Lesezugriff – keine Code-Änderungen in diesem Schritt.

Personas aus: `docs/factory/agents/review-agent.md`

## Kontext laden

- `docs/factory/PROJECT-CONTEXT.md`
- `tasks/task-$ARGUMENTS.md`
- Git diff des aktuellen Branches: `git fetch origin` (best-effort), dann `git diff origin/main...HEAD`
- Relevante Spec: `docs/specs/spec-$ARGUMENTS.md`

## Review-Runden

### Runde 1: Backend / Logik Review
**Fokus:** Korrektheit, Fehlerbehandlung, Edge Cases, Datenmodell
- Sind alle Akzeptanzkriterien aus der Spec erfüllt?
- Fehlerszenarien korrekt behandelt?
- Keine unnötige Komplexität?
- Business Logic korrekt implementiert?

### Runde 2: Code-Qualität Review
**Fokus:** Clean Code, Testqualität, Wartbarkeit
- Namen aussagekräftig?
- Funktionen klein und fokussiert?
- Tests testen Verhalten, nicht Implementierung?
- Keine Code-Duplikation?
- Keine Magic Numbers/Strings?

### Runde 3: Architektur & Patterns Review
**Fokus:** Schicht-Einhaltung, Pattern-Konsistenz, technische Schulden
- Architektur-Entscheidungen aus ADRs eingehalten?
- Keine Schicht-Verletzungen?
- Konsistent mit bestehendem Code-Stil?
- Bei Routen-Änderungen: `docs/routes.md` mitgepflegt (neue/geänderte/entfernte `page.tsx`/`route.ts`; Pfad, Funktion, Zugriff)? (#145)

## Output-Format

Schreibe Findings in `tasks/review-$ARGUMENTS.md`.

> **⚠️ Die Abschnitts-Überschriften sind verbindlich.**
> `run-pipeline.sh` wertet diese Datei automatisch aus (Pipeline Summary).
> Abweichende Überschriften führen zu falschen Zählungen.

```markdown
# Review: Task $ARGUMENTS

## Kritische Findings (müssen behoben werden)
- [ ] [Datei:Zeile] [Beschreibung] [Begründung]

## Wichtige Findings (sollten behoben werden)
- [ ] [Datei:Zeile] [Beschreibung]

## Nitpicks (optional)
- [ ] [Datei:Zeile] [Beschreibung]

## Positives
- [Was gut gemacht wurde]

## Empfehlung
APPROVED | NEEDS_REWORK
```

## Out-of-Scope-Findings: Schwelle klassifizieren (ADR-018/ADR-043)

Ein Finding, das **außerhalb** des aktuellen Task-Scopes liegt (eigenständiges Refactoring,
fehlende Tests an anderer Stelle, Härtung), gehört nicht in diesen PR. Klassifiziere es zuerst
gegen die Schwellen-Tabelle in `docs/factory/guidelines/git-workflow.md` → „Zentraler
Anlage-Weg (ADR-018)": ein echtes Sicherheitsrisiko, ein funktionaler Defekt mit
reproduzierbarem Auslöser oder ein Zweifelsfall (**im Zweifel Issue**) folgen Schritt A;
alles andere (Nitpick, Doku-Drift, „unter zehn Zeilen") folgt Schritt B.

**A – oberhalb der Schwelle:** autonom über den zentralen Seam anlegen:

```bash
. scripts/lib/create-issue.sh
create_issue_idempotent "<Titel im Imperativ>" "<Kontext: Datei:Zeile, warum eigener Task>" enhancement "tech-debt,test"
```

**Genau ein Art-Label** (`bug`/`enhancement`/`documentation`) + passende **Aspekt-Labels**
(`security`/`tech-debt`/`test`) – Konvention kanonisch in
`docs/factory/guidelines/git-workflow.md` → „GitHub-Labels". Die Issue-Nummer erscheint auf
stdout; im Review-Report referenzieren.

**B – unterhalb der Schwelle:** Eintrag in
[`docs/factory/kleinfunde.md`](../../docs/factory/kleinfunde.md) ergänzen – Schema,
Duplikat-Prüfung und Verhalten bei fehlgeschlagenem Edit stehen im Dateikopf.

Findings **im** Scope bleiben in `tasks/review-<id>.md`.

> **Sicherheit:** Labels sind **feste Literale** – niemals aus Finding-/Diff-/Fremdinhalt
> ableiten (nur Titel/Body dürfen Inhalt zitieren). Der `factory::`-Präfix ist der Pipeline
> vorbehalten und wird vom Seam verworfen.

## Circuit Breaker

Wenn dieser Review zum 3. Mal auf denselben Code angewendet wird:
→ Nicht weiter iterieren
→ An Mensch eskalieren mit Hinweis auf den ungelösten Konflikt

## Hinweis für Stage 3

Input: Task-ID
Output: `tasks/review-<id>.md`
Bei NEEDS_REWORK: `run-pipeline.sh` ruft `/implement` erneut auf (max. 2x)
Bei APPROVED: weiter zu `/test`
