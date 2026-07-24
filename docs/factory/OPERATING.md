# OPERATING – Factory optimal nutzen: Issue → Production, maximal automatisiert

> **Zweck:** Ein Runbook für den Alltag. Es zeigt den kürzesten verlässlichen Weg von einer
> Idee/einem Issue bis in die Produktion.
>
> **Leitbild:** *Der Mensch schärft die Anforderung, die Automatik führt sie aus.* Dieser Schnitt
> in **zwei Phasen** (schärfen ↔ umsetzen) ist das Leitmotiv der Factory – als Rahmen erklärt unter
> [Die zwei Phasen der Factory](#die-zwei-phasen-der-factory). Der
> **Standardweg ist automatisiert** (Abschnitt 1): ein Kommando fährt die ganze Pipeline bis zum
> merge-reifen PR, das Deploy-Gate trägt sie nach Production. Von Hand macht der Mensch bewusst nur
> zwei Dinge: die **Anforderung interaktiv schärfen** (Requirements, ggf. ADR) und die klar
> markierten **Entscheidungs-Gates** halten (Abschnitt 4). Wer volle Kontrolle über jeden Schritt
> will, nutzt den manuellen Fallback (Abschnitt 2).
>
> **Verhältnis zu anderen Dokumenten:**
> - **Was** die Factory ist und **warum** (Prinzipien, Pipeline-Übersicht): [`CLAUDE.md`](../../CLAUDE.md)
> - **Betriebsumgebung** (Stages, Deploy-Gate, Vercel/Neon): [`README.md`](../../README.md)
> - **Entscheidungen** (mit Alternativen): [`docs/adr/`](../adr/)
> - **Dieses Dokument** ist das prozedurale Bindeglied: die Reihenfolge der Handgriffe.

---

## Inhalt

- [Die zwei Phasen der Factory](#die-zwei-phasen-der-factory)
- [0. Einmal-Setup](#0-einmal-setup-pro-repo--pro-maschine)
- [1. Der automatisierte Weg (Default)](#1-der-automatisierte-weg-default)
- [2. Manuell / mit voller Kontrolle (Fallback)](#2-manuell--mit-voller-kontrolle-fallback)
- [3. Interrupts – wenn die Pipeline hält](#3-interrupts--wenn-die-pipeline-hält)
- [4. Menschen-Gates (nicht automatisierbar)](#4-menschen-gates-nicht-automatisierbar)
- [5. Wartung: Codify, Metriken, Post-Merge](#5-wartung-codify-metriken-post-merge)
- [Anhang: Branch-Protection richtig einordnen](#anhang-branch-protection-richtig-einordnen)

---

## Die zwei Phasen der Factory

Unabhängig davon, ob du automatisiert (Abschnitt 1) oder manuell (Abschnitt 2) arbeitest, zerfällt
jedes Feature in **zwei wesentliche Phasen**. Sie unterscheiden sich grundlegend in der **Rolle des
Menschen**:

| | **Phase 1 · Anforderung schärfen** | **Phase 2 · Umsetzung** |
|---|---|---|
| **Umfang** | Requirements, bei ADR-Trigger auch Architecture | Implement → Review↺ → Test → Refactor → Security → Codify → PR |
| **Rolle des Menschen** | Interaktion **Mensch ↔ Claude** – menschliches Urteil (*was* gebaut wird, *welche* Architektur) | Fleißarbeit (*wie* gebaut/getestet/reviewt wird) |
| **Automatisierbar?** | **Nein** – bleibt immer Handarbeit | **Ja** – vollautomatisiert, oder wahlweise Skill für Skill |
| **Start-Skript** | `bash scripts/start-work.sh "<beschreibung>"` → dann `/requirements`, ggf. `/architecture` | `PR_SHEPHERD=true bash scripts/run-pipeline.sh <task-id>` |

```
[Mensch]    Phase 1 · Anforderung schärfen        ◄─ immer interaktiv, nie automatisiert
            start-work.sh → /requirements → (ggf.) /architecture
 ═══════════════════════ Phasengrenze ═══════════════════════   ◄─ hier übernimmt die Automatik
[Automatik] Phase 2 · Umsetzung                    ◄─ vollautomatisiert ODER Skill für Skill
            run-pipeline.sh → implement → review↺ → test → refactor → security → codify → PR
```

> **Warum das zählt:** Der größte Qualitäts-Hebel liegt in Phase 1 – je schärfer Spec und
> Akzeptanzkriterien, desto verlässlicher läuft Phase 2. Deshalb bleibt Phase 1 **bewusst
> Handarbeit**: menschliches Urteil ist nicht automatisierbar. Phase 2 dagegen ist Fleißarbeit,
> die die Automatik übernimmt.
>
> **Automatisiert vs. manuell ist eine Frage von Phase 2, nicht von Phase 1.** Die beiden Wege in
> diesem Dokument unterscheiden sich **nur** darin, wie Phase 2 abläuft – ein Kommando
> ([Abschnitt 1](#1-der-automatisierte-weg-default)) gegen Skill für Skill
> ([Abschnitt 2](#2-manuell--mit-voller-kontrolle-fallback)). **Phase 1 ist in beiden Wegen
> identisch** und immer interaktiv (`start-work.sh` → `/requirements`, ggf. `/architecture`).
>
> **Kosten:** Die vollautomatisierte Phase 2 ist bequem, aber **teurer** – sie fährt 6+
> Claude-Sessions pro Feature hintereinander (deutlich mehr Token als interaktive Nutzung, Details
> in [Abschnitt 1.2](#12-automatik-laufen-lassen--ein-kommando-bis-zum-merge)).

---

## 0. Einmal-Setup (pro Repo / pro Maschine)

Diese Schritte sind einmalig. Danach greift die Automatik.

### 0.1 Lokale Werkzeuge (pro Entwickler-Maschine)

| Werkzeug | Zweck | Prüfen |
|----------|-------|--------|
| Node ≥ 20 + `pnpm` | Build/Test/DB-Scripts | `node -v`, `pnpm -v` |
| `gh` (authentifiziert) | Issues, PRs, Auto-Merge | `gh auth status` |
| `yq` | Config-Merge in `run-pipeline.sh` (Prerequisite) | `yq --version` |
| `claude` CLI (authentifiziert) | Skills, Stage-3-Pipeline | `claude --version` |
| Docker (Compose v2) | lokale DEV-Postgres | `docker compose version` |

Projekt aufsetzen: siehe [README → DEV](../../README.md#dev--lokale-entwicklung)
(`pnpm install` · `.env.local` · `pnpm db:up` · `db:migrate` · `db:seed` · `pnpm dev`).

### 0.2 GitHub-Repository-Secrets (für das Deploy-Gate)

Das Deploy-Gate (`.github/workflows/deploy-gate.yml`) migriert und promotet **fail-closed** –
fehlt ein Pflicht-Secret, bricht es ab (nie stilles Überspringen). Setzen unter
**Repo → Settings → Secrets and variables → Actions → Secrets**:

| Secret | Wofür | Pflicht? |
|--------|-------|----------|
| `VERCEL_AUTOMATION_BYPASS_SECRET` | E2E dürfen an Vercels Deployment-Protection vorbei (INT) | **Pflicht** |
| `E2E_ADMIN_EMAIL` / `E2E_ADMIN_PASSWORD` | INT-Admin-Login der E2E-Tests | **Pflicht** |
| `PRD_DATABASE_URL` | Prod-Neon-Connection-String (Auto-Migration, ADR-017) | **Pflicht** |
| `PRD_ADMIN_EMAIL` / `PRD_ADMIN_PASSWORD` | Prod-Login idempotent seeden | **Pflicht** |
| `NEON_API_KEY`, `NEON_PROJECT_ID`, `NEON_INT_BRANCH_ID`, `NEON_PRD_BRANCH_ID`, `INT_DATABASE_URL` | INT-Refresh von PRD (Reset → anonymisieren → migrieren) | **Pflicht** — Absicherungs-Vorstufe der PRD-Migration (seit ADR-017) |
| `ANTHROPIC_API_KEY` (oder `ANTHROPIC_BASE_URL` für ein Gateway) | nur für den **Async-Trigger** (Stage 3 in CI) | Optional (siehe 0.4) |

> Warum die Neon-Secrets **Pflicht** sind: Der INT-Refresh migriert dieselbe Migration zuerst
> gegen prod-nahe, anonymisierte Daten und fährt E2E dagegen. Solange das Gate PRD **automatisch**
> migriert, darf diese Vorstufe nicht fehlen – sonst liefe die Prod-Migration ohne den bewiesenen
> INT-Lauf (die Lücke, die ADR-017 schließt). Details: [README → Deploy-Gate](../../README.md#deploy-gate-e2e-vor-production).

### 0.3 Vercel Production-Branch (Scharfschalten – Reihenfolge zwingend)

Production ist vom `main`-Push **entkoppelt** und hängt am `production`-Branch, den nur das Gate
bewegt. Aktivierungsreihenfolge (aus README/ADR-017):

1. **Alle Pflicht-Secrets** aus 0.2 setzen.
2. Das Gate **einmal grün** laufen lassen (ein `main`-Push) → es legt/aktualisiert den `production`-Branch.
3. **Erst danach** in **Vercel → Project → Settings → Git → Production Branch = `production`** setzen.

Ab jetzt: `main`-Push → nur INT-Preview; **Prod deployt ausschließlich** über den vom Gate
promoteten `production`-Branch (nur bei grünem INT-E2E **und** grüner PRD-Migration).

Vercel-Env je Scope: `NEXT_PUBLIC_STAGE`, `DATABASE_URL`, `AUTH_SECRET` für *Preview/int* und
*Production* getrennt setzen (siehe [README → Stages](../../README.md#umgebungen-stages)).

### 0.4 Async-Trigger scharfschalten (unbeaufsichtigte Pipeline in CI)

Voraussetzung für den **vollständig unbeaufsichtigten** Pfad ([1.3](#13-vollautomatisch-unbeaufsichtigt-in-ci)) –
Issues, die die Factory eigenständig abarbeitet (`factory-poll.yml`, ADR-008):

- Repo-Secret `ANTHROPIC_API_KEY` (oder `ANTHROPIC_BASE_URL`).
- Labels existieren bereits (`factory::run/running/done/failed/interrupted`).
- Optional Repo-**Variablen**: `FACTORY_MAX_RUNS_PER_DAY` (Default 5), `FACTORY_RUN_TIMEOUT` (Default 3600s).
- Steuerung erfolgt **ausschließlich** über das Label `factory::run` am Issue (bewusst per Hand).

> Default **aus**. Ohne `factory::run`-Label und ohne API-Key passiert nichts.

### 0.5 Optional: Telemetrie (Token/Kosten)

`source config/otel.env.example` aktiviert client-seitige OTEL-Metriken (ADR-006). Default aus,
backend-unabhängig. Die **Prozess**-Kennzahlen (Abschnitt 5) brauchen das **nicht**.

---

## 1. Der automatisierte Weg (Default)

So läuft ein Feature standardmäßig – **maximal automatisiert**. Der Mensch macht bewusst nur den
ersten Schritt (Anforderung schärfen) interaktiv; danach orchestriert **ein Kommando** die
komplette Pipeline bis zum merge-reifen PR, und das Deploy-Gate trägt den Merge nach Production.

```
[Mensch]  1.1  Anforderung interaktiv schärfen  (/requirements, ggf. /architecture)
   │
[Automatik] 1.2  run-pipeline.sh  → implement → review↺ → test → refactor → security → codify → PR
   │              (hält deterministisch an den Menschen-Gates aus Abschnitt 4)
   ▼
[Automatik] 1.4  Merge → Deploy-Gate → Production
```

### 1.1 Anforderung schärfen (Mensch, interaktiv) — bleibt Handarbeit

**Dieser Schritt wird bewusst *nicht* automatisiert.** Hier entsteht der größte Hebel für Qualität:
Je schärfer Spec und Akzeptanzkriterien, desto verlässlicher läuft die nachfolgende Automatik. Die
Empfehlung lautet daher unverändert – **interaktiv mit einem Menschen**:

```bash
bash scripts/start-work.sh "<kurzbeschreibung>" [branch-typ]   # Issue + eigener Worktree + Draft-PR
```

`start-work.sh` legt Issue, **eigenen git-Worktree** (Isolation, siehe git-workflow.md) und Draft-PR
an; **Task-ID = Issue-Nummer** (ADR-013). Der Worktree gehört der **Task, nicht der Session**:
`/requirements` und das spätere `/implement` laufen im **selben** Worktree (die geschärfte Spec liegt
als Commit auf genau diesem Branch) – eine *frische Claude-Session* für den Implement-Schritt ist gut
für die Kontext-Hygiene, ein *frischer Working Tree* wäre falsch. In den ausgegebenen Worktree
wechseln, dann:

1. **`/requirements <id>`** – Spec + Akzeptanzkriterien **interaktiv schärfen** (`docs/specs/spec-<id>-*.md`,
   Task-Datei befüllt). Rückfragen jetzt klären, nicht später.
2. **Bei ADR-Trigger** (Technologie-/Architektur-/Schnittstellen-/Irreversibel-Entscheidung, siehe
   [4.1](#41-architektur-entscheidung-adr-trigger)): **`/architecture <id>`** – die Entscheidung
   interaktiv treffen und als ADR festhalten, **bevor** die Automatik implementiert.
3. **Beschreibendes Label** ans Issue hängen (genau eins): `bug` · `enhancement` · `documentation`
   · `security` · `tech-debt` · `test`.

> Faustregel: Alles, was menschliches Urteil braucht (was gebaut wird, welche Architektur), gehört
> vor die Automatik. Alles, was Fleißarbeit ist (wie es gebaut/getestet/reviewt wird), übernimmt sie.

### 1.2 Automatik laufen lassen — ein Kommando bis zum Merge

Wenn die Anforderung steht, orchestriert **ein** deterministisches Skript die restlichen Schritte
(Agenten werden aufgerufen – nicht umgekehrt):

```bash
PR_SHEPHERD=true bash scripts/run-pipeline.sh <task-id>   # implement→review↺→test→refactor→security→codify→PR-Lifecycle
bash scripts/run-pipeline.sh <task-id> --dry-run          # zeigt nur, was liefe (keine Claude-Aufrufe)
```

Ohne `PR_SHEPHERD=true` endet der Lauf am merge-reifen Stand; mit ihm fährt er zusätzlich den
PR-Lifecycle bis zum (Auto-)Merge. **Eigenschaften:**

- **Preflight:** PROJECT-CONTEXT ohne Platzhalter, sauberer Working Tree, Spec empfohlen (fehlt sie,
  Warnung → erst 1.1), stale Interrupt-Sentinel wird entfernt.
- **Review-Loop** mit **Circuit Breaker**: `MAX_REVIEW_ITERATIONS` (Default 2) – danach `exit 2`,
  Mensch übernimmt.
- **Security-Gate:** `NEEDS_FIXES` → Abbruch vor Merge.
- **Hält an den Menschen-Gates** (`FACTORY_STAGE=3`): Erkennt ein Agent eine nicht automatisierbare
  Entscheidung, ruft er `raise-interrupt.sh` und die Pipeline **stoppt hart** (ADR-004, Abschnitt 3).
  Kein stiller Durchlauf.
- **Kosten-Hebel** (Env-Vars): `CLAUDE_MODEL_HEAVY`, `CLAUDE_MODEL_LIGHT`, `CLAUDE_MODEL` (globaler
  Override), `MAX_TURNS`. Tier/Turns pro Skill aus `factory.defaults.yml` (optional
  `factory.config.yml`, ADR-009).

> **Kosten:** Der Lauf fährt 6+ Claude-Sessions pro Feature hintereinander – deutlich mehr Token als
> interaktive Nutzung. Die **Task-Datei** wird von der Automatik abgeschlossen; die letzte Checkbox
> `Fertig / PR erstellt` muss **vor** dem Merge im Branch stehen (Guardrail aus #63) – bei
> `PR_SHEPHERD=true` erledigt der Lauf das, sonst manuell vor `/pr-shepherd` prüfen ([2.2](#22-vor-dem-merge-task-datei-auf-dem-branch-abschließen-)).

### 1.3 Vollautomatisch, unbeaufsichtigt in CI

Für Issues, die ganz ohne lokale Session laufen sollen: das Issue mit **`factory::run`** labeln.
`factory-poll` (Scheduled Workflow, ADR-008) nimmt das älteste solche Issue und fährt
`run-pipeline.sh` selbst – **fail-closed hinter dem Budget-Guard** (Label-Eintrittstür +
Concurrency=1 + Tageskappe). Voraussetzung: Async-Trigger scharfgeschaltet ([0.4](#04-async-trigger-scharfschalten-unbeaufsichtigte-pipeline-in-ci)).

> Auch hier gilt 1.1: Ohne lokale `/requirements`-Sitzung ist der **Issue-Text die Spec**. Der
> unbeaufsichtigte Pfad ist nur so gut wie die Anforderung im Issue – gut spezifizieren oder vorher
> interaktiv schärfen. `factory::run` bewusst nur an dafür vorbereitete Issues, nie an rohe
> Backlog-/Doku-Issues ([4.4](#44-auslöser-des-auto-triggers)).

### 1.4 Was nach dem Merge automatisch passiert

Kein Handgriff mehr – der Merge auf `main` löst die Kette nach Production aus:

```
Merge auf main
   └─▶ Deploy-Gate (.github/workflows/deploy-gate.yml)
        INT auf Commit → INT-DB von PRD auffrischen (Reset→anonymisieren→migrieren→seed)
        → auf INT-Build warten → Playwright-E2E gegen INT
        → (nur grün) PRD-DB migrieren + seeden  → Promote main→production
        → Vercel deployt Production → /api/health-Check (DB-Read)
```

E2E **oder** Prod-Migration rot → **kein** Promote → Production bleibt auf dem letzten Stand.

---

## 2. Manuell / mit voller Kontrolle (Fallback)

Wenn du **jeden Schritt selbst fahren** willst (enger Blick auf ein heikles Feature, Lernen, oder
ein Schritt braucht durchgehend dein Urteil), fährst du **Phase 2** Skill für Skill – **Stage 2,
interaktiv**. **Phase 1** ([Die zwei Phasen](#die-zwei-phasen-der-factory)) bleibt identisch zu
Abschnitt 1: Der Einstieg (1.1: `start-work.sh` + `/requirements` + ggf. `/architecture`) ist
derselbe; nur danach fährst du statt `run-pipeline.sh` die Schritte von Hand.
**Eine Task = eine Claude-Session.**

### 2.1 Die Pipeline-Schritte einzeln

Reihenfolge wie in `CLAUDE.md`. Jeder Skill schreibt seinen Output in Dateien (kein
Gesprächsgedächtnis nötig).

| # | Skill | Wann nötig | Ergebnis / Gate |
|---|-------|-----------|-----------------|
| 1 | `/requirements <id>` | fast immer (siehe [1.1](#11-anforderung-schärfen-mensch-interaktiv--bleibt-handarbeit)) | Spec + Akzeptanzkriterien in `docs/specs/spec-<id>-*.md` |
| 2 | `/architecture <id>` | **nur bei ADR-Trigger** ([Abschnitt 4](#4-menschen-gates-nicht-automatisierbar)) | ADR in `docs/adr/` |
| 3 | `/implement <id>` | immer | TDD Red→Green→Refactor; Lint + Tests grün |
| 4 | `/review <id>` | immer | `tasks/review-<id>.md`, Verdict `APPROVED` / `NEEDS_REWORK` |
| ↺ | (bei `NEEDS_REWORK`) | zurück zu `/implement` | max. **3** Iterationen (Circuit Breaker), dann eskalieren |
| 5 | `/test <id>` | immer | Test-Suite vollständig, Coverage ≥ 80 % (neuer Code: 100 % erwartet) |
| 6 | `/refactor <id>` | immer | Clean-Code-Pass, **kein** neues Verhalten, Tests bleiben grün |
| 7 | `/security-review <id>` | immer (letztes Gate vor Merge) | `tasks/security-<id>.md`, `PASSED` / `NEEDS_FIXES` |
| 8 | `/codify <id>` | immer | `tasks/codify-<id>.md`; Learnings → Regeln in `CLAUDE.md`/`PROJECT-CONTEXT.md`/Guidelines |

Alternativer Einstieg statt 1: **`/bug-fix <id>`** – von Bug/Stacktrace statt Spec
(Reproduzieren → Isolieren → Beheben → Verifizieren).

### 2.2 Vor dem Merge: Task-Datei **auf dem Branch** abschließen ⚠️

**Guardrail (aus #63):** Die letzte Checkbox `Fertig / PR erstellt` und alle Abschluss-Notizen
müssen **im Feature-Branch** gesetzt sein, **bevor** der Merge läuft. Nach dem Merge liegt die
Datei auf `main` und ist nur noch über einen **neuen** PR änderbar (Direkt-Commit auf `main` ist
verboten) – für ein Häkchen unverhältnismäßig.

Konkret vor `/pr-shepherd`:

- [ ] Alle Status-Checkboxen in `tasks/task-<id>-*.md` abgehakt (inkl. `Fertig / PR erstellt`).
- [ ] Review `APPROVED`, Security `PASSED`, Codify ausgeführt.
- [ ] Bewusst offen gelassene Nitpicks als Backlog notiert (nicht stillschweigend).
- [ ] Änderungen committet und gepusht.
- [ ] `docs/CHANGELOG.md` `[Unreleased]` ergänzt (Konvention des Repos).

### 2.3 Rebasen, PR grün, mergen

```bash
git fetch origin && git rebase origin/main       # linear halten, Rebase statt Merge
git push --force-with-lease                       # nach Rebase
```

Dann **`/pr-shepherd <id>`** – fährt den PR-Lifecycle bis Auto-Merge: Rebase, CI abwarten,
Approval, Merge. Läuft ein Schritt gegen eine menschliche Entscheidung, **hält** der Shepherd via
Interrupt ([Abschnitt 3](#3-interrupts--wenn-die-pipeline-hält)). Danach greift automatisch das
Deploy-Gate ([1.4](#14-was-nach-dem-merge-automatisch-passiert)).

---

## 3. Interrupts – wenn die Pipeline hält

Ein Interrupt ist **kein Fehler**, sondern ein deterministischer Stopp-Punkt: eine Entscheidung
liegt beim Menschen (ADR-004). Signal = Datei `tasks/INTERRUPT-<id>.md`; Audit-Spur =
`tasks/interrupt-log.jsonl` (Quelle der Autonomie-Rate, ADR-006). Nach Klärung: Ursache beheben,
Sentinel wird beim nächsten Lauf im Preflight entfernt, dann Pipeline neu starten.

| Typ | Ausgelöst von | Bedeutung | Was der Mensch tut |
|-----|---------------|-----------|--------------------|
| `ADR` | `/implement` (Stage 3) | ADR-Trigger erkannt (Technologiewahl / Architekturmuster / Schnittstellen-Vertrag / irreversible Folge) | `/architecture <id>` fahren, ADR schreiben, Pipeline neu starten |
| `MISSING_INFO` | `/bug-fix` | Bug nicht reproduzierbar – Angaben fehlen | fehlende Infos liefern, erneut starten |
| `REVIEW_CONFLICT` | `/pr-shepherd` | Review-Kommentare widersprüchlich / unklar | Review klären, dann fortsetzen |
| `MERGE_CONFLICT` | `/pr-shepherd` | Rebase/Merge-Konflikt | Konflikt lokal auflösen, pushen |
| `CI_FAILURE` | `/pr-shepherd` | CI rot, nicht selbst behebbar | Ursache fixen, CI grün, fortsetzen |
| `APPROVAL_PENDING` | `/pr-shepherd` | Review-Approval fehlt | menschliches Approval einholen |
| `POST_MERGE_FAIL` | `post-merge-verify.sh` | deployte Umgebung verhält sich falsch (CI-grün ≠ Prod-grün) | Deployment prüfen, ggf. Rollback, neu verifizieren |
| `INCOMPLETE_OUTCOME` | `run-pipeline.sh` (Endzustands-Verifikation, ADR-040) | Lauf würde Erfolg melden, aber der reale Endzustand stimmt nicht (uncommittet/ungepusht, oder PR Draft bzw. weder gemergt noch Auto-Merge scharf) | realen Endzustand herstellen (pushen / PR aus Draft holen / Merge freigeben), dann neu starten |
| `PUSH_GATE_BLOCKED` | `/pr-shepherd` | fremdes, den Push-Gate blockierendes getracktes Artefakt (z. B. versehentlich committete Coverage-Ausgaben) | Artefakt bewusst bereinigen/entfernen (kein autonomes `git rm --cached`), dann fortsetzen |

Manuell einen Interrupt setzen (z. B. um einen Stage-3-Lauf gezielt anzuhalten):

```bash
bash scripts/raise-interrupt.sh <task-id> <TYP> "<nachricht>" ["<empfohlene aktion>"]
```

Im **Async-Trigger** (0.4) unterscheidet `factory-poll.sh` sauber: Interrupt-Sentinel vorhanden →
Label `factory::interrupted` (menschliche Entscheidung); sonst `factory::failed` (echter Fehler).

---

## 4. Menschen-Gates (nicht automatisierbar)

Diese Entscheidungen darf die Automatik **nicht** allein treffen. Sie sind bewusste Halte-Punkte –
auch (und gerade) im automatisierten Weg aus Abschnitt 1.

### 4.1 Architektur-Entscheidung (ADR-Trigger)

`/implement` prüft als **Schritt 0** vier Trigger-Kategorien (Spec-002 / ADR-002). Feuert eine,
**stoppt** der Agent:

1. **Technologiewahl** – neue Library/Framework/Datenbank/externer Dienst.
2. **Architekturmuster** – z. B. Wechsel zu Event-Driven, neue Schicht, Query-Modell.
3. **Schnittstellen-Vertrag** – öffentliche API/DB-Schema-Vertrag mit Außenwirkung.
4. **Langfristige/irreversible Konsequenz** – teuer rückgängig zu machen.

→ **Aktion:** `/architecture <id>` → ADR in `docs/adr/` (mit Alternativen), dann weiter. Am besten
schon **vorab** interaktiv in [1.1](#11-anforderung-schärfen-mensch-interaktiv--bleibt-handarbeit)
klären. In Stage 2 fragt der Agent interaktiv; in Stage 3 löst er den `ADR`-Interrupt aus.

### 4.2 Security-Freigabe

`/security-review` ist das **letzte Gate vor Merge**. Ergebnis `NEEDS_FIXES` = **Stopp**:
kritische/wichtige Findings werden behoben (nicht wegdiskutiert). Bewusst akzeptierte Rest-Punkte
gehören **begründet** in den Report und als Backlog-Issue heraus – nie stillschweigend.

### 4.3 Destruktive Produktions-Migrationen

Automatisch im Gate laufen nur **additive/geprüfte** Migrationen (auf INT gegen prod-nahe,
anonymisierte Daten bewiesen, dann PRD, ADR-017). **Nicht** dem Automatismus überlassen:

- `DROP`/`TRUNCATE`/Spalten-Umbenennung/Typ-Wechsel mit **echtem Prod-Datenbestand**.
- Alles, was Daten verliert oder nicht idempotent rückspielbar ist.

→ Solche Migrationen als **eigene ADR** entscheiden, Datensicherung/Rücklaufplan festhalten und
**manuell** kontrolliert fahren (`.env.prd` ist ausdrücklich für solche Sonderfälle gedacht,
README). Der drop-and-recreate-Trick aus den Migrations-Learnings gilt nur, **solange kein
Prod-Datenbestand betroffen ist** (PROJECT-CONTEXT).

### 4.4 Auslöser des Auto-Triggers

Das Label `factory::run` an ein Issue zu hängen ist eine **bewusste menschliche Handlung** – es
gibt das Issue zur unbeaufsichtigten Bearbeitung frei ([1.3](#13-vollautomatisch-unbeaufsichtigt-in-ci)).
Nie an reine Backlog-/Doku-Issues.

---

## 5. Wartung: Codify, Metriken, Post-Merge

### 5.1 Self-Improvement (`/codify` nach jedem Feature)

> „Jeder Bug, den die KI einführt, wird zur Regel, die den nächsten verhindert."

`/codify <id>` extrahiert Learnings → neue Regeln in `CLAUDE.md`, den Guidelines oder als
ausgelagertes Stolperstein-Learning unter `docs/factory/lessons/` + Index-Zeile in
`docs/factory/PROJECT-CONTEXT.md` (ADR-037). Faustregeln aus der Praxis:

- **Stack-spezifisch** (Next/NextAuth/Drizzle/Vitest …) → Volltext nach
  `docs/factory/lessons/<thema>.md` + Index-Zeile in `PROJECT-CONTEXT.md` (ADR-037), **nicht**
  die stack-agnostischen Guidelines.
- **Kanonische Quelle referenzieren:** taucht eine Regel mehrfach auf (Skill + Persona + Spec),
  jede Kopie auf die Quelle verweisen und beim Update **alle** synchronisieren.
- **Kein Check-Skript aus Reflex:** ein Gate nur, wenn der Fehler verlässlich grep-bar **und**
  wiederkehrend ist – sonst YAGNI (der laute Fehlschlag genügt).

### 5.2 Prozess-Kennzahlen

```bash
bash scripts/metrics.sh            # Lead-Time, Autonomie-Rate, CI-Quote, Interrupts, Durchsatz
bash scripts/metrics.sh --no-api   # nur lokale Kennzahlen (ohne GitHub-API)
```

Quelle: Git/GitHub (ADR-006) – **kein** Token-Accounting (das ist die optionale Telemetrie-Ebene,
0.5). Die Autonomie-Rate speist sich aus `tasks/interrupt-log.jsonl`.

### 5.3 Post-Merge-Verifikation

Das Deploy-Gate prüft nach dem Promote bereits `/api/health` (DB-Read). Für andere/zusätzliche
Smoke-Tests gibt es `post-merge-verify.sh` (CI-Stage `verify`, nur auf `main`, ADR-007):

- `FACTORY_HEALTHCHECK_CMD` – beliebiger Smoke-Test (Vorrang), **oder**
- `FACTORY_HEALTHCHECK_URL` (+ `_STATUS`/`_RETRIES`/`_INTERVAL`).

Fehlschlag → `POST_MERGE_FAIL`-Interrupt + roter Job (fail-closed).

> **Hinweis (aus #63):** `FACTORY_HEALTHCHECK_URL` **nicht** auf `/api/health` zeigen lassen –
> `post-merge-verify` läuft parallel/vor dem Promote und würde einen Fehlalarm erzeugen (Timing).

### 5.4 Invarianten laufend grün halten

- **Task = Issue** (ADR-013): `bash scripts/sync-issues.sh --check` (CI-Gate `issue-sync`
  erzwingt es); `--create` legt fehlende Issues an.
- **Nie direkt auf `main`** – pre-push-Hook blockiert hart; immer über Feature-Branch + PR.
- **Parallele Sessions in eigenen Worktrees** – `start-work.sh` legt jede Task in einem eigenen
  git-Worktree an; nach dem Merge `git worktree remove <pfad>` (siehe git-workflow.md).
- **Gates lokal vor dem Push:** `scripts/checks/pre-commit.sh` und `pre-push.sh` laufen sowieso,
  aber Lint/Tests/Format vorab spart CI-Runden.

---

## Anhang: Branch-Protection richtig einordnen

**Production ist bereits abgesichert** – über den vom `main`-Push **entkoppelten**
`production`-Branch plus das **E2E-Deploy-Gate** (Issue #38). Prod deployt ausschließlich, wenn
INT-E2E **und** PRD-Migration grün sind; sonst kein Promote. Ein direkter Weg an dieser Kette
vorbei nach Production existiert nicht.

Daraus folgt die Einordnung:

- **Branch-Protection auf `main` ist kein Produktions-Sicherheitsthema.** Selbst ein
  ungeschütztes `main` kann Prod nicht am Gate vorbei deployen.
- Sie ist **optionale `main`-Hygiene**: Der `main`-Push triggert das Gate, das jedoch nur die
  **E2E** fährt – **nicht** `lint`/`unit-test`. Diese laufen im PR-CI (`factory-ci.yml`). Wer auch
  auf `main` einen erzwungenen grünen Lint/Unit-Status oder Pflicht-Reviews möchte, kann dafür
  GitHub-Branch-Protection/Required-Checks einschalten.
- **Priorität: niedrig.** Nice-to-have für Historie-Sauberkeit und PR-Disziplin, nicht als
  Schließen einer Prod-Lücke – die gibt es hier nicht.

> Kurz: Der pre-push-Hook (kein Direkt-Push auf `main`) und das Deploy-Gate tragen die
> Sicherheit. Branch-Protection ist Komfort obendrauf, kein fehlender Schutzwall.
