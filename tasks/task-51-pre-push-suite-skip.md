# Task 51: pre-push-suite-skip

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Das `commands.test`-Kommando des Factory-Repos überspringt die ausgelieferte Suite (~9,5 min lokal),
wenn die Änderungsmenge des Branchs gegenüber `origin/main` nur `tasks/**` und `docs/specs/**`
umfasst. Gilt gleich für pre-push-Hook und `run-pipeline.sh`-Gates; Override per Env erzwingt den
vollen Lauf; fail-closed bei unbestimmbarem Diff. Keine Änderung an ausgelieferten Dateien.
Spec: `docs/specs/spec-51-pre-push-suite-skip.md`

## Akzeptanzkriterien
<!-- Von /requirements befüllt – Volltext in der Spec -->
- [ ] AK1 – Skip bei nur `tasks/`/`docs/specs/`, Exit 0, Meldung mit Grund
- [ ] AK2 – Voller Lauf bei anderer Datei, Exit-Code durchgereicht
- [ ] AK3 – Uncommittete/untracked Dateien zählen mit
- [ ] AK4 – Umbenennung über die Pfadgrenze → voller Lauf
- [ ] AK5 – Override-Env erzwingt vollen Lauf, Meldung nennt Override
- [ ] AK6 – Gleiches Verhalten für pre-push und `run-pipeline.sh`
- [ ] AK7 – Keine Änderung an Dateien der Seite `factory`
- [ ] AK8 – Ownership-Zeile (Seite `project`) für neue Dateien, Check grün
- [ ] AK9 – Tests in der Projekt-Suite für AK1–AK5 und F1–F3
- [ ] Fehlerszenarien F1–F5 (fail-closed, Sonderzeichen, Präfix-Verwechslung) abgedeckt

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- [ ] Q3: Projekt-ADR nötig oder reicht Kommentar in `factory.config.yml` + Spec? (für `/architecture`)

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/51-pre-push-suite-skip`
Erstellt: 2026-11-09 21:20
