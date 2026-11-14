# Development Factory · v0.7.0

> **Besitzer: Factory** (`bash scripts/checks/ownership-check.sh --list factory`). Generischer Teil der Agenten-Regeln; die
> projekteigenen Regeln stehen in `CLAUDE.md`, die diese Datei per `@import` einbindet.

Du operierst innerhalb der **Development Factory** – einem System für deterministische,
qualitativ hochwertige Softwareentwicklung mit KI-Unterstützung.

## Kernprinzip

> Deterministische Skripte orchestrieren nicht-deterministische Agenten-Schritte – nie umgekehrt.
> Bash ruft Agenten auf. Agenten rufen keine Bash-Pipelines auf.

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
━━━ PHASE 1 · Anforderung schärfen ━━━━━━━━━━━━━ Mensch ↔ Claude, immer interaktiv (start-work.sh)
[Mensch] Ideate
    ↓
/requirements  → Spec erstellen, Akzeptanzkriterien definieren
    ↓
/architecture  → Technische Entscheidungen, ADR erstellen  (nur bei ADR-Trigger)
    ↓
═══ PHASENGRENZE ═══════════════════════════════ ab hier vollautomatisierbar (run-pipeline.sh)
    ↓
━━━ PHASE 2 · Umsetzung ━━━━━━━━━━━━━━━━━━━━━━━━━ vollautomatisiert ODER Skill für Skill
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

> **Zwei Phasen:** Phase 1 ist immer interaktiv, Phase 2 kann vollautomatisch laufen – kanonisch: [`docs/factory/OPERATING.md`](OPERATING.md) → „Die zwei Phasen der Factory".

Alternativer Einstieg statt `/implement`: **`/bug-fix`** – startet von einem
Bug/Stacktrace statt von einer Spec (Reproduzieren → Isolieren → Beheben → Verifizieren).

**Stage 2 (manuell):** Jeder Schritt einzeln als Skill aufrufen.
**Stage 3 (automatisiert):** `scripts/run-pipeline.sh <task-id>` orchestriert alles.

**Messen (Factory-ADR-006):** Die Prozess-Messung läuft automatisch als Abschluss-Schritt jedes
`run-pipeline.sh`-Laufs (fail-open, Factory-ADR-045; manuell `/daily-metrics`, Veröffentlichung an `FACTORY_METRICS_ISSUE`).
Telemetrie läuft seit nothra/tch-gastro-services#334 automatisch je Pipeline-Lauf (Factory-ADR-049, abschaltbar mit `--no-telemetry`),
personenfrei nach `tasks/telemetry-<task-id>-<zeitstempel>.csv`. Details: `OPERATING.md` §0.5, §5.2.

**Nach dem Merge:** `/post-merge-verify` prüft die Umgebung (Factory-ADR-007, `OPERATING.md` §5.3).
**Async-Start:** `scripts/factory-poll.sh` über das Label `factory::run`, Default aus (Factory-ADR-008, `OPERATING.md` §0.4).

---

## Coding Guidelines

@docs/factory/guidelines/clean-code.md
@docs/factory/guidelines/tdd-principles.md
@docs/factory/guidelines/testing-standards.md

