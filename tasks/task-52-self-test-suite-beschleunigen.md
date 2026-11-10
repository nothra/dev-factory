# Task 52: self-test-suite-beschleunigen

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Laufzeit der ausgelieferten Self-Test-Suite senken, ohne Abdeckung zu verlieren. Schwerpunkt ist
`scripts/checks/tests/factory-lock-tests.sh` (362 von 566 s lokal). Parallele Ausführung ist erlaubt.
Spec: [`docs/specs/spec-52-self-test-suite-beschleunigen.md`](../docs/specs/spec-52-self-test-suite-beschleunigen.md)

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] AK1 – Profiling vorher/nachher je Abschnitt (lokal Median aus 3, CI), Methode ohne Zeilen-Zuordnungsartefakt
- [ ] AK2 – `factory-lock-tests.sh` lokal ≤ 181 s
- [ ] AK3 – gesamte Suite lokal (macOS) ≤ 240 s
- [ ] AK4 – CI-Job `factory-self-test` nicht langsamer als vorher
- [ ] AK5 – Anzahl der Assertions gleich; jede Namens-/Reihenfolge-Abweichung begründet
- [ ] AK6 – jede Assertion prüft denselben Sachverhalt mit derselben Erwartung
- [ ] AK7 – Rot-Nachweis je geändertem Fixture-Muster dokumentiert
- [ ] AK8 – geteilte Basis-Fixture bleibt unverändert (Fingerprint-Test)
- [ ] AK9 – Abschnitte reihenfolge-unabhängig
- [ ] AK10 – parallel: PASS/FAIL zusammengeführt, Exit ≠ 0 bei Rot, Ausgabe nicht verschränkt (entfällt ohne Parallelisierung)
- [ ] AK11 – parallel: abgebrochene Gruppe → Suite rot, nie als grün gelesen (entfällt ohne Parallelisierung)
- [ ] AK12 – konsumenten-neutral (Fixture-Lauf grün, kein Node/DB)
- [ ] AK13 – grün auf macOS (bash 3.2) und `ubuntu-latest`
- [ ] AK14 – keine Wegwerf-Verzeichnisse/Hintergrundprozesse nach Lauf (auch rot/Signal)
- [ ] AK15 – Ownership-Check grün für neue Dateien
- [ ] F1–F5 – Fehlerszenarien der Spec abgedeckt

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- [ ] Q5 (`/architecture`): Ziel ≤ 240 s ist bei Scope „nur factory-lock“ praktisch nur mit Parallelisierung erreichbar – Weg + ADR-Trigger prüfen
- [ ] Q6 (`/architecture`): Parallelisierung auch in CI/bei Konsumenten, Schalter für sequenziellen Lauf?

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `test/52-self-test-suite-beschleunigen`
Erstellt: 2026-11-10 02:18
