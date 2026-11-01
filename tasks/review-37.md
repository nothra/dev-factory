# Review: Task 37

> Iteration 2 (nach Rework zu Iteration 1, Commit `212cc25`). Runden 1–3 direkt im Orchestrator-Kontext (Lesson
> „Fork-Kontamination“). Geprüft: `git diff bd4274c..HEAD` (Rework) und erneut die tragenden Stellen aus
> `git diff origin/main...HEAD`; Suite grün (Pre-Push-Gate am Rework-Commit).
> **Iteration 1 – alle umgesetzt:** W1 geschützte Pfade in `verify_bundle` (Test + Mutation), W2 `overwrite: true` (Wiring-Anker +
> Mutation), W3 Spec-AK-37d angeglichen; Nitpicks Drift-Guard `COMPOSED_TARGETS`, `pub_37`-Entdopplung, CHANGELOG-Hinweis.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)
- [ ] docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md (E18, Prüfliste) und docs/factory/OPERATING.md (§0.6 „Aufbau des Workflows“, Klammer der `publish`-Prüfungen) – Doku-Drift (Lesson nothra/tch-gastro-services#211/#176): der Rework hat in `verify_bundle` die Ablehnung eines Manifests mit geschützten Stellen (Projektbereiche, Anpassungsstellen; `fl_protected_findings`, wie `factory-sync.sh`) ergänzt, die beschriebene Mechanik in E18 und in der Aufzählung in §0.6 nennt diese Prüfung nicht. Fix: in E18 („prüft vor dem Push, alle Prüfungen fail-closed“) und in der Klammer von §0.6 „keine geschützten Stellen im Manifest“ ergänzen; ein Doku-Guard-Anker (`ops_ok_37`/`adr_ok_37`) mit Mutation zieht nach.

## Nitpicks (optional)
- [ ] scripts/factory-update.sh:177 (`verify_bundle`, ~60 Zeilen) – eine Funktion mit fünf Aufgaben (Bundle laden, Commit-Form, Manifest holen/prüfen, Pfad-/Modusprüfung, Hash-Prüfung); Clean Code („kleine Funktionen“) – Aufteilung in `load_bundle`, `verify_manifest`, `verify_changed_paths`, `verify_hashes` ist Aufgabe des folgenden `/refactor` (kein neues Verhalten).
- [ ] scripts/checks/tests/factory-lock-tests.sh (`PROT_37`) – das Fixture-Snippet ist eine einzige, stark escapte Zeile und schwer lesbar; als kleine Funktion `craft_protected_manifest_37` wäre es wartbarer (`/refactor`).

## Positives
- Alle drei Wichtigen aus Iteration 1 sauber und mit Beleg behoben: der neue Protected-Check ist test- und mutationsgedeckt, der Re-run-Fall ist im Wiring-Prüfer verankert, die Spec trägt die tatsächliche Abweichung.
- Der Drift-Guard `COMPOSED_TARGETS` ↔ `factory-sync.sh` ist in beide Richtungen mutiert – genau das Muster aus den Lessons (je Seite ein Negativtest).
- Keine neuen Pfade/Dateien, `OWNERSHIP.md` unberührt; die Suiten sind grün, SIGPIPE-/pipefail-Fallen im neuen Testcode vermieden (Ausgabe vor `grep -q` gefangen).
- Restrisiko im ADR weiterhin ehrlich benannt; menschliche Schritte (Environment, Secret, Beleg Q-37.3) sind als solche markiert.

## Empfehlung
NEEDS_REWORK
