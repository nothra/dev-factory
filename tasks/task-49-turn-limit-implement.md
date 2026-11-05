# Task 49: turn-limit-implement

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Das Turn-Budget von `/implement` wird nach der AK-Zahl der Spec gestaffelt: 1–5 AK → 20, 6–11 → 40,
ab 12 → 60 Turns. Fehlt die Spec, fehlt ihr AK-Abschnitt oder hat er 0 AK, stoppt die Pipeline vor
`/implement`. `/bug-fix` und die übrigen Skills bleiben unverändert.
Spec: `docs/specs/spec-49-turn-limit-implement.md`

## Akzeptanzkriterien
Volltext (GIVEN/WHEN/THEN) und Fehlerszenarien F1–F6: Spec.

- [ ] AK1: 5 AK → `max 20 turns`
- [ ] AK2: 6 AK → `max 40 turns`
- [ ] AK3: 11 AK → `max 40 turns`
- [ ] AK4: 12 AK → `max 60 turns`
- [ ] AK5: 18 AK (Größe Task 47) → `max 60 turns`
- [ ] AK6: Rework-Iteration nach `/review` nutzt dieselbe Stufe
- [ ] AK7: `- [ ]` und `- [x]` zählen gleich (Zählweise wie Modellwahl)
- [ ] AK8: Spec fehlt → Stopp vor `/implement`, Exit ≠ 0, Meldung mit Task-ID + Hinweis `/requirements`
- [ ] AK9: Abschnitt `## Akzeptanzkriterien` fehlt → Stopp
- [ ] AK10: 0 AK → Stopp
- [ ] AK11: Stopp greift auch mit `--dry-run`
- [ ] AK12: Stopp greift auch mit gesetztem `MAX_TURNS`
- [ ] AK13: `MAX_TURNS` überschreibt bei gültiger Spec die Staffelung (Bestand)
- [ ] AK14: Stufen-Override in `factory.config.yml` wirkt
- [ ] AK15: Gate lehnt Stufen-Budget 81 ab
- [ ] AK16: Gate lehnt Stufen-Budget 0 / Nicht-Integer ab
- [ ] AK17: Budgets der übrigen Skills unverändert
- [ ] AK18: `bug-fix` behält festes `max_turns: 20`
- [ ] AK19: Repo-Config setzt keine `skills.*`; Budget kommt end-to-end aus den Defaults (#348)
- [ ] AK20: `@reason` + `@tradeoff` (Kosten-Wirkung) an der Staffelung in `factory.defaults.yml`
- [ ] AK21: Doku (`factory.config.yml.example`, `configure-factory.md`, `OPERATING.md`) beschreibt Staffelung; Example nennt Obergrenze 80

## Technische Notizen
Entscheidung: [Factory-ADR-065](../docs/factory/adr/065-turn-budget-nach-ak-zahl.md) (Proposed → beim Umsetzen Accepted).

- Config: `skills.implement.max_turns_by_size: { signal: proxy, mid: {from: 6, max_turns: 40}, high: {from: 12, max_turns: 60} }`;
  `max_turns: 20` bleibt Basis (1–5 AK).
- Lib `scripts/lib/tier-select.sh`: neue reine Funktionen `select_max_turns` (Fail-Safe: `high`) und
  `spec_file_for` (eine Spec-Auflösung für Preflight, Modell- und Turn-Wahl, F4); Kopfkommentar mitpflegen.
- `run-pipeline.sh`: `get_max_turns <skill> [task_id]`; `preflight_checks` stoppt bei fehlender Spec,
  fehlendem AK-Abschnitt oder 0 AK mit je eigener Meldung. Kein Interrupt.
- Gate `config-validation-check.sh`: Regel 4d (Signal, `mid.from >= 2`, `high.from > mid.from`, Budgets in `[1, 80]`).
- Doku: `factory.config.yml.example` (auch Obergrenze 80), `configure-factory.md`, `OPERATING.md`,
  `CHANGELOG.md` (Breaking: Stopp ohne Spec); Notizen in ADR-038/ADR-010.
- Reihenfolge: (1) Spec-Fixture-Helfer für die Test-Scaffolds, Suite grün → (2) Lib + Gate →
  (3) Preflight + `get_max_turns` → (4) Doku/ADR-Pflege. In getrennten Skill-Läufen, nicht `run-pipeline.sh`.

## Offene Fragen
- [x] Q1–Q3 durch Factory-ADR-065 beantwortet (siehe Spec).
- Hinweis: Rund 116 `run-pipeline.sh`-Aufrufe in der Self-Test-Suite laufen ohne Spec und brauchen eine
  Spec-Fixture (Teil dieser Task). Laut Lesson „Turn-Limit“ (> 10 AK) die Umsetzung in getrennten
  Skill-Läufen fahren.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `improvement/49-turn-limit-implement`
Erstellt: 2026-11-05 11:05
