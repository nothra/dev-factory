# OPERATING – Factory optimal nutzen: Issue → Production, maximal automatisiert

> **Zweck:** Ein Runbook für den Alltag. Es zeigt den kürzesten verlässlichen Weg von einer
> Idee/einem Issue bis in die Produktion – so viel wie möglich automatisiert, mit klar
> markierten Stellen, an denen ein Mensch entscheiden **muss**.
>
> **Verhältnis zu anderen Dokumenten:**
> - **Was** die Factory ist und **warum** (Prinzipien, Pipeline-Übersicht): [`CLAUDE.md`](../../CLAUDE.md)
> - **Betriebsumgebung** (Stages, Deploy-Gate, Vercel/Neon): [`README.md`](../../README.md)
> - **Entscheidungen** (mit Alternativen): [`docs/adr/`](../adr/)
> - **Dieses Dokument** ist das prozedurale Bindeglied: die Reihenfolge der Handgriffe.

---

## Inhalt

- [0. Einmal-Setup](#0-einmal-setup-pro-repo--pro-maschine)
- [1. Ein Feature von Issue bis Production (Checkliste)](#1-ein-feature-von-issue-bis-production-checkliste)
- [2. Stage-3-Modus: `run-pipeline.sh`](#2-stage-3-modus-run-pipelinesh)
- [3. Interrupts – wenn die Pipeline hält](#3-interrupts--wenn-die-pipeline-hält)
- [4. Menschen-Gates (nicht automatisierbar)](#4-menschen-gates-nicht-automatisierbar)
- [5. Wartung: Codify, Metriken, Post-Merge](#5-wartung-codify-metriken-post-merge)
- [Anhang: Branch-Protection richtig einordnen](#anhang-branch-protection-richtig-einordnen)

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

### 0.4 Optional: Async-Trigger (Stage 3 unbeaufsichtigt in CI)

Nur wenn die Factory Issues **eigenständig** abarbeiten soll (`factory-poll.yml`, ADR-008):

- Repo-Secret `ANTHROPIC_API_KEY` (oder `ANTHROPIC_BASE_URL`).
- Labels existieren bereits (`factory::run/running/done/failed/interrupted`).
- Optional Repo-**Variablen**: `FACTORY_MAX_RUNS_PER_DAY` (Default 5), `FACTORY_RUN_TIMEOUT` (Default 3600s).
- Steuerung erfolgt **ausschließlich** über das Label `factory::run` am Issue (bewusst per Hand).

> Default **aus**. Ohne `factory::run`-Label und ohne API-Key passiert nichts.

### 0.5 Optional: Telemetrie (Token/Kosten)

`source config/otel.env.example` aktiviert client-seitige OTEL-Metriken (ADR-006). Default aus,
backend-unabhängig. Die **Prozess**-Kennzahlen (Abschnitt 5) brauchen das **nicht**.

---

## 1. Ein Feature von Issue bis Production (Checkliste)

Der Standardweg (**Stage 2**, interaktiv – ein Mensch fährt die Skills nacheinander).
**Eine Task = eine neue Claude-Session** (kleiner Kontext, weniger Token, kein Übersprechen).

### 1.0 Starten (Issue-first, nie manuell branchen)

```bash
bash scripts/start-work.sh "<kurzbeschreibung>" [branch-typ]   # legt Issue+Branch+Task-Datei+Draft-PR an
# branch-typ: feature (Default) | fix | improvement | hotfix | chore | docs | test | refactor
```

Das Skript stellt deterministisch sicher: `main` aktuell (rebase), Branch existiert, Task-Datei
committet, Branch gepusht, Draft-PR offen. **Task-ID = Issue-Nummer** (ADR-013). Danach eine
**neue** Claude-Session öffnen und dort weiterarbeiten.

Ein passendes **beschreibendes Label** ans Issue hängen (genau eins): `bug` · `enhancement` ·
`documentation` · `security` · `tech-debt` · `test`. **Kein** `factory::run` an normale
Backlog-Issues (das ist der Auto-Trigger, siehe 0.4).

### 1.1 Die Pipeline-Schritte

Reihenfolge wie in `CLAUDE.md`. Jeder Skill schreibt seinen Output in Dateien (kein
Gesprächsgedächtnis nötig).

| # | Skill | Wann nötig | Ergebnis / Gate |
|---|-------|-----------|-----------------|
| 1 | `/requirements <id>` | fast immer | Spec + Akzeptanzkriterien in `docs/specs/spec-<id>-*.md`, Task-Datei befüllt |
| 2 | `/architecture <id>` | **nur bei ADR-Trigger** (siehe [Abschnitt 4](#4-menschen-gates-nicht-automatisierbar)) | ADR in `docs/adr/` |
| 3 | `/implement <id>` | immer | TDD Red→Green→Refactor; Lint + Tests grün |
| 4 | `/review <id>` | immer | `tasks/review-<id>.md`, Verdict `APPROVED` / `NEEDS_REWORK` |
| ↺ | (bei `NEEDS_REWORK`) | zurück zu `/implement` | max. **3** Iterationen (Circuit Breaker), dann eskalieren |
| 5 | `/test <id>` | immer | Test-Suite vollständig, Coverage ≥ 80 % (neuer Code: 100 % erwartet) |
| 6 | `/refactor <id>` | immer | Clean-Code-Pass, **kein** neues Verhalten, Tests bleiben grün |
| 7 | `/security-review <id>` | immer (letztes Gate vor Merge) | `tasks/security-<id>.md`, `PASSED` / `NEEDS_FIXES` |
| 8 | `/codify <id>` | immer | `tasks/codify-<id>.md`; Learnings → Regeln in `CLAUDE.md`/`PROJECT-CONTEXT.md`/Guidelines |

Alternativer Einstieg statt 1: **`/bug-fix <id>`** – von Bug/Stacktrace statt Spec
(Reproduzieren → Isolieren → Beheben → Verifizieren).

### 1.2 Vor dem Merge: Task-Datei **auf dem Branch** abschließen ⚠️

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

### 1.3 Rebasen, PR grün, mergen

```bash
git fetch origin && git rebase origin/main       # linear halten, Rebase statt Merge
git push --force-with-lease                       # nach Rebase
```

Dann **`/pr-shepherd <id>`** – fährt den PR-Lifecycle bis Auto-Merge: Rebase, CI abwarten,
Approval, Merge. Läuft ein Schritt gegen eine menschliche Entscheidung, **hält** der Shepherd via
Interrupt (siehe [Abschnitt 3](#3-interrupts--wenn-die-pipeline-hält)).

**Was danach automatisch passiert** (kein Handgriff mehr):

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

## 2. Stage-3-Modus: `run-pipeline.sh`

Wenn ein Feature spec-reif ist und man die Schritte **nicht** einzeln fahren will:

```bash
bash scripts/run-pipeline.sh <task-id>            # orchestriert implement→review↺→test→refactor→security→codify
bash scripts/run-pipeline.sh <task-id> --dry-run  # zeigt nur, was liefe (keine Claude-Aufrufe)
PR_SHEPHERD=true bash scripts/run-pipeline.sh <id> # zusätzlich PR-Lifecycle bis Auto-Merge
```

**Eigenschaften (deterministisch orchestriert, Agenten werden aufgerufen):**

- **Preflight:** PROJECT-CONTEXT ohne Platzhalter, sauberer Working Tree, Spec empfohlen,
  stale Interrupt-Sentinel wird entfernt.
- **Review-Loop** mit **Circuit Breaker**: `MAX_REVIEW_ITERATIONS` (Default 2) – danach `exit 2`,
  Mensch übernimmt.
- **Security-Gate:** `NEEDS_FIXES` → Abbruch vor Merge.
- **Interrupt nach jedem Schritt** (`FACTORY_STAGE=3`): Erkennt ein Agent eine nicht
  automatisierbare Entscheidung, ruft er `raise-interrupt.sh` und die Pipeline **stoppt hart**
  (ADR-004). Kein stiller Durchlauf.
- **Kosten-Hebel** (Env-Vars): `CLAUDE_MODEL_HEAVY`, `CLAUDE_MODEL_LIGHT`, `CLAUDE_MODEL`
  (globaler Override), `MAX_TURNS`. Tier/Turns pro Skill kommen aus `factory.defaults.yml`
  (optional `factory.config.yml`, ADR-009).

> **Kosten:** Stage 3 fährt 6+ Claude-Sessions pro Feature hintereinander – deutlich mehr Token
> als interaktive Nutzung. Für unbeaufsichtigte Läufe **in CI** siehe Async-Trigger (0.4): dort
> greift zusätzlich der Budget-Guard (Label-Eintrittstür + Concurrency=1 + Tageskappe).

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

Manuell einen Interrupt setzen (z. B. um einen Stage-3-Lauf gezielt anzuhalten):

```bash
bash scripts/raise-interrupt.sh <task-id> <TYP> "<nachricht>" ["<empfohlene aktion>"]
```

Im **Async-Trigger** (0.4) unterscheidet `factory-poll.sh` sauber: Interrupt-Sentinel vorhanden →
Label `factory::interrupted` (menschliche Entscheidung); sonst `factory::failed` (echter Fehler).

---

## 4. Menschen-Gates (nicht automatisierbar)

Diese Entscheidungen darf die Automatik **nicht** allein treffen. Sie sind bewusste Halte-Punkte.

### 4.1 Architektur-Entscheidung (ADR-Trigger)

`/implement` prüft als **Schritt 0** vier Trigger-Kategorien (Spec-002 / ADR-002). Feuert eine,
**stoppt** der Agent:

1. **Technologiewahl** – neue Library/Framework/Datenbank/externer Dienst.
2. **Architekturmuster** – z. B. Wechsel zu Event-Driven, neue Schicht, Query-Modell.
3. **Schnittstellen-Vertrag** – öffentliche API/DB-Schema-Vertrag mit Außenwirkung.
4. **Langfristige/irreversible Konsequenz** – teuer rückgängig zu machen.

→ **Aktion:** `/architecture <id>` → ADR in `docs/adr/` (mit Alternativen), dann `/implement`
weiter. In Stage 2 fragt der Agent interaktiv; in Stage 3 löst er den `ADR`-Interrupt aus.

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
gibt das Issue zur unbeaufsichtigten Bearbeitung frei (0.4). Nie an reine Backlog-/Doku-Issues.

---

## 5. Wartung: Codify, Metriken, Post-Merge

### 5.1 Self-Improvement (`/codify` nach jedem Feature)

> „Jeder Bug, den die KI einführt, wird zur Regel, die den nächsten verhindert."

`/codify <id>` extrahiert Learnings → neue Regeln in `CLAUDE.md`, `docs/factory/PROJECT-CONTEXT.md`
(Bekannte Stolpersteine) oder den Guidelines. Faustregeln aus der Praxis:

- **Stack-spezifisch** (Next/NextAuth/Drizzle/Vitest …) → `PROJECT-CONTEXT.md`, **nicht** die
  stack-agnostischen Guidelines.
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
