# Task 27: ownership-verweise-modus-neutral

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Ausgelieferte Dateien formulieren die Zuordnungsregel (Lesson-/Kleinfund-Ort, Besitzer-Kopf) über
`docs/factory/OWNERSHIP.md`, das seit Factory-ADR-064 D5 nicht mehr ausgeliefert wird – im Konsumenten
tote Links. Neue Bezugsquelle: `bash scripts/checks/ownership-check.sh --list factory` (beide Modi).
Spec: `docs/specs/spec-27-ownership-verweise-modus-neutral.md`.

## Akzeptanzkriterien
<!-- Volltext GIVEN/WHEN/THEN: docs/specs/spec-27-ownership-verweise-modus-neutral.md -->
- [ ] AK1: die elf Scope-Dateien nennen das Kommando, kein Link/Pfad auf `OWNERSHIP.md`
- [ ] AK2: Formulierung in Tabellen- und Lock-Modus ausführbar, ohne toten Link
- [ ] AK3: Zuordnungsregel inhaltlich unverändert, nur die Bezugsquelle ist neu
- [ ] AK4: Tests AK-C5/AK-L1 prüfen das Kommando (Mutationsbeleg)
- [ ] AK5: Guard – `OWNERSHIP.md`-Verweis in einer Datei der Seite `factory` → rot mit Datei:Zeile
- [ ] AK6: Ausnahmeliste nur für die Nicht-Scope-Klassen, begründet, keine ganze Scope-Datei ausgenommen
- [ ] AK7: Guard konsumenten-neutral (Lock-Modus, liest keine Projektdatei)
- [ ] AK8: pre-push und beide Suiten grün
- [ ] F1: Guard fail-closed, wenn die Dateimenge nicht bestimmbar ist
- [ ] F2: Guard erkennt alle heutigen Verweisformen, auch über Zeilenumbrüche
- [ ] F3: kein Dauer-Rot durch die eigene Suchphrase

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Keine offen – Umfang, Bezugsquelle und Guard am 2026-10-28 entschieden (siehe Spec).

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `docs/27-ownership-verweise-modus-neutral`
Erstellt: 2026-10-28 21:04
