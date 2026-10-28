# Task 27: ownership-verweise-modus-neutral

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [ ] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Ausgelieferte Dateien formulieren die Zuordnungsregel (Lesson-/Kleinfund-Ort, Besitzer-Kopf) über
`docs/factory/OWNERSHIP.md`, das seit Factory-ADR-064 D5 nicht mehr ausgeliefert wird – im Konsumenten
tote Links. Neue Bezugsquelle: `bash scripts/checks/ownership-check.sh --list factory` (beide Modi).
Spec: `docs/specs/spec-27-ownership-verweise-modus-neutral.md`.

## Akzeptanzkriterien
<!-- Volltext GIVEN/WHEN/THEN: docs/specs/spec-27-ownership-verweise-modus-neutral.md -->
- [x] AK1: die elf Scope-Dateien nennen das Kommando, kein Link/Pfad auf `OWNERSHIP.md`
- [x] AK2: Formulierung in Tabellen- und Lock-Modus ausführbar, ohne toten Link
- [x] AK3: Zuordnungsregel inhaltlich unverändert, nur die Bezugsquelle ist neu
- [x] AK4: Tests AK-C5/AK-L1 prüfen das Kommando (Mutationsbeleg)
- [x] AK5: Guard – `OWNERSHIP.md`-Verweis in einer Datei der Seite `factory` → rot mit Datei:Zeile
- [x] AK6: Ausnahmeliste nur für die Nicht-Scope-Klassen, begründet, keine ganze Scope-Datei ausgenommen
- [x] AK7: Guard konsumenten-neutral (Lock-Modus, liest keine Projektdatei)
- [x] AK8: pre-push und beide Suiten grün
- [x] F1: Guard fail-closed, wenn die Dateimenge nicht bestimmbar ist
- [x] F2: Guard erkennt alle heutigen Verweisformen, auch über Zeilenumbrüche
- [x] F3: kein Dauer-Rot durch die eigene Suchphrase

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

## Test-Notizen (/test)
- Kein Coverage-Werkzeug im Repo (Bash). Zeilenabdeckung des Guards bewertet über die fail-closed-Zweige einzeln.
- Mutationsbelege (je ein Mutant, F1-Test wurde rot): leere Dateimenge → fail-open; Kommando-Exit ignoriert; unlesbare gelistete Datei ignoriert.
- Beide Suiten grün (1956 / 145). Kein Produktionscode geändert.

## Refactoring-Notizen (/refactor)
- Dreifach duplizierter „Scan ausführen + Ausgabe greppen"-Block in `run-tests.sh` (F2/AK6) in den Helfer `own_ref_scan_reports_27` gezogen; die pipefail-Begründung steht dort einmal. Kein neues Verhalten, Suite weiter 1956 grün.
- Review-Nitpicks (Zeilenumbruch in Lesson-Köpfen, Spec-Checkboxen) bewusst unverändert: kosmetisch, ohne Wirkung.
