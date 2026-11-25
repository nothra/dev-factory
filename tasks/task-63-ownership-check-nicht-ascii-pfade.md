# Task 63: ownership-check-nicht-ascii-pfade

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
`scripts/checks/ownership-check.sh` soll jeden getrackten Pfad byte-genau lesen und keinen überspringen. Umlaute sind seit #22
schon behoben. Offen sind Pfade, die git auch mit `core.quotepath=false` quotet (`"`, `\`, Tab) – heute Falsch-Rot –, und
Pfade mit `|`, die der Tabellenmodus still überspringt (fail-open). Ein Zeilenumbruch im Pfad wird fail-closed behandelt.
Spec: `docs/specs/spec-63-ownership-check-nicht-ascii-pfade.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt – Volltext in der Spec -->
- [ ] AK1 – Tabellenmodus, Nicht-ASCII-Pfad unquotet zugeordnet und gelistet (Regression)
- [ ] AK2 – Tabellenmodus, `"`/`\`/Tab im Pfad byte-genau zugeordnet und gelistet
- [ ] AK3 – Tabellenmodus, `|`-Pfad gezählt und in `--list factory`
- [ ] AK4 – Tabellenmodus, `|`-Pfad ohne Zuordnung → Exit 1 mit `✗`-Meldung
- [ ] AK5 – Lock-Modus, `"`/`\` im Pfad → Exit 0, Listen byte-genau
- [ ] AK6 – Zeilenumbruch im Pfad → Exit 2, keine zerteilte Ausgabe
- [ ] AK7 – Mutationsbeleg: Tests zu AK2–AK6 rot gegen `main` vor dem Fix (Beleg hier eintragen)
- [ ] AK8 – keine Verhaltensänderung für das Repo selbst, Suite grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
- Kein ADR-Trigger (lokaler Bugfix, kein neues Format, keine neue Abhängigkeit) – `/architecture` entfällt.
- Reproduktion: Wegwerf-Repo mit `docs/a"b.md`, `docs/a\b.md`, `docs/a|b.md`, Tab-Pfad und Muster `docs/**` →
  „3 von 5 Dateien ohne eindeutige Zuordnung" bei 6 getrackten Dateien (`|`-Pfad fehlt in der Zählung).

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
- [x] Zeilenumbruch-Pfad: Exit 2 wie AK6 – bestätigt von Ralf (2026-11-25)

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/63-ownership-check-nicht-ascii-pfade`
Erstellt: 2026-11-25 20:43
