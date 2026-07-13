# /bug-fix – Deterministischer Bug-Fix-Workflow

Spawne einen spezialisierten Bug-Fix-Agenten mit der Persona aus
`docs/factory/agents/coding-agent.md`.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md` – Tech-Stack, Test- und Lint-Befehle
- `tasks/task-$ARGUMENTS.md` – Bug-Beschreibung, Stacktrace, Reproduktionsschritte

## Bug-Fix-Prozess (Reihenfolge einhalten)

### Schritt 1: Reproduzieren (Pflicht – kein Fix ohne Reproduktion)

Ziel: einen fehlschlagenden Test schreiben, der den Bug beweist.

- Bug-Beschreibung und Stacktrace aus der Task-Datei verstehen
- Minimalen Testfall schreiben, der reproduzierbar fehlschlägt (RED)
- Testfall committen: `bash scripts/factory-commit.sh "fix: reproducing test for task-$ARGUMENTS"`
- Wenn kein Stacktrace vorhanden: Reproduktionsschritte in der Task-Datei dokumentieren
  und manuell nachvollziehen

> **Stage 3 – kein Mensch verfügbar:** Wenn der Bug nicht mit den gegebenen Infos
> reproduzierbar ist, Interrupt auslösen statt raten:
> ```bash
> bash scripts/raise-interrupt.sh $ARGUMENTS MISSING_INFO "Bug nicht reproduzierbar – fehlende Angaben: [was fehlt]"
> ```

### Schritt 2: Isolieren (Root Cause, nicht Symptom)

- Fehler auf die kleinste verantwortliche Code-Einheit eingrenzen
- Symptombehandlung (z. B. try/catch um den Fehler) ist verboten
- Root Cause in der Task-Datei dokumentieren:
  ```
  Root Cause [Datum]: [Datei:Zeile] – [Ursache in einem Satz]
  ```

### Schritt 3: Beheben (minimaler, chirurgischer Fix)

- Nur das Minimum ändern, das den Reproduktionstest grün macht (GREEN)
- Kein Scope Creep: keine Refactorings, keine verwandten Verbesserungen
- Fix committen: `bash scripts/factory-commit.sh "fix: [kurze Beschreibung] (task-$ARGUMENTS)"`

### Schritt 4: Verifizieren

```bash
# Reproduktionstest muss grün sein
{{TEST_COMMAND}}

# Keine Regression: gesamte Test-Suite muss grün sein
{{TEST_COMMAND}}
```

Wenn Regression: zurück zu Schritt 3, Fix einschränken.

### Schritt 5: Task-Datei aktualisieren

Trage in `tasks/task-$ARGUMENTS.md` ein:
- Checkboxen abhaken
- Root Cause (aus Schritt 2)
- Kurzform des Fix (Datei:Zeile → was geändert)
- Hinweis für `/codify`: welches Muster den Bug verursacht hat

## Regeln

- Kein Fix ohne Reproduktionstest
- Kein Fix, der Symptome kaschiert statt Ursachen behebt
- Kein Gold-Plating: verwandte Verbesserungen gehören in eine eigene Task
- Keine offenen Checkboxen → kein Done

## Output

- Fehlschlagender Reproduktionstest (committed)
- Minimaler Fix (committed)
- Aktualisierte Task-Datei (Root Cause, Fix-Beschreibung)

## Hinweis für Stage 3

Input: Task-ID mit Bug-Beschreibung/Stacktrace
Output: Reproduktionstest + Fix committed, Task-Datei aktualisiert
Nächster Schritt: `run-pipeline.sh` ruft `/review` auf

Wenn der Bug nicht reproduzierbar ist: `scripts/raise-interrupt.sh` aufrufen.
Die Pipeline stoppt deterministisch statt mit einem Blind-Fix weiterzulaufen (ADR-004).
