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

> **Zwei Phasen:** Phase 1 (Requirements + ggf. Architecture) erfordert **immer** die Interaktion
> Mensch ↔ Claude und wird nicht automatisiert; Phase 2 (Umsetzung) kann **vollautomatisiert**
> laufen. Kanonische Quelle des prozeduralen Ablaufs (inkl. Start-Skripte je Phase) ist
> [`docs/factory/OPERATING.md`](docs/factory/OPERATING.md) → „Die zwei Phasen der Factory".

Alternativer Einstieg statt `/implement`: **`/bug-fix`** – startet von einem
Bug/Stacktrace statt von einer Spec (Reproduzieren → Isolieren → Beheben → Verifizieren).

**Stage 2 (manuell):** Jeder Schritt einzeln als Skill aufrufen.
**Stage 3 (automatisiert):** `scripts/run-pipeline.sh <task-id>` orchestriert alles.

**Messen (zwei Ebenen, ADR-006):**
- **Prozess:** läuft automatisch als Abschluss-Schritt **jedes** `run-pipeline.sh`-Laufs –
  fail-open, per EXIT-Trap, auch bei Abbruch (ADR-045) – und bleibt zusätzlich manuell über
  `/daily-metrics` (bzw. `scripts/metrics.sh [--publish]`) aufrufbar. Kennzahlen: Lead-Time,
  Autonomie-Rate, CI-Quote, Interrupts, Durchsatz. Quelle: Git/GitHub. Baut **kein**
  Token-Accounting nach. Veröffentlichung (`--publish`) optional an `$GITHUB_STEP_SUMMARY`
  (in CI) und als Kommentar an `FACTORY_METRICS_ISSUE` (Tracking-Issue) – lokal ohne beides
  bleibt es bei der Report-Datei.
- **Telemetrie (optional):** `config/otel.env.example` sourcen aktiviert client-seitige
  OTEL-Metriken (Token/Kosten/Nutzung pro Skill & Agent). Default aus, backend-unabhängig
  (funktioniert auch hinter einem AI-Gateway).

**Nach dem Merge:** `/post-merge-verify` (CI-Stage `verify`, nur auf `main`) prüft das
Verhalten der deployten Umgebung – CI-grün ≠ Produktion-grün. Check via
`FACTORY_HEALTHCHECK_CMD` (beliebiger Smoke-Test, Vorrang) oder `FACTORY_HEALTHCHECK_URL`.
Fehler → `POST_MERGE_FAIL`-Interrupt (ADR-007).

**Async-Start (optional, ADR-008):** `scripts/factory-poll.sh` (CI-Stage `orchestrate`) startet
die Pipeline für Issues mit Label `factory::run` – fail-closed hinter einem Budget-Guard
(Label-Eintrittstür + Concurrency=1 + Tageskappe). Default aus; Aktivierung = Schedule + Labels
+ Auth-Variable (Spur B). Der `schedule`-Trigger ist seit #284 **stillgelegt** – der Workflow
läuft nur auf manuelles `workflow_dispatch`; das Wiedereintragen ist Teil der
Scharfschalt-Checkliste (`docs/factory/OPERATING.md` §0.4).

Skills sind für beide Stufen designed: kein Gesprächsgedächtnis nötig, Output in Dateien.

---

## Coding Guidelines

@docs/factory/guidelines/clean-code.md
@docs/factory/guidelines/tdd-principles.md
@docs/factory/guidelines/testing-standards.md

> **Bedarfsgesteuert laden statt `@import` (ADR-047).** Eine Guideline verlässt den Dauerkontext,
> wenn ein Gate/Hook/Ruleset ihre Regeln fail-closed erzwingt – **oder** wenn ihr Adressatenkreis
> so eng und namentlich benennbar ist, dass ein „Laden bei"-Trigger genügt (so
> `architecture-principles.md`: nicht erzwungen, aber nur von zwei Skills gebraucht, ADR-047 §2).
> Wo eine nicht erzwungene Regel **jeden** Schritt treffen kann (Clean Code, TDD,
> Testing-Standards), bleibt sie oben geladen – **oder** ihre schritt-relevanten Regeln werden als
> Kern-Kurzregeln inline gespiegelt (so `git-workflow.md`, ADR-047 §3). „Laden bei" nennt Skill +
> Situation, im Format des Lessons-Index in `docs/factory/PROJECT-CONTEXT.md`:
>
> - [`guidelines/git-workflow.md`](docs/factory/guidelines/git-workflow.md) – Branches, PR/Issue,
>   Labels, Commits, Worktrees, Hook-Installation, Branch-Aufräumen · **Laden bei:**
>   `/pr-shepherd` (immer); `/review`, `/security-review`, `/codify` bei Issue-Anlage oder
>   Out-of-Scope-Funden; jedem Skill, sobald Branch-/Rebase-/Merge-/Label-Arbeit über die
>   Kern-Kurzregeln unten hinausgeht
> - [`guidelines/architecture-principles.md`](docs/factory/guidelines/architecture-principles.md) –
>   SOLID, Separation of Concerns, Dependency Rule, Fehlerbehandlung, API-Design · **Laden bei:**
>   `/architecture` (immer); `/review` bei Schichtungs-/Kopplungs-Findings
> - [`guidelines/token-efficiency.md`](docs/factory/guidelines/token-efficiency.md) – Token- &
>   Kosten-Effizienz · **Laden bei:** bewusst nie automatisch – die Datei rät selbst, geladenen
>   Kontext schlank zu halten
> - [`guidelines/bash-gotchas.md`](docs/factory/guidelines/bash-gotchas.md) – Bash-Fallstricke ·
>   **Laden bei:** `/implement`, `/review`, `/refactor` beim Schreiben/Reviewen von Shell-Skripten
> - Ausgelagerte `/codify`-Learnings (Stolpersteine, Volltext): `docs/factory/lessons/` – **nicht**
>   @importiert (ADR-037). Der Index + die Kern-Kurzregeln stehen in
>   `docs/factory/PROJECT-CONTEXT.md`; die passende Lesson bei Bedarf lesen

