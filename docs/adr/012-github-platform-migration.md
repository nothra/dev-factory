# ADR 012: Plattform-Migration von GitLab auf GitHub

## Status
Accepted

## Datum
2026-07-08

## Kontext

Das dm-Factory-Template wurde ursprünglich für die dm-interne GitLab-Instanz
(`gitlab.dm-drogeriemarkt.com`) gebaut: GitLab CI (`.gitlab-ci.yml`), `glab` als CLI
für Merge Requests, Issues und Labels, GitLab Container Registry + kaniko für die
CI-Images, und der Async-Trigger (ADR-008) als GitLab Scheduled Pipeline.

Dieses Projekt (**TCH Gastro Services**) wird jedoch auf **GitHub** verwaltet
(`github.com/nothra/tch-gastro-services`). Damit passten die plattformspezifischen
Teile der Factory nicht mehr: die GitLab-Pipeline läuft auf GitHub nicht, und `glab`
ist gegen die falsche Instanz konfiguriert.

Entscheidung des Auftraggebers: GitHub **ersetzt** GitLab vollständig (kein
Parallelbetrieb), inklusive Portierung des vollautomatischen Issue-Triggers.

## Decision

Alle plattformgebundenen Bestandteile der Factory werden GitHub-nativ umgesetzt.
Die zugrundeliegenden Entscheidungen (ADR-006 Mess-Architektur, ADR-007 Post-Merge-
Verifikation, ADR-008 Async-Trigger) bleiben **inhaltlich unverändert** – nur ihre
konkrete Plattform-Umsetzung wechselt:

| Aspekt | Vorher (GitLab) | Nachher (GitHub) |
|--------|-----------------|------------------|
| CI | `.gitlab-ci.yml` | `.github/workflows/factory-ci.yml` |
| Async-Trigger | Scheduled Pipeline + `resource_group` | `.github/workflows/factory-poll.yml` (`schedule` + `concurrency`) |
| CLI (PR/Issues/Labels) | `glab` | `gh` |
| CI-Runtime | Prebuilt-Image (kaniko + Registry) | `ubuntu-latest` (yq/claude zur Laufzeit geholt) |
| PR-Update | `glab mr rebase` | `gh pr update-branch` |
| Metriken | GitLab-API (MRs, Pipelines) | GitHub-API (`gh pr list`, `gh run list`) |
| Config-Variablen | CI/CD-Variablen | Repository-Variablen/-Secrets |

Der Budget-Guard, die Label-State-Maschine (`factory::run/running/done/interrupted/failed`),
die deterministischen Quality-Gates und der Interrupt-Mechanismus (ADR-004) bleiben
identisch.

## Alternatives

### Option A: GitHub ersetzt GitLab (gewählt)
**Pros:** Ein Plattform-Pfad, keine doppelte CI-Pflege, weniger Fehlerquellen; das Repo
liegt ohnehin nur auf GitHub.
**Cons:** Rückportierung auf GitLab wäre erneut Arbeit (bewusst akzeptiert).

### Option B: Beide Plattformen parallel (Host-Erkennung)
**Pros:** Portabel; Template bliebe für GitLab- und GitHub-Projekte nutzbar.
**Cons:** Deutlich mehr Code (Host-Weiche in jedem Skript), doppelte CI-Definitionen und
doppelter Testaufwand – ohne aktuellen Nutzen, da nur GitHub gebraucht wird.

## Rationale

Single-Platform ist die einfachste korrekte Lösung für den tatsächlichen Bedarf. Die
Self-Test-Suite (`scripts/checks/tests/run-tests.sh`) wurde mitmigriert und mockt jetzt
`gh` statt `glab`; sie läuft vollständig grün und sichert die Guards der GitHub-Variante
genauso ab wie zuvor die GitLab-Variante.

## Consequences

**Positive:**
- Factory läuft ohne GitLab-Abhängigkeit vollständig auf GitHub (CI, Async-Trigger, CLI).
- Kein Prebuilt-Image/Registry nötig – GitHub-hosted Runner bringen die Tools mit.
- CI-Gates und Self-Test unverändert wirksam; Self-Test grün.

**Negative / Trade-offs:**
- Das Projekt divergiert vom GitLab-Upstream-Template – künftige Template-Verbesserungen
  müssen manuell nachgezogen und ggf. auf GitHub übersetzt werden.
- Der `factory-poll`-Workflow benötigt projektspezifisches Setup (Secret `ANTHROPIC_API_KEY`,
  Labels `factory::*`), bevor der automatische Trigger end-to-end läuft.

## Betroffene Artefakte

- `.github/workflows/factory-ci.yml`, `.github/workflows/factory-poll.yml` (neu)
- entfernt: `.gitlab-ci.yml`, `ci/factory-selftest.Dockerfile`, `ci/factory-runtime.Dockerfile`
- `scripts/factory-poll.sh`, `scripts/start-work.sh`, `scripts/metrics.sh` (glab → gh)
- `scripts/checks/pre-push.sh`, `scripts/run-pipeline.sh` (Wording MR → PR)
- `.claude/commands/{pr-shepherd,daily-metrics,post-merge-verify,setup-project}.md`
- `docs/factory/guidelines/git-workflow.md`, `scripts/checks/tests/run-tests.sh`
- Verweis-Banner in ADR-006, ADR-007, ADR-008
