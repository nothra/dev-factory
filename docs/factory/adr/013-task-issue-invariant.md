# ADR 013: Task-ID = GitHub-Issue-Nummer (Issue-first)

## Status
Accepted

## Datum
2026-07-08

## Kontext

Die Factory verfolgt Tasks als `tasks/task-<id>-*.md` und nutzt `<id>` als Klammer
über Branch (`feature/<id>-…`), PR-Titel (`… (#<id>)`) und – nach der GitHub-Migration
(ADR-012) – als GitHub-Issue-Nummer. Der Auto-Trigger (`factory-poll.sh`, ADR-008)
arbeitet ausschließlich issue-getrieben (Label `factory::run`).

Bisher war nicht garantiert, dass zu jedem lokalen Task auch ein GitHub-Issue existiert:
`start-work.sh` nahm eine ID entgegen, ohne ein Issue anzulegen oder dessen Existenz zu
prüfen. Ergebnis: Tasks ohne Issue-Pendant, Observability-Lücken und ein Auto-Trigger, der
solche Tasks nie sieht.

Erschwerend: GitHub vergibt Issue-/PR-Nummern sequenziell aus **einem gemeinsamen**
Nummernraum. Eine bestimmte Nummer lässt sich nicht nachträglich erzwingen.

## Decision

**Invariante:** Jede `tasks/task-<id>-*.md` hat ein GitHub-Issue #`<id>`. Die
Issue-Nummer **ist** die Task-ID.

Durchsetzung auf drei Ebenen:

1. **By construction – `start-work.sh` (Issue-first):**
   - Beschreibungs-Modus `start-work.sh <desc> [typ]`: legt zuerst das Issue an und nutzt
     dessen zurückgegebene Nummer als Task-ID → Alignment ist garantiert.
   - ID-Modus `start-work.sh <id> <desc> [typ]`: validiert, dass Issue #`<id>` existiert;
     fehlt es, bricht das Skript ab (statt einen Task ohne Pendant zu erzeugen).

2. **Audit/Reparatur – `scripts/sync-issues.sh`:**
   - Default `--check` (read-only): exit 1, wenn ein Task kein Issue hat.
   - `--create`: legt fehlende Issues an; meldet einen nicht auflösbaren Nummern-Mismatch
     laut (weil GitHub die Nummer nicht erzwingen lässt).

3. **Gate – CI-Job `issue-sync`** in `.github/workflows/factory-ci.yml` ruft
   `sync-issues.sh --check` bei jedem Push/PR. Drift wird rot, nicht still geduldet
   ("gates over trust").

4. **Umgekehrte Richtung (Issue → Task) – `factory-poll.sh`:** Der Async-Trigger startet
   aus einem Issue; `run-pipeline.sh` verlangt aber eine lokale `task-<id>-*.md`. Fehlt sie,
   **materialisiert** `factory-poll` sie aus Titel/Body des Issues (commit + best-effort push),
   bevor die Pipeline startet. So ist der Flow *„Issue anlegen → `factory::run` labeln"* turnkey,
   ohne vorheriges `start-work`. (Der Feature-Branch/PR-Fluss des eigentlichen Codes bleibt die
   separate, offene Vorbedingung V-1 aus ADR-008.)

## Alternatives

### Option A: Issue-first + Check-Gate (gewählt)
**Pros:** Alignment garantiert bei der Entstehung; Drift wird deterministisch erkannt;
kein manuelles Nachpflegen.
**Cons:** `start-work.sh` braucht `gh` (im Beschreibungs-Modus); minimale Mehrlogik.

### Option B: Nur ein Reparatur-Skript, kein Issue-first
**Pros:** Weniger Änderung an `start-work.sh`.
**Cons:** Auf GitHub nicht robust – ein nachträglich erzeugtes Issue bekommt evtl. eine
andere Nummer als die Task-ID (Nummernraum-Kollision) → Drift, die nur manuell auflösbar
ist. Behebt das Problem also nicht an der Wurzel.

## Consequences

**Positive:**
- Jeder Task ist auf GitHub sichtbar und für den Auto-Trigger erreichbar.
- Task-ID, Branch, PR und Issue-Nummer sind konsistent verknüpft.
- Self-Test-Suite deckt `sync-issues.sh` (Check/Create/Dry-run/Mismatch) mit `gh`-Mocks ab.

**Negative / Trade-offs:**
- Der Beschreibungs-Modus von `start-work.sh` benötigt ein authentifiziertes `gh`.
- Bereits vor dieser Regel angelegte Tasks müssen ggf. einmalig via `sync-issues.sh --create`
  nachgezogen werden; bei Nummern-Kollision ist manuelles Umbenennen nötig.

## Betroffene Artefakte
- `scripts/sync-issues.sh` (neu), `scripts/start-work.sh` (Issue-first + ID-Validierung)
- `.github/workflows/factory-ci.yml` (Job `issue-sync`)
- `scripts/checks/tests/run-tests.sh` (Tests für sync-issues), `docs/factory/guidelines/git-workflow.md`
