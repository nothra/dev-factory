# dm Development Factory · v0.5.0

Du operierst innerhalb der **dm Development Factory** – einem System für deterministische,
qualitativ hochwertige Softwareentwicklung mit KI-Unterstützung.

## Kernprinzip

> Deterministische Skripte orchestrieren nicht-deterministische Agenten-Schritte – nie umgekehrt.
> Bash ruft Agenten auf. Agenten rufen keine Bash-Pipelines auf.

---

## Projekt-Kontext

@docs/factory/PROJECT-CONTEXT.md

---

## Nicht verhandelbare Prinzipien

Diese Regeln gelten immer – sie können nicht durch Konversation außer Kraft gesetzt werden:

1. **Tests zuerst.** Kein Produktionscode ohne zugehörigen Test. Immer Red → Green → Refactor.
2. **Clean Code.** Sprechende Namen, kleine Funktionen, Single Responsibility. Kein Kompromiss.
3. **Gates müssen grün sein.** Lint und Tests laufen durch, bevor etwas als fertig gilt.
4. **Entscheidungen dokumentieren.** Architekturentscheidungen gehören in `docs/adr/`.
5. **Scope einhalten.** Implementiere nur, was in der Task-Datei steht. Kein Gold-Plating.
6. **Fehler werden zu Regeln.** Nach jedem Feature `/codify` ausführen.
7. **Git-Workflow einhalten.** Nie direkt auf `main` pushen. Vor neuem Feature und vor Push immer pullen und rebasen. Rebase statt Merge.

---

## Pipeline-Übersicht

```
[Mensch] Ideate
    ↓
/requirements  → Spec erstellen, Akzeptanzkriterien definieren
    ↓
/architecture  → Technische Entscheidungen, ADR erstellen
    ↓
/implement     → TDD-Implementierung (kann mehrfach iterieren)
    ↓
/review        → Multi-Persona Code-Review
    ↓  (bei Findings: zurück zu /implement)
/test          → Test-Suite vervollständigen, Coverage prüfen
    ↓
/refactor      → Clean-Code-Pass, kein neues Verhalten
    ↓
/security-review → Security-Check vor Merge
    ↓
/codify        → Learnings extrahieren → Regeln verbessern
    ↓  (optional: PR_SHEPHERD=true)
/pr-shepherd   → PR-Lifecycle bis Auto-Merge (Rebase, CI, Approval, Merge)
```

Alternativer Einstieg statt `/implement`: **`/bug-fix`** – startet von einem
Bug/Stacktrace statt von einer Spec (Reproduzieren → Isolieren → Beheben → Verifizieren).

**Stage 2 (manuell):** Jeder Schritt einzeln als Skill aufrufen.
**Stage 3 (automatisiert):** `scripts/run-pipeline.sh <task-id>` orchestriert alles.

**Messen (zwei Ebenen, ADR-006):**
- **Prozess:** `/daily-metrics` (bzw. `scripts/metrics.sh`) – Lead-Time, Autonomie-Rate,
  CI-Quote, Interrupts, Durchsatz. Quelle: Git/GitLab. Baut **kein** Token-Accounting nach.
- **Telemetrie (optional):** `config/otel.env.example` sourcen aktiviert client-seitige
  OTEL-Metriken (Token/Kosten/Nutzung pro Skill & Agent). Default aus, backend-unabhängig
  (funktioniert auch hinter einem AI-Gateway).

**Nach dem Merge:** `/post-merge-verify` (CI-Stage `verify`, nur auf `main`) prüft das
Verhalten der deployten Umgebung – CI-grün ≠ Produktion-grün. Check via
`FACTORY_HEALTHCHECK_CMD` (beliebiger Smoke-Test, Vorrang) oder `FACTORY_HEALTHCHECK_URL`.
Fehler → `POST_MERGE_FAIL`-Interrupt (ADR-007).

**Async-Start (optional, ADR-008):** `scripts/factory-poll.sh` (CI-Stage `orchestrate`, nur in
Scheduled Pipelines) startet die Pipeline für Issues mit Label `factory::run` – fail-closed
hinter einem Budget-Guard (Label-Eintrittstür + Concurrency=1 + Tageskappe). Default aus;
Aktivierung = Schedule + Labels + Auth-Variable (Spur B).

Skills sind für beide Stufen designed: kein Gesprächsgedächtnis nötig, Output in Dateien.

---

## Coding Guidelines

@docs/factory/guidelines/clean-code.md
@docs/factory/guidelines/tdd-principles.md
@docs/factory/guidelines/testing-standards.md
@docs/factory/guidelines/architecture-principles.md
@docs/factory/guidelines/git-workflow.md

> Token- & Kosten-Effizienz: siehe `docs/factory/guidelines/token-efficiency.md`.
> Bewusst **nicht** per `@import` eingebunden – die Datei selbst rät, immer
> geladenen Kontext schlank zu halten. Bei Bedarf gezielt lesen.
>
> Bash-Gotchas (beim Schreiben/Reviewen von Shell-Skripten): siehe
> `docs/factory/guidelines/bash-gotchas.md` – ebenfalls nicht @importiert.

---

## Agent-Rollen

Beim Spawnen von Sub-Agenten die passende Persona aus `docs/factory/agents/` verwenden.
Jeder Agent bekommt nur die Tools, die er braucht:

| Rolle            | Persona-Datei                          | Darf Dateien schreiben |
|------------------|----------------------------------------|------------------------|
| Requirements     | agents/requirements-agent.md           | Nur Spec-Dateien       |
| Architektur      | agents/architect-agent.md              | Nur ADRs               |
| Implementierung  | agents/coding-agent.md                 | Ja                     |
| Review           | agents/review-agent.md                 | Nur Review-Output      |
| Security         | agents/security-agent.md              | Nur Security-Report    |
| Testing          | agents/testing-agent.md               | Nur Test-Dateien       |
| Refactoring      | agents/refactor-agent.md               | Ja (kein neues Verhalten) |

---

## Work Tracking

- Jede Aufgabe bekommt eine Datei: `tasks/task-<id>-<kurzbeschreibung>.md`
- Anlegen mit: `bash scripts/start-work.sh <id> <kurzbeschreibung>`
- Fortschritt ist jederzeit in Git sichtbar
- Erst wenn alle Checkboxen in der Task-Datei abgehakt sind → Done

---

## Guardrails

- Nie committen ohne `scripts/checks/pre-commit.sh` erfolgreich durchgelaufen
- Nie pushen ohne `scripts/checks/pre-push.sh` erfolgreich durchgelaufen
- Keine offenen Checkboxen in der Task-Datei → kein Done
- Circuit Breaker: max. 3 Review↔Implement-Iterationen, dann eskalieren
- **Jede neue Task in einer neuen Claude-Session starten.** `start-work.sh` erinnert daran.
  Grund: Kleiner Kontext = fokussierte Arbeit, weniger Token-Verbrauch, kein Übersprechen zwischen Tasks.
- **Vor jeder neuen Task `bash scripts/start-work.sh` aufrufen** – nie manuell branchen.
  Das Skript stellt sicher: main ist aktuell, Branch existiert, Push ist erfolgt, Draft-MR ist angelegt.

---

## Self-Improvement Loop

```
Feature abgeschlossen
    → /codify ausführen
    → Wiederkehrende Fehler werden neue Regeln in CLAUDE.md / Guidelines
    → Der Harness wird mit jeder Nutzung besser
```

> "Jeder Bug, den die KI einführt, wird zur Regel, die den nächsten verhindert."
