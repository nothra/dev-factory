# Task 38: release-v070

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Release v0.7.0 vorbereiten (Muster v0.6.1: #20/#21): CHANGELOG-Abschnitt `v0.7.0 – 2026-10-31` aus `Unreleased`,
Versionszeile in `docs/factory/FACTORY.md`. Inhalt: T2a (#22, #23, #24) plus #27, #28, #32. Reihenfolge laut
Factory-ADR-063 Nachtrag 2026-10-24 Q1/Q6: Factory-PRs → Release v0.7.0 → `nothra/tch-gastro-services#440`.
Nicht im Release: #37 (kommt in v0.7.1), #30, #35, #15, #14.

## Akzeptanzkriterien
- [x] `CHANGELOG.md`: `## v0.7.0 – 2026-10-31` aus `Unreleased`, leeres `## Unreleased` darüber
- [x] Eintrag Update-Workflow (#24, PR #36) unter „Neu“; #27, #28, #32 unter „Geändert“ abgedeckt
- [x] „Breaking“ geprüft (MINOR darf brechen, Factory-ADR-063 D6): `OWNERSHIP.md` nicht mehr ausgeliefert, Integritäts-Gate
- [x] „Bekannte Einschränkungen“: #37 offen, `FACTORY_SYNC_TOKEN` erst ab v0.7.1 hinterlegen (FS-T2.3)
- [x] `docs/factory/FACTORY.md`: Version v0.7.0; `factory-release-check.sh v0.7.0` ok
- [ ] Gates grün, PR gemergt
- [ ] Tag `v0.7.0` (setzt der Mensch) → `release.yml` legt GitHub Release mit Asset `factory-release.json` an

## Technische Notizen
Reines Doku-Release, keine Pipeline (wie v0.6.1). Text nach dem Vorgehen von `/release-notes` aus Task-Dateien,
Commits seit `v0.6.1` und Codify-Reports erzeugt, aber im Format dieses `CHANGELOG.md` (deutsch, `## vX.Y.Z – Datum`)
statt in `docs/CHANGELOG.md` im Keep-a-Changelog-Format, das der Skill vorgibt.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `docs/38-release-v070`
Erstellt: 2026-10-31 14:44
