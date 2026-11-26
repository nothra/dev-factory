# Task 67: pipeline-summary-task-datei-slug

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
`pipeline_summary()` in `scripts/run-pipeline.sh` sucht die Task-Datei unter `tasks/task-<id>.md` (ohne Slug) und
meldet deshalb in jedem Lauf `→ Task-Datei nicht gefunden`. Das Summary soll den Titel genau der Task-Datei zeigen,
mit der die Pipeline läuft (`tasks/task-<id>-<slug>.md`). Spec: `docs/specs/spec-67-pipeline-summary-task-datei-slug.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] AK1 – Titel wird gezeigt: Summary zeigt `→ Task <id>: <titel>` aus `tasks/task-<id>-<slug>.md`, kein `Task-Datei nicht gefunden`
- [ ] AK2 – dieselbe Datei wie der Pipeline-Start, auch bei ID-Präfix-Kollision (`task-6-…` neben `task-67-…`)
- [ ] AK3 – Titelzeile fehlt → `→ (kein Titel)`, kein Abbruch
- [ ] AK4 – Mutationsbeleg: Tests zu AK1/AK3 rot gegen `main` vor dem Fix (Kommando + Ergebnis hier)
- [ ] AK5 – keine Verhaltensänderung sonst, bestehende Suite grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Kein ADR-Trigger (Fehlerkorrektur). Testanker: Dry-Run-Scaffold des Tests zu nothra/tch-gastro-services#261 in
`scripts/checks/tests/run-tests.sh`.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Keine offen (siehe Spec).

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/67-pipeline-summary-task-datei-slug`
Erstellt: 2026-11-26 08:55