> **Bedarfsgesteuert laden statt `@import` (Factory-ADR-047):** Was ein Gate erzwingt oder nur ein eng benennbarer
> Adressatenkreis braucht, steht unten mit „Laden bei"-Trigger (Skill + Situation), im Format der
> Factory-Lessons-Übersicht unten. Regeln, die jeden Schritt treffen, bleiben oben geladen oder stehen als Kern-Kurzregeln inline.
>
> - [`guidelines/git-workflow.md`](guidelines/git-workflow.md) – Branches, PR/Issue,
>   Labels, Commits, Worktrees, Hook-Installation, Branch-Aufräumen · **Laden bei:**
>   `/pr-shepherd` (immer); `/review`, `/security-review`, `/codify` bei Issue-Anlage oder
>   Out-of-Scope-Funden; jedem Skill, sobald Branch-/Rebase-/Merge-/Label-Arbeit über die
>   Kern-Kurzregeln unten hinausgeht
> - [`guidelines/architecture-principles.md`](guidelines/architecture-principles.md) –
>   SOLID, Separation of Concerns, Dependency Rule, Fehlerbehandlung, API-Design · **Laden bei:**
>   `/architecture` (immer); `/review` bei Schichtungs-/Kopplungs-Findings
> - [`guidelines/token-efficiency.md`](guidelines/token-efficiency.md) – Token- &
>   Kosten-Effizienz · **Laden bei:** bewusst nie automatisch – die Datei rät selbst, geladenen
>   Kontext schlank zu halten
> - [`guidelines/bash-gotchas.md`](guidelines/bash-gotchas.md) – Bash-Fallstricke ·
>   **Laden bei:** `/implement`, `/review`, `/refactor`, `/security-review` bei Shell-Skripten
>
> **Factory-Lessons** (`/codify`-Learnings, Volltext, nicht @importiert – Factory-ADR-037):
>
> - [`lessons/testing.md`](lessons/testing.md) – Guard-/Gate-Tests für Skripte und Pipeline, Mutationsbelege, Fixtures, Test-Helfer · **Laden bei:** `/implement`, `/test`, `/review` beim Schreiben von Tests für Skripte/Gates/Pipeline
> - [`lessons/build-tooling.md`](lessons/build-tooling.md) – Wegwerf-/Debug-Artefakte und `.gitignore` · **Laden bei:** `/implement`, `/review` bei Wegwerf-Dateien und Ignore-Mustern
> - [`lessons/code-style.md`](lessons/code-style.md) – Clean-Code-Muster (Naming, Kommentar-Ort) · **Laden bei:** `/refactor`, `/review` (Clean-Code)
> - [`lessons/factory-workflow.md`](lessons/factory-workflow.md) – Git/CI, Pipeline-Skills, Patch-Workflow, Branch/Label, Review-Scope, kanonische Quellen, Blocker · **Laden bei:** jedem Skill bei Git-/Rebase-/CI-Arbeit, Pipeline-Abbruch oder Turn-Limit, `.claude/**`-Patch, ADR-/Spec-/Doku-Drift, Review-/Security-Review-Runden und Issue-/`kleinfunde.md`-Anlage
> - Einzelliste je Learning (Titel, Herkunft, bei `factory-workflow.md` ein Trigger je Eintrag):
>   [`lessons/INDEX.md`](lessons/INDEX.md). Projekt-Lessons: `docs/factory/PROJECT-CONTEXT.md` → „Bekannte Stolpersteine".

### Kern-Kurzregeln Git-Workflow (immer geladen)

> Die Regeln aus `git-workflow.md` (kanonische Quelle), die jeden Schritt treffen können (Factory-ADR-047 §3); Regel 7 verweist bewusst nur.

