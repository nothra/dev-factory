# /implement – TDD-Implementierung

Spawne einen spezialisierten Coding-Agenten mit der Persona aus
`docs/factory/agents/coding-agent.md`.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md` – Tech-Stack, Build-Befehle
- `tasks/task-$ARGUMENTS.md` – Aufgaben-Details und Checkboxen
- `docs/specs/spec-$ARGUMENTS.md` – Akzeptanzkriterien (falls vorhanden)
- Relevante ADRs in `docs/adr/`

## Implementierungs-Prozess (strikt einhalten)

### Schritt 0 – ADR-Trigger-Check (vor jedem anderen Schritt ausführen)

**Voraussetzung:** Wenn keine Task-Datei geladen werden kann oder die Datei keine Beschreibung/Scope-Angabe enthält: Stoppe mit der Meldung: „Kein ADR-Trigger-Check möglich – Task-Datei fehlt oder enthält keinen Scope. Bitte eine gültige Task-Datei bereitstellen." Fahre nicht mit Schritt 1 fort.

Prüfe die Task-Datei und Spec auf die vier Trigger-Kategorien:

| # | Kategorie | Ausgelöst wenn... |
|---|-----------|-------------------|
| 1 | Technologiewahl | Framework, Datenbank, Messaging-System oder externe Bibliothek mit starker Bindewirkung wird eingeführt oder gewechselt |
| 2 | Architekturmuster | Entscheidung zwischen Schichtungsansätzen, CQRS, Event-Driven, Monolith vs. Microservice |
| 3 | Schnittstellen-Vertrag | Neue oder geänderte API zwischen Teams oder Services (REST, gRPC, Event-Schema) |
| 4 | Irreversible Konsequenz | Datenmigration, öffentliche API, Lizenzwahl, Security-Architektur, Persistenz-Strategie |

_(Kanonische Quelle: Spec-002 unter `docs/specs/spec-002-adr-auto-detection.md`. Bei Änderung der Kategorien: diese Datei und `docs/factory/agents/coding-agent.md` synchron aktualisieren.)_

**Wenn mindestens eine Kategorie zutrifft:**
Stoppe. Benenne die konkrete Entscheidung und die zutreffende Kategorie. Frage:
„Dies ist eine [Kategoriename] (Trigger-Kategorie [N]). Soll ich `/architecture` aufrufen, bevor ich weitermache?"

**Wenn keine Kategorie zutrifft:**
Fahre direkt mit Schritt 1 fort. Kein Hinweis nötig.

**Wenn du unsicher bist:**
Frage den Menschen explizit: „Ich bin unsicher, ob dies ADR-würdig ist. Handelt es sich um [Kategorie X]?"

**Wenn der Mensch bestätigt:**
Rufe `/architecture` auf (oder weise den Menschen explizit an, dies zu tun). Warte, bis eine ADR-Datei existiert. Protokolliere in der Task-Datei den Blocker: `Blocker [Datum]: Implementierung pausiert – ADR für [Entscheidung] ausstehend.` Implementiere den betroffenen Teil nicht ohne ADR.

**Wenn der Mensch ablehnt:**
Protokolliere in der Task-Datei:
`Nicht-ADR [Datum]: [Entscheidung] – bewusst kein ADR (Begründung: [kurze Begründung])`
Bestätige, dass der Protokolleintrag in der Task-Datei geschrieben wurde, bevor du mit der Implementierung fortfährst.
Frage in derselben Task-Session nicht erneut für dieselbe Entscheidung nach.

**Sonderfall Stage 3 – nicht-interaktive Pipeline (`run-pipeline.sh` / `claude --print`, erkennbar an `FACTORY_STAGE=3`):**
Hier ist kein Mensch da, den du fragen kannst. Frage daher NICHT, sondern löse einen deterministischen Interrupt aus:
```bash
bash scripts/raise-interrupt.sh $ARGUMENTS ADR "Trigger-Kategorie [N]: [konkrete Entscheidung]"
```
Implementiere den betroffenen Teil nicht und beende den Schritt. Die Pipeline erkennt das Sentinel, stoppt hart, trägt einen Blocker in die Task-Datei ein und weist auf `/architecture` hin (siehe ADR-004). Stilles Weiterlaufen ist nicht erlaubt.

### Schritt 1: Verstehen
- Task-Datei komplett lesen
- Bei Unklarheiten: Fragen stellen, bevor Code geschrieben wird
- Scope eingrenzen: Was gehört zu dieser Task, was nicht?

### Schritt 2: Test zuerst (TDD)
```
RED:   Schreibe einen fehlschlagenden Test für das gewünschte Verhalten
GREEN: Implementiere das Minimum, damit der Test grün wird
REFACTOR: Bereinige Code ohne neues Verhalten einzuführen
```
Führe nach jedem Zyklus die Tests aus.

### Schritt 3: Implementieren
- Kleine, fokussierte Commits – committen und pushen über `bash scripts/factory-commit.sh "<message>"`,
  nicht über rohes `git commit`/`git push` (fail-closed gegen main/master & `--force`, ADR-019).
- Jede Akzeptanz-Checkbox aus der Spec wird durch einen Test abgedeckt
- Clean-Code-Guidelines einhalten (siehe CLAUDE.md)

### Schritt 4: Quality Gates lokal prüfen
```bash
# Lint muss grün sein
{{LINT_COMMAND}}

