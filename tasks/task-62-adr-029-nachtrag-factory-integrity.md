# Task 62: adr-029-nachtrag-factory-integrity

## Status
- [x] In Bearbeitung
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
- [x] ADR-029: Nachtrag im Abschnitt Bezug zu anderen ADRs mit Entscheidung (Konsumenten Required Check, Factory-Repo No-op)
- [x] ADR-029: Begründung (Ruleset = einzige serverseitige Durchsetzung)
- [x] ADR-029: Reihenfolge für Konsumenten (erst Erst-Einbindung mergen, dann Ruleset)
- [x] ADR-029: Fail-closed-Folge und Notfall
- [x] ADR-029: Soll-Ist-Abgleich (`gh api`, Platzhalter) mit Erwartung
- [x] ADR-029: Status/JSON unverändert, Nachtrag widerspruchsfrei (Muster ADR-064)
- [x] OPERATING.md: neuer Unterabschnitt 0.7 Required Check `factory-integrity` eintragen (nach dem ersten Merge), Verweis aus §5.5a, TOC ggf. angepasst
- [x] ADR-Index (`adr/README.md`) konsistent
- [x] CHANGELOG `Unreleased` mit Eintrag zu #62
- [x] Gates grün (`pre-commit.sh`, `pre-push.sh`)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
- Docs-only, kein ADR-Trigger: der Nachtrag ergänzt ADR-029 im Muster ADR-041/064, kein neuer ADR (Spec „Form").
- Kein neuer Test: die Spec schließt Änderungen an Skripten und Tests aus; die Prüfung übernehmen die bestehenden Gates
  (Ownership, Herkunftsbegriffe, Import-Deckel). Keine neue getrackte Datei, `OWNERSHIP.md` bleibt unverändert.
- TOC in `OPERATING.md` listet nur die Hauptabschnitte, daher keine Änderung für 0.7. Anker `#07-required-check-…` folgt dem
  Slug-Muster von 0.6.
- ADR-Index Zeile 029 unverändert (Titel und Status `Accepted` stimmen, ein Nachtrag ändert den Status nicht).
- Notfallverfahren konkretisiert: Vorfall als Issue mit Ursache, Zeitraum und in dieser Zeit gemergten PRs.

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
