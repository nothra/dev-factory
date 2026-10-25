# Architecture Decision Records (ADRs)

This directory contains the architectural decisions of the **Development Factory** (pipeline,
skills, gates, configuration). Decisions about an adopting project's own application live in that
project's repository.

## What is an ADR?

An ADR documents an important architectural decision:
- **Context:** Why was the decision necessary?
- **Decision:** What was decided?
- **Alternatives:** What was rejected – and why?
- **Consequences:** What changes as a result?

## When to create an ADR?

- When choosing technology (framework, database, messaging)
- When deciding on architectural patterns (Hexagonal vs. Layered)
- When making decisions with long-term consequences
- When the team has discussed and reached an agreement

**Not for:** Implementation details that belong in a PR description.

## Numbering

Format: `NNN-short-title.md` (e.g. `001-database-selection.md`)
Numbers are sequential and never reused. The factory and the project keep **separate** number
sequences (ADR-063 D8): a plain `ADR-NNN` in a factory file means this directory, a project file
writes `Factory-ADR-NNN` for a decision recorded here. The numbers below are the historical ones
from the shared sequence and stay unchanged.

## Status values

| Status | Meaning |
|--------|---------|
| `Proposed` | Under discussion, not yet decided |
| `Accepted` | Decided and active |
| `Deprecated` | No longer recommended, but still present |
| `Superseded by ADR-NNN` | Replaced by a newer decision |

---

## Template

Create a new ADR with `/architecture` or manually using this template:

```markdown
# ADR NNN: [Title]

## Status
Proposed

## Date
YYYY-MM-DD

## Context
[Why is this decision necessary? What problem is being solved?]

## Decision
[What was decided?]

## Alternatives

### Option A: [Name]
**Pros:** ...
**Cons:** ...

### Option B: [Name]
**Pros:** ...
**Cons:** ...

## Rationale
[Why Option X? Which criteria were decisive?]

## Consequences
**Positive:**
- ...

**Negative / Trade-offs:**
- ...
```

---

## Index

Every ADR in this directory, in number order (the test suite checks that this list matches the
directory). Duplicate numbers (040) are known, see nothra/tch-gastro-services#321.

| Nr. | Titel | Status |
|---|---|---|
| 001 | [Dynamic Workflows as Complementary Orchestration](001-dynamic-workflows-complementary-orchestration.md) | Proposed |
| 002 | [Technische Umsetzung des ADR-Trigger-Checks im Coding-Agenten](002-adr-trigger-check-implementation.md) | Proposed |
| 003 | [Hook Input via stdin JSON, Centrally Parsed in check.sh](003-hook-input-via-stdin-json.md) | Accepted |
| 004 | [Stage-3-Interrupt – deterministischer Stopp bei menschlicher Entscheidung](004-stage3-interrupt-mechanism.md) | Accepted |
| 005 | [Kanonische Pipeline-Reihenfolge – Security-Review als letztes Gate vor Merge](005-pipeline-step-order.md) | Accepted |
| 006 | [Mess-Architektur – zwei Ebenen: Prozess (Git/GitLab) und Telemetrie (OTEL/Gateway)](006-measurement-architecture.md) | Accepted |
| 007 | [Post-Merge-Verifikation als CI-on-main-Pattern](007-post-merge-verification.md) | Accepted |
| 008 | [Async-Trigger – Pipeline-Start per GitLab-Event statt Terminal](008-async-trigger-mechanism.md) | Accepted |
| 009 | [Geführte Factory-Konfiguration — kanonische, geschichtete Config](009-factory-configuration.md) | Accepted |
| 010 | [Config-Validierung über yq-natives Gate (verfeinert ADR-009)](010-config-validation-gate.md) | Accepted |
| 011 | [Annotations-Konvention für Config-Begründungen (verfeinert ADR-009)](011-config-annotation-convention.md) | Accepted |
| 012 | [Plattform-Migration von GitLab auf GitHub](012-github-platform-migration.md) | Accepted |
| 013 | [Task-ID = GitHub-Issue-Nummer (Issue-first)](013-task-issue-invariant.md) | Accepted |
| 018 | [Zentraler Issue-Seam mit Label-Funktion (`create-issue`)](018-central-issue-seam.md) | Accepted |
| 019 | [Stage-3 Commit-Seam & Report-Guard für `run_skill()`](019-stage3-commit-seam-report-guard.md) | Accepted |
| 029 | [Schutz des `main`-Branch via GitHub Repository-Ruleset](029-branch-protection-main-ruleset.md) | Accepted |
| 030 | [pr-shepherd – Direct-Merge-Fallback bei bereits mergebarem PR](030-pr-shepherd-direct-merge-fallback.md) | Accepted |
| 037 | [`/codify`-Learnings aus dem @import-Kontext in `docs/factory/lessons/` auslagern](037-lessons-auslagern-aus-import-kontext.md) | Accepted |
| 038 | [Größenabhängige Modell-Tier-Wahl (dynamisches Tiering)](038-groessenabhaengige-modell-tier-wahl.md) | Accepted |
| 040 | [Idempotenter Issue-Seam für Pipeline-Retries](040-idempotenter-issue-seam-fuer-pipeline-retries.md) | Accepted |
| 040 | [Deterministische Endzustands-Verifikation der Pipeline (agenten-signal-unabhängiger Backstop)](040-pipeline-endzustands-verifikation.md) | Accepted |
| 041 | [`config-validation-check.sh` als eigener CI-Required-Check](041-config-validation-ci-required-check.md) | Accepted |
| 042 | [Hook-Installation über eine gemeinsame Quelle (`install-hooks.sh`)](042-hook-installation-single-source.md) | Accepted |
| 043 | [Schwelle für die autonome Issue-Anlage der Review-Skills](043-schwelle-fuer-autonome-issue-anlage.md) | Accepted |
| 045 | [Prozess-Messung läuft je Pipeline-Lauf (fail-open Exit-Hook) statt im Zeittakt](045-prozess-messung-je-pipeline-lauf.md) | Accepted |
| 047 | [`@import`-Kontext der 5 Guidelines nach Erzwungenheit schneiden](047-import-kontext-guidelines-nach-erzwungenheit.md) | Accepted |
| 049 | [Telemetrie-Persistenz je Pipeline-Lauf – in `run-pipeline.sh` integriert, Default an, personenfrei getrackt in Git](049-telemetrie-persistenz-je-pipeline-lauf.md) | Accepted |
| 051 | [Turn-Limit-Ceiling für `/implement` von 50 auf 80 anheben (erweitert ADR-009 §6 / ADR-010)](051-turn-limit-ceiling-implement-80.md) | Accepted |
| 063 | [Factory in eigenes Repo – versionierte Übernahme per Manifest](063-factory-eigenes-repo-vendored-manifest.md) | Accepted |
| 064 | [Konsumenten-Vertrag – `factory.lock` als Ownership-Quelle, Lock-Format](064-konsumenten-vertrag-lock-als-ownership-quelle.md) | Accepted |
