# Task 24: factory-update-workflow-update-pr

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Übernommener Workflow `factory-update.yml` (täglich + `workflow_dispatch`): erkennt eine neuere
Factory-Version im Quell-Repo, holt sie per `factory-sync.sh` ab und pflegt **einen** Update-PR auf dem
festen Branch `chore/factory-update` (Release Notes im Body, PAT `FACTORY_SYNC_TOKEN`, kein Auto-Merge).
Teil-Task T2a-3 von `nothra/tch-gastro-services#428`. Spec: `docs/specs/spec-24-factory-update-workflow-update-pr.md`.

## Akzeptanzkriterien
<!-- Volltext: docs/specs/spec-24-factory-update-workflow-update-pr.md -->
- [ ] AK2.2d – neue Version → Update-PR auf `chore/factory-update` mit Release Notes, ohne menschliches Zutun
- [ ] AK2.4 – Push/PR mit `FACTORY_SYNC_TOKEN` (nicht `GITHUB_TOKEN`), nie Merge/Auto-Merge
- [ ] AK2.4b – keine neuere Version / kein Release → nichts geändert, Lauf grün
- [ ] F3 – mehrere Versionen → höchstens ein offener PR, neu aufgebaut auf die neueste
- [ ] AK-24a – Release Notes jeder übersprungenen Version im Body
- [ ] AK-24b – PR schon auf neuester Version → Branch unberührt (auch mit Fremd-Commits)
- [ ] AK-24c – neuere Version ersetzt Fremd-Commits sichtbar (Hinweis im Body)
- [ ] AK-24d – ohne Merge geschlossene Version wird nicht erneut angeboten
- [ ] AK-24e – ohne `factory.lock` (Factory-Repo): No-op, grün, ohne Token

### Fehlerszenarien
- [ ] F1 – rote Gates im Update-PR: PR bleibt offen, `main` unverändert, Workflow schreibt nie auf `main`
- [ ] FS-T2.3 – Token fehlt/abgelehnt → Lauf rot vor jedem weiteren Schritt, auch ohne neue Version
- [ ] F-24.1 – Abholung scheitert → rot, kein Push, bestehender PR unverändert
- [ ] F-24.2 – Release-Liste nicht lesbar → rot (fail-closed)
- [ ] F-24.3 – `factory.lock` unlesbar → rot, kein Rückfall auf No-op

### Begleitend
- [ ] `OPERATING.md`: Token anlegen, Rechte, Ablauf, Rotation
- [ ] `OWNERSHIP.md`: je neue Datei eine Zeile

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- Q-24.1–Q-24.4 entschieden 2026-10-30 (siehe Spec).
- Q-24.5 (Ort der Logik, Testbarkeit, Erkennung von Branch-/PR-Stand, Labels, Draft) → `/architecture`, Nachtrag zu Factory-ADR-063 D2.
- Q-24.6 (Token-Rechte, ggf. *workflows:write*) → `/architecture`.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/24-factory-update-workflow-update-pr`
Erstellt: 2026-10-30 21:48