1. **Nie direkt auf `main`/`master`** committen oder pushen – jede Änderung über Feature-Branch + PR. Der pre-push-Hook ist dabei nur lokales, **umgehbares** Feedback (`--no-verify`, zweiter Clone); fail-closed ist allein das serverseitige Ruleset `protect-main` (auch für Admins).
2. **Branch-Typ aus der Tabelle in `git-workflow.md`:** `feature/` `fix/` `improvement/` `hotfix/` `refactor/` `docs/` `test/` `chore/` – kanonisch ist die Tabelle in `git-workflow.md`, nicht diese Liste. `branch-name-check.sh` prüft sie nur als Claude-Code-Hook auf `checkout -b`/`switch -c`; kein Push- oder CI-Gate fängt einen falschen Branch-Typ.
3. **`Closes #<id>` im PR-Body** – eine bloße Erwähnung (`(#<id>)`, „Behebt #<id>") schließt das Issue nicht.
4. **Rebase statt Merge:** vor dem Start `git checkout main && git pull --rebase origin main`, vor dem Push `git fetch origin` + `git rebase origin/main` – nie `git merge origin/main` in den Feature-Branch. Auf einem **bereits gepushten** Branch rebast kein Zwischenschritt eigenständig gegen `main`; das bleibt bei `/pr-shepherd` (sonst erzwingt es einen Force-Push, nothra/tch-gastro-services#249).
5. **Commit-Message:** `<typ>: <kurze Beschreibung im Imperativ>` mit `typ` ∈ `feat` `fix` `docs` `refactor` `test` `chore`. Kein „WIP", kein „asdf". (Kein Hook prüft das Format – der `commit-msg`-Hook lehnt nur `--help`/`-h` als Message ab.)
6. **Task-ID = GitHub-Issue-Nummer** (Factory-ADR-013): jede `tasks/task-<id>-*.md` hat ein Issue #`<id>`; Anlage Issue-first über `scripts/start-work.sh`.
7. **Labels, Issue-Anlage und die Schwelle „Issue oder `kleinfunde.md`" nie aus dem Gedächtnis** – sie stehen **kanonisch in** `git-workflow.md` → „GitHub-Labels" bzw. „Zentraler Anlage-Weg (Factory-ADR-018)" (Schwelle: Factory-ADR-043) und werden dort von einem Drift-Guard bewacht. Vor jeder Issue-Anlage dort nachlesen; hier steht bewusst keine Kopie.
8. **Nach dem Merge aufräumen:** `git worktree remove <pfad>` + `git worktree prune`, lokale Branches via `git gone` – der Worktree enthält Kopien der in `start_work.copy_files` gelisteten lokalen Dateien, oft Secrets (Secret-Hygiene, nicht nur Plattenplatz; nicht bei `FACTORY_WT_SKIP_COPY=1` oder fehlender Quelle).

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

- Nie committen ohne grünes `scripts/checks/pre-commit.sh`, nie pushen ohne grünes `scripts/checks/pre-push.sh`. Der Hook
  ist lokales Feedback; fail-closed schützt `main` allein das Ruleset `protect-main` ([Factory-ADR-029](adr/029-branch-protection-main-ruleset.md)).
- **Git-Hooks nur aus `bash scripts/install-hooks.sh`** ([Factory-ADR-042](adr/042-hook-installation-single-source.md),
  idempotent, einmal je Clone): `pre-commit`, `pre-push` und der `commit-msg`-Hook (lehnt `--help`/`-h` als Message ab).
- **`yq` kommt in CI nur aus `bash scripts/install-yq.sh`** (Version + SHA-256 gepinnt, fail-closed, nothra/tch-gastro-services#258) – kein
  eigener `wget`/`curl`-Block; dasselbe Muster für jedes weitere Fremd-Binary.
- Keine offenen Checkboxen in der Task-Datei → kein Done. Letzte Checkbox und Abschluss-Notizen **vor dem Merge auf dem
  Feature-Branch** setzen – danach nur per neuem PR (nothra/tch-gastro-services#63).
- **Der `@import`-Dauerkontext ist gedeckelt** (Zeilen und Bytes, `scripts/checks/import-context-limit-check.sh`,
  [Factory-ADR-047](adr/047-import-kontext-guidelines-nach-erzwungenheit.md) §4; lokal, in CI nur mittelbar, nothra/tch-gastro-services#328).
  Neue Regeln verdichten oder als Lesson auslagern (`docs/factory/lessons/` + Zeile in `lessons/INDEX.md`), nicht anhängen.
- Circuit Breaker: max. 3 Review↔Implement-Iterationen, dann eskalieren.
- **Empfehlung (keine Pflicht): Für den `/implement`-Schritt einer Task eine neue Claude-Session öffnen**; `start-work.sh`
  und `/requirements` (ggf. `/architecture`) laufen im Regelfall in derselben Session. Kanonische Quelle für Regelfall und Grenze: `docs/factory/guidelines/git-workflow.md` → „Eine Task = Eine Session".
- **Vor jeder neuen Task `bash scripts/start-work.sh`** – nie manuell branchen. Jede Task bekommt einen eigenen
  Worktree (parallele Sessions verschieben nie gegenseitig `HEAD`, nothra/tch-gastro-services#71); nach dem Merge `git worktree remove`.

---

## Self-Improvement Loop

```
Feature abgeschlossen
    → /codify ausführen
    → Wiederkehrende Fehler werden neue Regeln in CLAUDE.md / Guidelines
    → Der Harness wird mit jeder Nutzung besser
```

> "Jeder Bug, den die KI einführt, wird zur Regel, die den nächsten verhindert."
