# Task 63: ownership-check-nicht-ascii-pfade

## Status
- [x] In Bearbeitung
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
- [x] AK1 – Tabellenmodus, Nicht-ASCII-Pfad unquotet zugeordnet und gelistet (Regression)
- [x] AK2 – Tabellenmodus, `"`/`\`/Tab im Pfad byte-genau zugeordnet und gelistet
- [x] AK3 – Tabellenmodus, `|`-Pfad gezählt und in `--list factory`
- [x] AK4 – Tabellenmodus, `|`-Pfad ohne Zuordnung → Exit 1 mit `✗`-Meldung
- [x] AK5 – Lock-Modus, `"`/`\` im Pfad → Exit 0, Listen byte-genau
- [x] AK6 – Zeilenumbruch im Pfad → Exit 2, keine zerteilte Ausgabe
- [x] AK7 – Mutationsbeleg: Tests zu AK2–AK6 rot gegen `main` vor dem Fix (Beleg unter „Technische Notizen“)
- [x] AK8 – keine Verhaltensänderung für das Repo selbst, Suite grün (2844/0 Factory-Suite, 250/0 Projekt-Suite; Repo-Lauf
  `249 Dateien (factory: 131, project: 118)`, Exit 0. Ein Byte-Diff von `--list` gegen die `main`-Fassung war in dieser
  Session nicht freigegeben. Begründung: für Pfade ohne `"`/`\`/Steuerzeichen/`|` liefern `ls-files -z` und das bisherige
  Lesen dieselben Pfade, und die Zuordnungslogik ist unverändert)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
- Kein ADR-Trigger (lokaler Bugfix, kein neues Format, keine neue Abhängigkeit) – `/architecture` entfällt.
- Reproduktion: Wegwerf-Repo mit `docs/a"b.md`, `docs/a\b.md`, `docs/a|b.md`, Tab-Pfad und Muster `docs/**` →
  „3 von 5 Dateien ohne eindeutige Zuordnung" bei 6 getrackten Dateien (`|`-Pfad fehlt in der Zählung).
- Fix: `load_git_tracked_files` liest `git ls-files -z` (statt `-c core.quotepath=false ls-files`) in eine Temp-Datei,
  prüft per `tr` auf Zeilenumbruch (Exit 2) und wandelt NUL → `\n`. Der Tabellenmodus wertet jede Zeile ganz aus (kein
  `-F'|'`/`NF == 1` mehr). `OWNERSHIP_FILE_LIST` bleibt unverändert (Spec: nicht inbegriffen).
- Tests: Block „Factory-Issue #63" in `scripts/checks/tests/run-tests.sh` (nach F-22.5), gegen echtes git mit
  `core.quotepath true`.

### AK7 – Mutationsbeleg (2026-11-25)
Kommando: `bash scripts/checks/tests/run-tests.sh` mit den neuen Tests und unverändertem `ownership-check.sh` (= Stand
`main`, vor dem Fix). Ergebnis im Block #63: AK1 2/2 grün (Regression, erwartet); rot: AK2 3/3, AK3 2/3 (Exit 0 war schon
„grün“ – genau das fail-open), AK4 2/2 (war Exit 0), AK5 4/4 (war Exit 1 „nicht getrackt“), AK6 18/18 (Tabellenmodus Exit 1,
Lock-Modus Exit 0 mit zerteilten Pfaden). Jedes AK2–AK6 hat damit mindestens eine rote Assertion.

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
