# Task 67: pipeline-summary-task-datei-slug

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [x] Tests vollständig
- [ ] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
`pipeline_summary()` in `scripts/run-pipeline.sh` sucht die Task-Datei unter `tasks/task-<id>.md` (ohne Slug) und
meldet deshalb in jedem Lauf `→ Task-Datei nicht gefunden`. Das Summary soll den Titel genau der Task-Datei zeigen,
mit der die Pipeline läuft (`tasks/task-<id>-<slug>.md`). Spec: `docs/specs/spec-67-pipeline-summary-task-datei-slug.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [x] AK1 – Titel wird gezeigt: Summary zeigt `→ Task <id>: <titel>` aus `tasks/task-<id>-<slug>.md`, kein `Task-Datei nicht gefunden`
- [x] AK2 – dieselbe Datei wie der Pipeline-Start, auch bei ID-Präfix-Kollision (`task-6-…` neben `task-67-…`)
- [x] AK3 – Titelzeile fehlt → `→ (kein Titel)`, kein Abbruch
- [x] AK4 – Mutationsbeleg: Tests zu AK1/AK3 rot gegen `main` vor dem Fix (Kommando + Ergebnis hier)
  - Kommando: `bash scripts/checks/tests/run-tests.sh` mit neuen #67-Tests, `run-pipeline.sh` unverändert (Stand `main`).
  - Ergebnis: ✗ AK1 (Titel), ✗ AK1 (kein „nicht gefunden"), ✗ AK2 (Titel eigene ID), ✗ AK3 (Fallback); AK2 „Titel der Präfix-ID erscheint nicht" war grün (trivial, da gar kein Titel kam).
  - Nach Fix (`task_file="$TASK_FILE"` in `pipeline_summary()`): alle 5 #67-Prüfungen ✓.
- [x] AK5 – keine Verhaltensänderung sonst, bestehende Suite grün (Voll-Lauf: 2855 grün, 0 rot)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Kein ADR-Trigger (Fehlerkorrektur). Testanker: Dry-Run-Scaffold des Tests zu nothra/tch-gastro-services#261 in
`scripts/checks/tests/run-tests.sh`.

## Implementierungs-Notizen
- Fix: `pipeline_summary()` nutzt das beim Pipeline-Start aufgelöste `$TASK_FILE` statt eines neu gebauten `task-<id>.md`-Pfads.
- AK5 erledigt: vollständiger Lauf `bash scripts/checks/tests/run-tests.sh` (Exit 0): 2855 grün, 0 rot, alle 5 #67-Prüfungen ✓.

- Refactoring-Pass: Diff geprüft (Fix = 1 Zeile + WHY-Kommentar, Test folgt dem #261-Scaffold). Nichts zu verbessern – bewusst keine Änderung, kein neues Verhalten.

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
