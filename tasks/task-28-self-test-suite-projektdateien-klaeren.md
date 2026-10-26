# Task 28: self-test-suite-projektdateien-klaeren

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Die ausgelieferte Self-Test-Suite soll keine projekteigenen Dateien des echten Repos lesen. Offen ist nur der
Label-Drift-Guard (`#431 AK-I2`), der `docs/factory/PROJECT-CONTEXT.md` liest; er bekommt eine eigene Fixture.
Fundstelle (2) und die ADR-064-D6-Ergänzung sind durch AK-28a/28c (spec-23, PR #29) erledigt; die
Config-Validierung (3) bleibt (Entscheidung Q1). Spec: `docs/specs/spec-28-self-test-suite-projektdateien.md`.

## Akzeptanzkriterien
- [ ] AK1: Label-Drift-Block grün bei verändertem/fehlendem `PROJECT-CONTEXT.md` des Repos (Fixture statt echter Datei)
- [ ] AK2: die drei Mutationsfälle schlagen unverändert an (Assertions erhalten, Vorher/Nachher-Zählung)
- [ ] AK3: Positivkontrolle – Fixture mit beschriebenem Label meldet keine Abweichung
- [ ] AK4: Konsument mit eigenem `aspects_extra` ohne Beschreibung → Suite bleibt grün
- [ ] AK5: Zustand des echten `PROJECT-CONTEXT.md`-Labelbereichs weiter geprüft (Projekt-Suite); kein Guard entfällt ersatzlos
- [ ] AK6: Guard gegen Rückfall – kein Lesezugriff auf projekteigene Dateien außer `factory.config.yml` (Negativfall + fail-closed)
- [ ] AK7: Task-Datei verweist auf AK-28a/28c als Beleg der Erledigung; ADR-064 D6 nicht doppelt ändern

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `test/28-self-test-suite-projektdateien-klaeren`
Erstellt: 2026-10-27 00:32
