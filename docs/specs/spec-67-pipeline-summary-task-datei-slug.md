# Spec: Pipeline-Summary findet die Task-Datei über `task-<id>-*.md` (#67)

## Kontext

`scripts/run-pipeline.sh` endet mit `pipeline_summary()`. Der Abschnitt „Implementierung" soll den Titel der Task
zeigen. Die Funktion sucht die Task-Datei aber unter `tasks/task-<id>.md` (ohne Slug). Task-Dateien heißen seit
`start-work.sh` immer `tasks/task-<id>-<kurzbeschreibung>.md` (Factory-ADR-013) – der Pfad trifft nie, jedes Summary
zeigt `→ Task-Datei nicht gefunden` (gefunden beim Lauf von Task 41, PR #65).

Der Pipeline-Start selbst löst die Task-Datei bereits richtig über `task-<id>-*.md` auf und bricht ab, wenn keine
existiert. Das Summary ist also die einzige Stelle, die danebengreift; die Auswirkung ist rein die Anzeige, der Lauf
selbst ist nicht betroffen.

## Scope

**Inbegriffen:**
- Abschnitt „Implementierung" in `pipeline_summary()` (`scripts/run-pipeline.sh`): zeigt den Titel genau der
  Task-Datei, mit der die Pipeline läuft.
- Regressionstest in der ausgelieferten Suite `scripts/checks/tests/run-tests.sh` über den echten Summary-Pfad
  (`run-pipeline.sh <id> --dry-run`, wie der bestehende Test zu nothra/tch-gastro-services#261), mit Mutationsbeleg.

**Nicht inbegriffen:**
- Die Auflösung der Task-Datei beim Pipeline-Start (Suchtiefe, Reihenfolge bei mehreren Treffern) – sie bleibt, wie
  sie ist; das Summary übernimmt ihr Ergebnis.
- Die übrigen Summary-Abschnitte (Review, Security, Codify) – deren Pfade kommen bereits aus `report_file` bzw. sind
  slug-los benannt (`codify-<id>.md`) und treffen.
- Andere Skripte, die Task-Dateien suchen (`factory-poll.sh`, `sync-issues.sh`, `start-work.sh`). Gleichartige
  Fehler, die `/implement` dabei auffallen, kommen nach der Schwelle in `git-workflow.md` in `kleinfunde.md` oder ein
  Issue.
- Format der Task-Datei und ihrer Titelzeile.

## Akzeptanzkriterien

> Gemeinsame Testbedingung: Wegwerf-Repo nach dem Muster des Dry-Run-Scaffolds aus dem Test zu
> nothra/tch-gastro-services#261; geprüft wird die Ausgabe von `run-pipeline.sh <id> --dry-run` im Abschnitt
> „Implementierung".

- [ ] **AK1 – Titel wird gezeigt:** GIVEN eine Task-Datei `tasks/task-<id>-<slug>.md` mit erster Überschrift
  `# Task <id>: <titel>`, WHEN `run-pipeline.sh <id> --dry-run` bis zum Summary läuft, THEN steht unter
  „Implementierung" `→ Task <id>: <titel>`, und die Ausgabe enthält nicht `Task-Datei nicht gefunden`.
- [ ] **AK2 – dieselbe Datei wie der Pipeline-Start:** GIVEN neben `tasks/task-<id>-<slug>.md` existiert eine
  Task-Datei einer anderen ID, deren Nummer mit `<id>` beginnt (z. B. `task-6-…` und `task-67-…`), WHEN die Pipeline
  für die kürzere ID läuft, THEN zeigt das Summary den Titel der Datei dieser ID, nicht den der anderen.
- [ ] **AK3 – Titelzeile fehlt:** GIVEN die Task-Datei existiert, enthält aber keine Zeile, die mit `# ` beginnt,
  WHEN das Summary läuft, THEN steht unter „Implementierung" `→ (kein Titel)` (der im Code bereits vorgesehene
  Fallback), der Lauf endet nicht wegen des fehlenden Titels mit einem Fehler.
- [ ] **AK4 – Mutationsbeleg:** GIVEN die Fassung von `main` vor diesem Fix, WHEN die Tests zu AK1 und AK3 gegen sie
  laufen, THEN ist jeder davon rot. Kommando und Ergebnis stehen in der Task-Datei.
- [ ] **AK5 – keine Verhaltensänderung sonst:** GIVEN die übrigen Summary-Abschnitte und der Pipeline-Start, WHEN die
  bestehende Suite läuft, THEN bleibt sie grün; Ausgaben außerhalb der Titelzeile von „Implementierung" ändern sich
  nicht.

## Fehlerszenarien

- [ ] Keine Task-Datei zur ID → unverändert: der Pipeline-Start bricht mit Exit 1 ab, bevor das Summary läuft
  (bestehendes Verhalten, keine neue Meldung).
- [ ] Titelzeile fehlt → `(kein Titel)` (AK3).

## Offene Fragen

- [x] **ADR nötig?** Nein – Fehlerkorrektur ohne Architekturentscheidung, kein ADR-Trigger.
- [x] **Greift der `(kein Titel)`-Fallback heute überhaupt?** Ja – `run-pipeline.sh` läuft mit `set -o pipefail`,
  ein fehlschlagendes `grep` lässt die Kette scheitern und den Fallback greifen (geprüft 2026-11-26). Er war nur
  hinter dem Pfadfehler nie erreichbar; AK3 sichert ihn als Regression ab.
