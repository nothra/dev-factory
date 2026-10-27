# Task 32: import-deckel-test-fixture

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Der @import-Deckel-Test der ausgelieferten Suite liest über `import-context-limit-check.sh` `CLAUDE.md` und
`PROJECT-CONTEXT.md` des Konsumenten (indirekter Leser, vom AK6-Guard aus #28 nicht erfasst). Fix: Test aus der
ausgelieferten Suite in die Projekt-Suite verschieben, AK6-Guard um indirekte Leser erweitern.
Spec: `docs/specs/spec-32-import-deckel-test-fixture.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] **AK1** Kein Falsch-Rot der ausgelieferten Suite durch fehlende/aufgeblähte Konsumenten-Dateien (Fixture-Lauf)
- [ ] **AK1a** Ausgelieferte Suite prüft die Dauerkontext-Größe des echten Repos nicht (Projekt-QS, keine Factory-Funktionsprüfung – Entscheidung Mensch)
- [ ] **AK2** Deckel-Verhaltenstests bleiben vollständig; nur der Aufruf gegen die echte Wurzel entfällt
- [ ] **AK3** Projekt-Suite (Projekt-QS) prüft den realen @import-Stand (Mutation belegt)
- [ ] **AK4** AK6-Guard (#28) erkennt Check-Skript-Aufrufe gegen die echte Wurzel (Negativfall, Kontrolle, fail-closed)
- [ ] **AK5** Erweiterter Guard im Ist-Stand grün oder weitere Treffer behoben/mit Issue dokumentiert
- [ ] **AK6** Gates und beide Suiten grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- Lösungsort der Realstand-Assertion und Erkennungsmuster des Guards → `/architecture` bzw. `/implement` (siehe Spec)

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/32-import-deckel-test-fixture`
Erstellt: 2026-10-27 10:28
