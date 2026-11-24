# Task 62: adr-029-nachtrag-factory-integrity

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
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
- Runde 1 (2026-11-24): NEEDS_REWORK, 0 kritisch, 2 wichtig, 5 Nitpicks, Details in `tasks/review-62.md`. Kern: Die Aussage
  „auch der Einbindungs-PR hängt" (ADR-029, §0.7, CHANGELOG, Spec FS1) ist ungenau, offene Alt-PRs fehlen. Außerhalb des
  Scopes: OPERATING-Anhang Branch-Protection widerspricht ADR-029/§0.7, Issue noch anzulegen.
- Rework Runde 1 (2026-11-24): beide wichtigen Findings und vier Nitpicks behoben. Hängen betrifft jeden PR, dessen Branch den
  Job noch nicht enthält (`factory-ci.yml`: `pull_request` ohne Pfadfilter, Job ohne `if:`), Abhilfe Rebase. Offene Alt-PRs
  stehen als Schritt 4 in §0.7. §0.7 enthält nur die Bedienschritte, Begründung und Notfall stehen kanonisch im ADR.
  „Release-Manifest" ist einheitlich, ADR-063 hat Rückverweise, die Decision-Liste in ADR-029 nennt `factory-integrity`.
  Der Nitpick zu „ADR-063 / …" bleibt bewusst unverändert (Stil der Nachbareinträge). **Spec AK3 und Fehlerszenario 1
  korrigiert, Bestätigung durch den Menschen steht aus.**
- Runde 2 (2026-11-24): APPROVED, 0 kritisch, 0 wichtig, 3 Nitpicks (Grund für „erst mergen" ausdrücklich nennen, „offene
  PRs" auf vor der Einbindung abgezweigte eingrenzen, „Factory-PRs" präzisieren). Das Issue zum OPERATING-Anhang
  Branch-Protection ist weiterhin nicht angelegt.

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `docs/62-adr-029-nachtrag-factory-integrity`
Erstellt: 2026-11-24 00:09