# Alle Tests müssen grün sein
{{TEST_COMMAND}}
```
Nur wenn beide grün: Schritt als abgeschlossen markieren.

**Oberflächentests bei UI-berührenden Tasks (zusätzlich, nicht als Ersatz):**
Sobald eine Task die Oberfläche berührt, wird das Verhalten gegen einen **lokal
gestarteten Dev-Server** verifiziert – Unit-grün ≠ UI-/Proxy-grün (vgl. #63, wo ein
Handler-Direktaufruf die `proxy.ts`-Ebene umging):
1. Voraussetzung: lokale DB hochfahren (`pnpm db:up`) + `.env.local`.
2. Automatisiert: je Akzeptanzkriterium eine Playwright-Spec unter `e2e/*.spec.ts`;
   `pnpm test:e2e` startet den Dev-Server via `webServer`-Config selbst
   (`reuseExistingServer` außerhalb CI).
3. Interaktiv: `pnpm dev` (bzw. Preview-Config `dev`) starten und die betroffene
   Oberfläche im Browser durchklicken/screenshotten (deckt sich mit `/verify`).

Oberflächentests sind **nicht** in den pre-push-Gates verankert (Gates = Lint + `pnpm test`);
sie laufen zusätzlich und werden in der Task-Datei als erledigt vermerkt.

**Stage 3 (`FACTORY_STAGE=3`, nicht-interaktiv):** Kein Mensch, meist keine DB und kein
Browser vorhanden. Die interaktive Browser-Verifikation entfällt; automatisierte E2E
(`pnpm test:e2e`) nur ausführen, wenn DB (`pnpm db:up`) und Dev-Server verfügbar sind. Ist
das nicht gegeben, die offene UI-Verifikation als Blocker/Nachtest in der Task-Datei
protokollieren (Nachweis später über `/post-merge-verify`) – nicht still überspringen.

### Schritt 5: Task-Datei aktualisieren
- Abgearbeitete Checkboxen abhaken
- Notizen zu nicht-offensichtlichen Entscheidungen eintragen

## Regeln

- Kein Produktionscode ohne Test
- Keine Features über den Task-Scope hinaus
- Kein `TODO` ohne Ticket-Referenz
- Keine auskommentierten Code-Blöcke
- Bei Routen-Änderungen (`app/**/page.tsx`, `app/api/**/route.ts`): `docs/routes.md` im selben PR aktualisieren (Pfad, Funktion, Zugriff) – der Drift-Check blockiert sonst den Push (#145).
- ADR-Trigger-Check: siehe Schritt 0 – vier Kategorien, bei Treffer stoppen und fragen.

## Output

- Implementierter Code mit Tests
- Aktualisierte Task-Datei (Checkboxen)
- Keine offenen TODOs im neuen Code

## Hinweis für Stage 3

Input: Task-ID
Output: Code + Tests committed, Task-Datei aktualisiert
Nächster Schritt: `run-pipeline.sh` ruft `/review` auf

Wenn in Schritt 0 ein ADR-Trigger feuert: keine Frage möglich – stattdessen
`scripts/raise-interrupt.sh` aufrufen (siehe Sonderfall Stage 3). Die Pipeline
stoppt dann deterministisch statt still weiterzulaufen (ADR-004).
