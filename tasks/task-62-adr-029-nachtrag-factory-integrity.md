# Task 62: adr-029-nachtrag-factory-integrity

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Nachtrag in Factory-ADR-029 zu `factory-integrity` als Required Check für Konsumenten-Repos, Einrichtungsschritt in
`OPERATING.md`, CHANGELOG-Eintrag. Spec: `docs/specs/spec-62-adr-029-nachtrag-factory-integrity.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] ADR-029: Nachtrag im Abschnitt Bezug zu anderen ADRs mit Entscheidung (Konsumenten Required Check, Factory-Repo No-op)
- [ ] ADR-029: Begründung (Ruleset = einzige serverseitige Durchsetzung)
- [ ] ADR-029: Reihenfolge für Konsumenten (erst Erst-Einbindung mergen, dann Ruleset)
- [ ] ADR-029: Fail-closed-Folge und Notfall
- [ ] ADR-029: Soll-Ist-Abgleich (`gh api`, Platzhalter) mit Erwartung
- [ ] ADR-029: Status/JSON unverändert, Nachtrag widerspruchsfrei (Muster ADR-064)
- [ ] OPERATING.md: neuer Unterabschnitt 0.7 Required Check `factory-integrity` eintragen (nach dem ersten Merge), Verweis aus §5.5a, TOC ggf. angepasst
- [ ] ADR-Index (`adr/README.md`) konsistent
- [ ] CHANGELOG `Unreleased` mit Eintrag zu #62
- [ ] Gates grün (`pre-commit.sh`, `pre-push.sh`)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- [x] Ort des OPERATING-Schritts: neuer Unterabschnitt 0.7, §5.5a verweist darauf (Mensch, 2026-11-24).
- [x] Neutrale Formulierung („zusätzlich zu den bestehenden Checks") statt Zählung der Checks (Mensch, 2026-11-24).

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `docs/62-adr-029-nachtrag-factory-integrity`
Erstellt: 2026-11-24 00:09
