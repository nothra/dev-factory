# Task 28: self-test-suite-projektdateien-klaeren

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
- [x] Fertig / PR erstellt

## Beschreibung
Die ausgelieferte Self-Test-Suite soll keine projekteigenen Dateien des echten Repos lesen. Offen ist nur der
Label-Drift-Guard (`#431 AK-I2`), der `docs/factory/PROJECT-CONTEXT.md` liest; er bekommt eine eigene Fixture.
Fundstelle (2) und die ADR-064-D6-Ergänzung sind durch AK-28a/28c (spec-23, PR #29) erledigt; die
Config-Validierung (3) bleibt (Entscheidung Q1). Spec: `docs/specs/spec-28-self-test-suite-projektdateien.md`.

## Akzeptanzkriterien
- [x] AK1: Label-Drift-Block grün bei verändertem/fehlendem `PROJECT-CONTEXT.md` des Repos (Fixture statt echter Datei)
- [x] AK2: die drei Mutationsfälle schlagen unverändert an (Assertions erhalten, Vorher/Nachher-Zählung)
- [x] AK3: Positivkontrolle – Fixture mit beschriebenem Label meldet keine Abweichung
- [x] AK4: Konsument mit eigenem `aspects_extra` ohne Beschreibung → Suite bleibt grün
- [x] AK5: Zustand des echten `PROJECT-CONTEXT.md`-Labelbereichs weiter geprüft (Projekt-Suite); kein Guard entfällt ersatzlos
- [x] AK6: Guard gegen Rückfall – kein Lesezugriff auf projekteigene Dateien außer `factory.config.yml` (Negativfall + fail-closed)
- [x] AK7: Task-Datei verweist auf AK-28a/28c als Beleg der Erledigung; ADR-064 D6 nicht doppelt ändern

## Technische Notizen
- **Q2 (Risiko real?):** Nein, soweit belegt – die Mutationsfälle prüfen nur „Meldung enthalten"; die Umstellung ist Härtung.
  Eine fehlende echte `PROJECT-CONTEXT.md` ließ zudem `flat_286` auf eine nicht vorhandene Datei laufen.
- **Umsetzung:** `label_drift_431` wandert nach `scripts/checks/tests/lib/assert-helpers.sh` (geteilt); die ausgelieferte Suite fährt
  den Guard gegen eine selbst gebaute Fixture-`PROJECT-CONTEXT.md` und eine Fixture-Config. Mutation 2 nutzt die Fixture-Config
  statt der echten `factory.config.yml`; die Ausdrücke aller drei Assertions sind unverändert.
- **Q3 (AK5):** Zustand der echten Datei prüft die Projekt-Suite (`#28 AK5`, 2 Assertions); kein ADR-Trigger.
- **Vorher/Nachher (ausgelieferte Suite):** 1887 → 1898 grün (+11: Positivkontrolle, Fixture-ohne-Label, 6 AK6-Mutationen,
  Positiv-Kontrolle `factory.config.yml`, fail-closed, AK6-Gesamtguard). Drei Mutations-Assertions: 3 → 3.
  Projekt-Suite: 143 → 145 grün.
- **AK7:** Fundstelle (2) (`.gitignore.project`, `.claude/settings.project.json` als Compose-Fixture) und die D6-Ergänzung in
  Factory-ADR-064 sind durch AK-28a/AK-28c aus `docs/specs/spec-23-factory-sync-lock-integritaets-gate.md` (PR #29) erledigt;
  ADR-064 D6 wird hier nicht erneut geändert. Fundstelle (3) bleibt bewusst (Entscheidung Q1).
- **Refactoring:** Die dreifach duplizierte Mutanten-Erzeugung im AK6-Block ist durch `mutant_28` ersetzt (Labels der Assertions
  unverändert, 1901 grün vorher/nachher). Review-Finding Issue #32 (indirekter Lesezugriff) bleibt außerhalb des Scopes.
- **Nicht mehr offen:** Q2 und Q3 sind damit beantwortet.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `test/28-self-test-suite-projektdateien-klaeren`
Erstellt: 2026-10-27 00:32