### Kern-Kurzregeln Git-Workflow (immer geladen)

> Die Regeln aus `git-workflow.md`, die **jeden** Pipeline-Schritt treffen können – damit kein
> Agent sie durch Nicht-Laden still verletzt (ADR-047 §3). Volltext, Begründung und
> Vorfall-Historie stehen in der Datei selbst; sie bleibt die kanonische Quelle. Bewusst **nicht**
> hier gespiegelt sind Regeln mit eigener kanonischer Quelle und eigenem Drift-Guard (Regel 7) –
> eine zweite normative Kopie im Dauerkontext wäre die einzige, die kein Guard bewacht.

1. **Nie direkt auf `main`/`master`** committen oder pushen – jede Änderung über Feature-Branch + PR. Der pre-push-Hook ist dabei nur lokales, **umgehbares** Feedback (`--no-verify`, zweiter Clone); fail-closed ist allein das serverseitige Ruleset `protect-main` (auch für Admins).
2. **Branch-Typ aus der Tabelle in `git-workflow.md`:** `feature/` `fix/` `improvement/` `hotfix/` `refactor/` `docs/` `test/` `chore/` – kanonisch ist die Tabelle in `git-workflow.md`, nicht diese Liste. `branch-name-check.sh` prüft sie nur als Claude-Code-Hook auf `checkout -b`/`switch -c`; kein Push- oder CI-Gate fängt einen falschen Branch-Typ.
3. **`Closes #<id>` im PR-Body** – eine bloße Erwähnung (`(#<id>)`, „Behebt #<id>") schließt das Issue nicht.
4. **Rebase statt Merge:** vor dem Start `git checkout main && git pull --rebase origin main`, vor dem Push `git fetch origin` + `git rebase origin/main` – nie `git merge origin/main` in den Feature-Branch. Auf einem **bereits gepushten** Branch rebast kein Zwischenschritt eigenständig gegen `main`; das bleibt bei `/pr-shepherd` (sonst erzwingt es einen Force-Push, #249).
5. **Commit-Message:** `<typ>: <kurze Beschreibung im Imperativ>` mit `typ` ∈ `feat` `fix` `docs` `refactor` `test` `chore`. Kein „WIP", kein „asdf". (Kein Hook prüft das Format – der `commit-msg`-Hook lehnt nur `--help`/`-h` als Message ab.)
6. **Task-ID = GitHub-Issue-Nummer** (ADR-013): jede `tasks/task-<id>-*.md` hat ein Issue #`<id>`; Anlage Issue-first über `scripts/start-work.sh`.
7. **Labels, Issue-Anlage und die Schwelle „Issue oder `kleinfunde.md`" nie aus dem Gedächtnis** – sie stehen **kanonisch in** `git-workflow.md` → „GitHub-Labels" bzw. „Zentraler Anlage-Weg (ADR-018)" (Schwelle: ADR-043) und werden dort von einem Drift-Guard bewacht. Vor jeder Issue-Anlage dort nachlesen; hier steht bewusst keine Kopie.
8. **Nach dem Merge aufräumen:** `git worktree remove <pfad>` + `git worktree prune`, lokale Branches via `git gone` – der Worktree enthält in der Regel eine Kopie von `.env.local` (Secret-Hygiene, nicht nur Plattenplatz; Ausnahmen: `FACTORY_WT_SKIP_ENV=1`, oder die Quelle hatte selbst keine).

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
- Nie pushen ohne `scripts/checks/pre-push.sh` erfolgreich durchgelaufen. Der Hook ist
  lokales Feedback; server-seitig ist `main` zusätzlich durch das GitHub-Ruleset
  `protect-main` fail-closed geschützt (kein Direkt-/Force-Push, PR-Pflicht, squash,
  required Checks – [ADR-029](docs/adr/029-branch-protection-main-ruleset.md)).
- **Git-Hooks kommen ausschließlich aus `bash scripts/install-hooks.sh`** (kanonische Quelle,
  [ADR-042](docs/adr/042-hook-installation-single-source.md); idempotent, beliebig oft
  ausführbar). Installiert werden `pre-commit`, `pre-push` und der `commit-msg`-Hook – letzterer
  lehnt Commit-Messages ab, die in Wahrheit ein CLI-Flag sind (`--help`/`-h`, `commit-msg-check.sh`).
  In einem frischen Clone bzw. einem vor dieser Regel initialisierten Repo einmalig ausführen;
  die Hooks liegen im gemeinsamen `.git` und gelten damit für alle Worktrees.
- **`yq` kommt in CI ausschließlich aus `bash scripts/install-yq.sh`** (kanonische Quelle, #258).
  Das Skript pinnt Version **und** SHA-256 (`YQ_VERSION` + `YQ_SHA256` – ein Bump ändert genau
  diese zwei Zeilen) und verifiziert fail-closed, bevor das Ausführbar-Bit fällt. Braucht ein
  neuer Workflow-Job `yq`, ruft er den Seam auf – **kein** eigener `wget`/`curl`+`chmod`-Block,
  auch nicht mit gepinnter URL. Grund für die Regel: genau dieser Block lag dreifach kopiert und
  unverifiziert in CI, bis #258 ihn zusammengezogen hat. Gleiches Muster für weitere
  Fremd-Binaries, die CI herunterlädt: gepinnter, verifizierter Seam statt Inline-Download.
- Keine offenen Checkboxen in der Task-Datei → kein Done
- **Der `@import`-Dauerkontext ist gedeckelt.** `scripts/checks/import-context-limit-check.sh`
  summiert `CLAUDE.md` + die `@`-eingebundenen Dateien und blockiert den Push, wenn die Grenze
  reißt ([ADR-047](docs/adr/047-import-kontext-guidelines-nach-erzwungenheit.md) §4). Wie jeder
  Hook ist er lokal und mit `--no-verify` umgehbar; server-seitig greift er bislang nur mittelbar
  über die Self-Test-Suite (Issue #328 zieht einen eigenen CI-Check nach). Neue Regeln also
  verdichten oder als Lesson auslagern (`docs/factory/lessons/` + Index-Zeile), nicht anhängen –
  ADR-037 wollte das per Konvention erreichen und lief von ~80 auf 341 Zeilen.
- **Routen-Doku bei jeder Routen-Änderung aktualisieren.** Wird eine Seite (`app/**/page.tsx`)
  oder ein API-Route-Handler (`app/api/**/route.ts`) hinzugefügt, entfernt oder in Pfad/Zugriff
  geändert, ist [`docs/routes.md`](docs/routes.md) im selben PR mitzupflegen (Pfad, Funktion,
  Zugriff). Der Drift-Check `scripts/checks/routes-doc-check.sh` blockiert einen Push fail-closed,
  wenn Doku und `app/`-Baum auseinanderlaufen. Analog zu „Entscheidungen dokumentieren". (aus #145)
- **Task-Datei final auf dem Feature-Branch abschließen – vor dem Merge.** Die letzte Checkbox
  (`Fertig / PR erstellt`) und alle Abschluss-Notizen müssen **im Branch** gesetzt sein, bevor
  `/pr-shepherd` (bzw. der Merge) läuft. Nach dem Merge liegt die Datei auf `main` und lässt sich
  nur noch über einen **neuen PR** ändern (Direkt-Commit auf `main` ist verboten) – für ein Häkchen
  unverhältnismäßig. (aus #63)
- Circuit Breaker: max. 3 Review↔Implement-Iterationen, dann eskalieren
- **Empfehlung (keine Pflicht): Für den `/implement`-Schritt einer Task eine neue
  Claude-Session öffnen.** `start-work.sh` und das anschließende `/requirements` (ggf.
  `/architecture`) laufen dagegen im Regelfall in derselben, noch task-freien Session –
  `start-work.sh` erinnert an der passenden Stelle daran. Grund: Kleiner Kontext = fokussierte
  Arbeit, weniger Token-Verbrauch, kein Übersprechen zwischen Tasks. Kanonische Quelle für
  Regelfall und Grenze: `docs/factory/guidelines/git-workflow.md` → „Eine Task = Eine Session".
- **Vor jeder neuen Task `bash scripts/start-work.sh` aufrufen** – nie manuell branchen.
  Das Skript stellt sicher: main ist aktuell, Branch existiert, Push ist erfolgt, Draft-PR ist angelegt.
- **Parallele Sessions arbeiten in getrennten git-Worktrees.** `start-work.sh` legt jede neue Task
  per Default in einem **eigenen Worktree** an (kein `checkout` im geteilten Baum) – so verschieben
  zwei gleichzeitige Sessions nie gegenseitig `HEAD` (Ursache des Kollisionsvorfalls #71). In den
  ausgegebenen Worktree-Pfad wechseln und dort arbeiten; nach dem Merge `git worktree remove`.
  Details: `docs/factory/guidelines/git-workflow.md` → „Parallele Sessions: eigener Worktree".

---

## Self-Improvement Loop

```
Feature abgeschlossen
    → /codify ausführen
    → Wiederkehrende Fehler werden neue Regeln in CLAUDE.md / Guidelines
    → Der Harness wird mit jeder Nutzung besser
```

> "Jeder Bug, den die KI einführt, wird zur Regel, die den nächsten verhindert."
